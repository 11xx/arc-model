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
    , expectedCoverage
    , recordedText
    , compareCoverage
    , Comparison(..)
    , Kind(..)
    , Adjudication(..)
    , compareAnswer
    , kindText
    ) where

import Arc.Model
import Differential.Arc ( Answer(..), DryRun(..), PostIntegration(..), checkRefusedConflictingGates )
import Generators ( Built(..), build, reverts )
import Scenario ( ActorPick(..), GateMode(..), Scenario(..) )

import Control.Applicative ( (<|>) )
import Data.Maybe ( fromMaybe, isJust, isNothing )
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
      -- refused only at execution, which a check never reaches
      RefusedAuthorityWithheld         -> []
      RefusedUndeclaredActor           -> []
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
  | executionAgrees wanted dry = Agreed
  | otherwise = orAdjudicated (adjudicateExecution scenario built wanted dry <|> iteratingExecution) $ explainedBy scenario $ \reread ->
      let rebuilt = build reread in compareExecution reread rebuilt (expectedExecution rebuilt rebuilt.execution) dry
  where
    -- the refusal arc's check reports for an iterating change leaves the
    -- approval out; with it left out, the dry run agrees or falls under a
    -- rule of its own
    iteratingExecution = do
      StoodDown refused <- Just wanted
      withoutApproval   <- iteratingReading scenario refused
      let reread = StoodDown withoutApproval
      if executionAgrees reread dry || isJust (adjudicateExecution scenario built reread dry)
        then Just iteratingAdjudication
        else Nothing

-- | Whether a dry run is the model's execution. A dry run that would
-- integrate answers beside a check that is ready and names no blocker.
executionAgrees :: Execution -> DryRun -> Bool
executionAgrees wanted dry = case wanted of
  WouldIntegrate    -> dry.exit == 0 && dry.after.ready && Set.null dry.after.blockers
  AuthorityRefused  -> dry.exit == 17
  StoodDown refused -> dry.exit `notElem` [0, 17] && not dry.after.ready && dry.after.blockers == refused

{- | The blockers an arc that reads C11 as (ii) reports for an iterating
change: the model's, without the approval, since such an arc reports the
iterating blocker instead of requesting a review. Nothing where the change
is not iterating or no approval ground stands.
-}
iteratingReading :: Scenario -> Set String -> Maybe (Set String)
iteratingReading scenario wanted
  | scenario.iterating
  , Set.member "iterating" wanted
  , Set.member "no-valid-approval" wanted
  = Just (Set.delete "no-valid-approval" wanted)
  | otherwise = Nothing

iteratingAdjudication :: Adjudication
iteratingAdjudication = Adjudication
  { kind   = Unsettled
  , reason = "iterating without approval: arc reports iterating instead of requesting a review (C11 reading (ii)); the model reads (i), the missing approval beside it"
  }

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
  , dry.after.ready
  , Set.null dry.after.blockers
  = Just Adjudication
      { kind   = Unsettled
      , reason = "policy motion: arc decides again under the policy in force at integration, which permits; the model acts only on the decision made before the policy moved"
      }
  -- a refused decision in a store without authority: arc refuses the store
  -- before it reads readiness, the model answers with the decision's
  -- refusal, and the check beside the dry run refuses on exactly its grounds
  | StoodDown refused <- wanted
  , scenario.authorityWithheld
  , not (isPermitted built.decision)
  , dry.exit == 17
  , not dry.after.ready
  , dry.after.blockers == refused
  = Just Adjudication
      { kind   = Unsettled
      , reason = "authority at execution: arc refuses a store without authority before readiness; the model's execute answers a refused decision with its refusal"
      }
  | otherwise = Nothing

{- | The model's post-integration answers, mapped onto what arc records. An
authorization is the slots of arc's authorization basis it names:
'AuthorizedByVerdict' the verdict, 'AuthorizedByWaiver' the debt,
'AuthorizedByVerdictUnderWaiver' both, and 'AuthorizedByExternalVerdict'
the external approval. The audit verdict is the newest audit's; the open
findings are the audit findings nobody disposed of; a review is owed where
a debt authorized the merge and no read fulfilled it. The model's
@approved@ has no field in arc and is not compared: arc keeps the
authorization and the audit verdicts, which is the pair the model reads it
from.
-}
expectedCoverage :: Maybe Authorization -> CoverageAfterIntegration -> PostIntegration
expectedCoverage authorization coverage = PostIntegration
  { integrated        = isJust authorization
  , basis             = maybe Set.empty slotsOf authorization
  , auditVerdict      = verdictText <$> coverage.verdict
  , openAuditFindings = length coverage.openFindings
  , owed              = isJust coverage.debt && isNothing coverage.read
  }
  where
    slotsOf = Set.fromList . \case
      AuthorizedByVerdict _              -> ["verdict"]
      AuthorizedByWaiver _               -> ["debt"]
      AuthorizedByVerdictUnderWaiver _ _ -> ["verdict", "debt"]
      AuthorizedByExternalVerdict _      -> ["external"]
    verdictText = \case
      Approved         -> "approved"
      ChangesRequested -> "changes-requested"
      CommentOnly      -> "comment-only"

