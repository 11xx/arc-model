{- | Comparing the model's answers with arc's.

Arc's vocabulary is coarser than the model's: five ways an approval can
fail to stand are one @no-valid-approval@, and a moved head shows up as an
invalid approval and missing gate evidence rather than as its own blocker.
The mapping here is the model's claim about how its grounds appear in
arc's answer; a case where the claim fails is a disagreement, and a
disagreement is classified, never dropped.

The execution channel compares 'execute' with @arc integrate --dry-run@.
arc keeps no decision to re-check: it re-evaluates readiness when asked to
integrate, after refusing a store without integration authority (exit 17).
So a permitted plan is a dry run that would integrate, withheld authority
is exit 17, and any other refusal is a dry run that refuses on the blockers
the model's own grounds name under the observations of that moment.
-}
module Differential.Compare
    ( expected
    , Execution(..)
    , expectedExecution
    , executionText
    , compareExecution
    , Comparison(..)
    , Kind(..)
    , Adjudication(..)
    , compareAnswer
    , kindText
    ) where

import Arc.Model
import Differential.Arc ( Answer(..), DryRun(..), checkRefusedConflictingGates )
import Generators ( Built(..) )
import Scenario ( Scenario(..) )

import Data.Set ( Set )
import Data.Set qualified as Set


-- | The blockers arc is expected to report for these grounds.
expected :: [Refusal] -> Set String
expected = Set.fromList . concatMap blockersOf
  where
    blockersOf = \case
      -- arc refuses to check at all; the name is the differential's
      RefusedConflictingDeclarations _ -> [checkRefusedConflictingGates]
      RefusedClosed _                  -> ["closed"]
      RefusedIterating                 -> ["iterating"]
      RefusedBlockedBy _               -> ["blocked-by-changes"]
      RefusedNoPatchset                -> ["no-valid-approval", "gates-not-green"]
      -- arc binds approval validity and gate lookup to the head, so a moved
      -- or missing head invalidates both as well as being named, or not
      RefusedBranchMissing             -> ["branch-missing", "no-valid-approval", "gates-not-green"]
      RefusedHeadMoved _ _             -> ["no-valid-approval", "gates-not-green"]
      RefusedNeedsRebase               -> ["needs-rebase"]
      RefusedMergedTreeUnevaluated _   -> ["merged-tree-unevaluated"]
      RefusedBlockingFindings _        -> ["blocking-findings"]
      RefusedContestedVerdict _        -> ["no-valid-approval"]
      RefusedVerdictStands _ _         -> ["no-valid-approval"]
      RefusedExternalVerdictStands _ _ -> ["no-valid-approval"]
      RefusedStaleApproval _ _         -> ["no-valid-approval"]
      RefusedSelfApproval {}           -> ["no-valid-approval"]
      RefusedNoApproval                -> ["no-valid-approval"]
      RefusedGates _                   -> ["gates-not-green"]
      RefusedAcceptanceProbes _        -> ["acceptance-probes-not-green"]
      RefusedHoldActive _              -> ["hold-active"]
      -- arc refuses the undeclared write itself; nothing reaches check
      RefusedUndeclaredActor           -> []
      RefusedAuthorityWithheld         -> []
      RefusedBasisMoved _              -> []

-- | What an integration attempted after the moves would do, by the model.
data Execution = WouldIntegrate
               | AuthorityRefused
               | StoodDown (Set String)  -- ^ Refused, with the blockers arc's re-evaluation is expected to report.
  deriving stock (Eq, Show)

executionText :: Execution -> String
executionText = \case
  WouldIntegrate    -> "{would integrate}"
  AuthorityRefused  -> "{exit 17}"
  StoodDown refused -> "{refused " <> unwords (Set.toList refused) <> "}"

{- | The model's execution, mapped onto what a dry run reports. A refusal is
expected to show as the blockers of the model's grounds under the
observations of execution time, since those are what arc reads when it
re-evaluates.
-}
expectedExecution :: Built -> Either Refusal ExecutionPlan -> Execution
expectedExecution built = \case
  Right _                       -> WouldIntegrate
  Left RefusedAuthorityWithheld -> AuthorityRefused
  Left _                        -> StoodDown (expected (refusals built.executionObservation built.state))

compareExecution :: Scenario -> Built -> Execution -> DryRun -> Comparison
compareExecution scenario built wanted dry
  | agrees    = Agreed
  | otherwise = maybe Disagreed Adjudicated (adjudicateExecution scenario built wanted dry)
  where
    agrees = case wanted of
      WouldIntegrate    -> dry.exit == 0
      AuthorityRefused  -> dry.exit == 17
      StoodDown refused -> dry.exit `notElem` [0, 17] && not dry.after.ready && dry.after.blockers == refused

{- | The execution disagreements that have been read and classified, each
with the exact shape it applies to.
-}
adjudicateExecution :: Scenario -> Built -> Execution -> DryRun -> Maybe Adjudication
adjudicateExecution scenario built wanted dry
  -- a policy that moved and now permits: arc decides again under it, and
  -- the model acts only on the decision made before it moved, whether that
  -- decision permitted on a basis that no longer holds or refused
  | StoodDown refused <- wanted
  , Set.null refused
  , scenario.policyAfter
  , dry.exit == 0
  = Just Adjudication
      { kind   = Unsettled
      , reason = "policy motion: arc decides again under the policy in force at integration, which permits; the model acts only on the decision made before the policy moved"
      }
  -- a refused decision in a store without authority: arc refuses the store
  -- before it reads readiness, the model answers with the decision's refusal
  | StoodDown _ <- wanted
  , scenario.authorityWithheld
  , not (isPermitted built.decision)
  , dry.exit == 17
  = Just Adjudication
      { kind   = Unsettled
      , reason = "authority at execution: arc refuses a store without authority before readiness; the model's execute answers a refused decision with its refusal"
      }
  | otherwise = Nothing

-- | Which side is wrong, or whether the contract is unsettled. An encoding
-- difference is a fact about the CLI's shape, not about either decision.
data Kind = RustDefect
          | ModelDefect
          | Unsettled
          | Encoding
  deriving stock (Eq, Ord, Show)

kindText :: Kind -> String
kindText = \case
  RustDefect  -> "rust-defect"
  ModelDefect -> "model-defect"
  Unsettled   -> "unsettled"
  Encoding    -> "encoding"

data Adjudication = Adjudication
  { kind   :: !Kind
  , reason :: !String
  }
  deriving stock (Eq, Show)

data Comparison = Agreed
                | Adjudicated Adjudication
                | Disagreed
  deriving stock (Eq, Show)

-- | Compare the expected blockers with arc's answer. Blockers the model does
-- not represent are disagreements in their own right: the model made no
-- claim about them, and a replay that produces one says the fixture drifted
-- from the scenario.
compareAnswer :: Scenario -> Set String -> Answer -> Comparison
compareAnswer scenario wanted answer
  | wanted == answer.blockers && Set.null wanted == answer.ready = Agreed
  | otherwise = maybe Disagreed Adjudicated (adjudicate scenario wanted answer)

{- | The disagreement classes that have been read and classified. None stands
at this comparison revision: every replayed history agrees once the model's
grounds are mapped onto arc's vocabulary. A new disagreement is reported
unclassified until somebody reads it, names its class here with the exact
scenario shape and blocker sets it applies to, and says why.
-}
adjudicate :: Scenario -> Set String -> Answer -> Maybe Adjudication
adjudicate _scenario _wanted _answer = Nothing
