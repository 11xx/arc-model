{- | Comparing the model's grounds with arc's blockers.

Arc's vocabulary is coarser than the model's: five ways an approval can
fail to stand are one @no-valid-approval@, and a moved head shows up as an
invalid approval and missing gate evidence rather than as its own blocker.
The mapping here is the model's claim about how its grounds appear in
arc's answer; a case where the claim fails is a disagreement, and a
disagreement is classified, never dropped.
-}
module Differential.Compare
    ( expected
    , Comparison(..)
    , Kind(..)
    , Adjudication(..)
    , compareAnswer
    , kindText
    ) where

import Arc.Model
import Differential.Arc ( Answer(..) )
import Scenario ( Scenario(..) )

import Data.Set ( Set )
import Data.Set qualified as Set


-- | The blockers arc is expected to report for these grounds.
expected :: [Refusal] -> Set String
expected = Set.fromList . concatMap blockersOf
  where
    blockersOf = \case
      RefusedClosed _                  -> ["closed"]
      RefusedIterating                 -> ["iterating"]
      RefusedBlockedBy _               -> ["blocked-by-changes"]
      RefusedNoPatchset                -> ["no-valid-approval", "gates-not-green"]
      -- arc binds approval validity and gate lookup to the head, so a moved
      -- head invalidates both rather than being named
      RefusedHeadMoved _ _             -> ["no-valid-approval", "gates-not-green"]
      RefusedBlockingFindings _        -> ["blocking-findings"]
      RefusedContestedVerdict _        -> ["no-valid-approval"]
      RefusedVerdictStands _ _         -> ["no-valid-approval"]
      RefusedExternalVerdictStands _ _ -> ["no-valid-approval"]
      RefusedStaleApproval _ _         -> ["no-valid-approval"]
      RefusedSelfApproval {}           -> ["no-valid-approval"]
      RefusedNoApproval                -> ["no-valid-approval"]
      RefusedGates _                   -> ["gates-not-green"]
      RefusedHoldActive _              -> ["hold-active"]
      -- arc refuses the undeclared write itself; nothing reaches check
      RefusedUndeclaredActor           -> []
      RefusedAuthorityWithheld         -> []
      RefusedBasisMoved _              -> []

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