recordedText :: PostIntegration -> String
recordedText found
  | not found.integrated = "{not integrated}"
  | otherwise = "{basis " <> unwords (Set.toList found.basis)
      <> "; audit " <> fromMaybe "none" found.auditVerdict
      <> "; open audit findings " <> show found.openAuditFindings
      <> (if found.owed then "; review owed" else "") <> "}"

compareCoverage :: Scenario -> Built -> PostIntegration -> PostIntegration -> Comparison
compareCoverage scenario built wanted found
  | wanted == found = Agreed
  | otherwise       = orAdjudicated (adjudicateCoverage scenario built wanted found) $ explainedBy scenario $ \reread ->
      let rebuilt = build reread
      in compareCoverage reread rebuilt (expectedCoverage (historicalAuthorization rebuilt.finalState) (coverageAfterIntegration rebuilt.finalState)) found

-- | The coverage disagreements that have been read and classified.
adjudicateCoverage :: Scenario -> Built -> PostIntegration -> PostIntegration -> Maybe Adjudication
adjudicateCoverage scenario built wanted found
  -- an external approval beside the verdict arc witnessed: arc records both
  -- in the basis, the model's authorization names the witnessed verdict
  | wanted.basis == Set.fromList ["verdict"]
  , found.basis == Set.fromList ["verdict", "external"]
  , wanted.integrated == found.integrated
  , wanted.auditVerdict == found.auditVerdict
  , wanted.openAuditFindings == found.openAuditFindings
  , wanted.owed == found.owed
  , scenario.externalVerdict == Just ExternalApproved
  = Just Adjudication
      { kind   = Unsettled
      , reason = "external beside local: arc records the external approval beside the witnessed verdict; the model's basis names the witnessed verdict alone"
      }
  -- a verdict from an undeclared reviewer where policy requires a declared
  -- actor: arc refuses to record it, the model's ledger holds it, so arc's
  -- basis lacks the verdict the model's names beside a waiver
  | scenario.policy.requireDeclaredActor
  , scenario.reviewer == Just ActorAssumed
  , Set.member "verdict" wanted.basis
  , found.basis == Set.delete "verdict" wanted.basis
  , wanted.integrated == found.integrated
  , wanted.auditVerdict == found.auditVerdict
  , wanted.openAuditFindings == found.openAuditFindings
  , wanted.owed == found.owed
  = Just Adjudication
      { kind   = Encoding
      , reason = "undeclared reviewer: arc refuses to record a verdict nobody declared where policy requires a declared actor; the model's ledger holds it"
      }
  -- a policy that moved and now permits: arc integrates under it, the model
  -- acts only on the decision made before it moved. What arc records has to
  -- be, field for field, what the model records when it decides afresh
  -- under the moved policy
  | scenario.policyAfter
  , not wanted.integrated
  , redecided.integrated
  , found == redecided
  = Just Adjudication
      { kind   = Unsettled
      , reason = "policy motion: arc decides again under the policy in force at integration, which permits; the model acts only on the decision made before the policy moved"
      }
  | otherwise = Nothing
  where
    redecided = expectedCoverage (historicalAuthorization built.redecidedState) (coverageAfterIntegration built.redecidedState)

{- | The scenario as an arc that reads gate and policy declarations from the
target's commits sees it. The plan moves a declaration and a policy with
uncommitted edits of the worktree's files, which such an arc never reads,
so for it nothing moved. Nothing where the scenario moves neither.
-}
asReadFromTarget :: Scenario -> Maybe Scenario
asReadFromTarget scenario
  | scenario.gateMode == EvidenceShapeMoved || scenario.policyAfter = Just scenario
      { Scenario.gateMode    = if scenario.gateMode == EvidenceShapeMoved then EvidenceCovered else scenario.gateMode
      , Scenario.policyAfter = False
      }
  | otherwise = Nothing

{- | The pass a newer run hides where arc lets the newest run at the evaluated
tree decide whatever environment it recorded: the scenario without the
further runs at the tree its own run reads, which is the tree the latest
patchset returns to, recorded before that run. Classified by what the newer
run recorded: another environment is C14's settled rule, so a Rust defect;
no environment is a reading C14 leaves open.
-}
asHiddenByNewerRun :: Scenario -> Maybe (Scenario, Adjudication)
asHiddenByNewerRun scenario
  | scenario.gateMode `elem` [EvidenceOtherEnvironment, EvidenceUnrecordedEnvironment]
  , reverts scenario
  , not (null hidden)
  = Just (scenario { Scenario.gateRuns = [ run | run <- scenario.gateRuns, run `notElem` hidden ] }, adjudication)
  | otherwise = Nothing
  where
    hidden = [ run | run@(index, GatePass) <- scenario.gateRuns, index == scenario.patchsets - 2 ]
    adjudication
      | scenario.gateMode == EvidenceOtherEnvironment = Adjudication
          { kind   = RustDefect
          , reason = "a newer run from another environment hides the pass here: arc lets it decide the gate at the evaluated tree, where C14 keys evidence by environment and such a record never hides one that answers"
          }
      | otherwise = Adjudication
          { kind   = Unsettled
          , reason = "a newer run recording no environment hides the pass here: arc reads it as under the key in force (C14, unsettled reading (ii)); the model keys it apart, so it neither answers nor hides (reading (i))"
          }

{- | A disagreement a known reading explains: arc's answer is the model's own
for the scenario as that reading sees it, agreed or adjudicated as that
scenario would be. The readings are arc's movement since the pin, which
reads declarations and policy from the target's commits, and a newer run
hiding an older pass at the evaluated tree.
-}
explainedBy :: Scenario -> (Scenario -> Comparison) -> Comparison
explainedBy scenario compareReread = case [ adjudication | (reread, adjudication) <- readings, compareReread reread /= Disagreed ] of
  adjudication : _ -> Adjudicated adjudication
  []               -> Disagreed
  where
    readings = concat
      [ [ (unmoved, arcMoved) | Just unmoved <- [asReadFromTarget scenario] ]
      , [ reread | Just reread <- [asHiddenByNewerRun scenario] ]
      ]
    arcMoved = Adjudication
      { kind   = ArcMoved
      , reason = "arc moved since the pin: it reads gate and policy declarations from the target's commits (C12 reading (ii)), so the plan's uncommitted edit moves nothing, and arc answers as the model does with nothing moved"
      }

-- | A reading that explains arc's answer outright is asked first; a class of
-- the history's own shape is asked only of a disagreement no reading
-- explains.
orAdjudicated :: Maybe Adjudication -> Comparison -> Comparison
orAdjudicated rule = \case
  Disagreed -> maybe Disagreed Adjudicated rule
  moved     -> moved

-- | Which side is wrong, whether the contract is unsettled, or whether arc
-- moved since the comparison revision in a way the contract already records.
-- An encoding difference is a fact about the CLI's shape, not about either
-- decision.
data Kind = RustDefect
          | ModelDefect
          | Unsettled
          | Encoding
          | ArcMoved
  deriving stock (Eq, Ord, Show)

kindText :: Kind -> String
kindText = \case
  RustDefect  -> "rust-defect"
  ModelDefect -> "model-defect"
  Unsettled   -> "unsettled"
  Encoding    -> "encoding"
  ArcMoved    -> "arc-moved"

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
  | otherwise = orAdjudicated (adjudicate scenario wanted answer) $ explainedBy scenario $ \reread ->
      let rebuilt = build reread in compareAnswer reread (expected (refusals rebuilt.observation rebuilt.state)) answer

{- | The disagreement classes that have been read and classified, each with
the exact scenario shape and blocker sets it applies to. A new disagreement
is reported unclassified until somebody reads it, names its class here, and
says why.
-}
adjudicate :: Scenario -> Set String -> Answer -> Maybe Adjudication
adjudicate scenario wanted answer
  -- an iterating change: arc reports the iterating blocker instead of
  -- requesting a review, the model reports the missing approval beside it
  | Just withoutApproval <- iteratingReading scenario wanted
  , not answer.ready
  , answer.blockers == withoutApproval
  = Just iteratingAdjudication
  | otherwise = Nothing
