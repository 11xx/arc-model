{-# LANGUAGE RecordWildCards #-}
{- | A compact plan for one history: which facts it records and which
observations it is decided under.

A scenario is a plan, not a ledger. 'Generators.build' interprets it into
events with coherent references, so shrinking can drop features without
ever leaving a dangling identifier: the causal references are regenerated,
not edited.
-}
module Scenario
    ( Scenario(..)
    , ActorPick(..)
    , GateMode(..)
    , defaultScenario
    , dangerPolicy
    , openPolicy
    , requireDeclaredPolicy
    , genAnyScenario
    , genIntegratable
    , shrinkScenario
    , namedScenarios
    ) where

import Arc.Model ( DebtKind(..), ExternalKind(..), Policy(..), VerdictKind(..) )
import Arc.Model.Policy qualified as Policy

import Test.QuickCheck


-- | Which identity records the verdict.
data ActorPick = ActorIndependent
               | ActorContributor
               | ActorAssumed
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | How the required gate's evidence relates to the declaration, tree, and
-- environment in force. The declared gate always names a probe.
data GateMode = EvidenceCovered
              | EvidenceFailing
              | EvidenceOtherTree
              | EvidenceShapeMoved
              | EvidenceOtherEnvironment
              | EvidenceUnrecordedEnvironment
              | EvidenceProbeFailed
              | EvidenceRecordUnreadable
              | EvidenceOmitted
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Scenario = Scenario
  { patchsets         :: !Int
  , verdictOnFirst    :: !Bool
  , reviewer          :: !(Maybe ActorPick)
  , verdict           :: !VerdictKind
  , provisional       :: !Bool
  , extraContributor  :: !Bool
  , externalVerdict   :: !(Maybe ExternalKind)   -- ^ An upstream decision about the latest head.
  , debt              :: !(Maybe (Int, Maybe DebtKind))
  , gateMode          :: !GateMode
  , blockingFinding   :: !Bool
  , resolveFinding    :: !Bool
  , headMoved         :: !Bool
  , policy            :: !Policy
  , targetAfter       :: !Bool
  , policyAfter       :: !Bool
  , authorityWithheld :: !Bool                   -- ^ The store lacks integration authority when it executes.
  , audit             :: !(Maybe (VerdictKind, Bool))
  , episodeExpired    :: !Bool
  }
  deriving stock (Eq, Ord, Show)

defaultScenario :: Scenario
defaultScenario = Scenario
  { patchsets         = 1
  , verdictOnFirst    = False
  , reviewer          = Just ActorIndependent
  , verdict           = Approved
  , provisional       = False
  , extraContributor  = False
  , externalVerdict   = Nothing
  , debt              = Nothing
  , gateMode          = EvidenceCovered
  , blockingFinding   = False
  , resolveFinding    = False
  , headMoved         = False
  , policy            = dangerPolicy
  , targetAfter       = False
  , policyAfter       = False
  , authorityWithheld = False
  , audit             = Nothing
  , episodeExpired    = False
  }

dangerPolicy :: Policy
dangerPolicy = Policy
  { independentVerdictRequired = True
  , forbidSelfApproval         = True
  , requireDeclaredActor       = False
  }

openPolicy :: Policy
openPolicy = Policy
  { independentVerdictRequired = False
  , forbidSelfApproval         = False
  , requireDeclaredActor       = False
  }

requireDeclaredPolicy :: Policy
requireDeclaredPolicy = dangerPolicy { Policy.requireDeclaredActor = True }

{- | Histories worth naming: each pins one rule the model states, so a reader
of a differential report can find the case by what it exercises rather than
by a seed.
-}
namedScenarios :: [(String, Scenario)]
namedScenarios =
  [ ("approved",                   defaultScenario)
  , ("contributor-reviewer",       defaultScenario { reviewer = Just ActorContributor })
  , ("assumed-reviewer",           defaultScenario { reviewer = Just ActorAssumed })
  , ("assumed-reviewer-open",      defaultScenario { reviewer = Just ActorAssumed, policy = openPolicy })
  , ("self-approval-open",         defaultScenario { reviewer = Just ActorContributor, policy = openPolicy })
  , ("changes-requested",          defaultScenario { verdict = ChangesRequested })
  , ("comment-only",               defaultScenario { verdict = CommentOnly })
  , ("unreviewed",                 defaultScenario { reviewer = Nothing })
  , ("waived",                     defaultScenario { reviewer = Nothing, debt = Just (1, Nothing) })
  , ("waiver-expired",             defaultScenario { reviewer = Nothing, debt = Just (1, Nothing), patchsets = 2 })
  , ("waived-contributor",         defaultScenario { reviewer = Just ActorContributor, debt = Just (1, Nothing) })
  , ("stale-approval",             defaultScenario { patchsets = 2, verdictOnFirst = True })
  , ("finding-open",               defaultScenario { blockingFinding = True })
  , ("finding-resolved",           defaultScenario { blockingFinding = True, resolveFinding = True })
  , ("head-moved",                 defaultScenario { headMoved = True })
  , ("gate-omitted",               defaultScenario { gateMode = EvidenceOmitted })
  , ("gate-failed",                defaultScenario { gateMode = EvidenceFailing })
  , ("gate-other-tree",            defaultScenario { gateMode = EvidenceOtherTree, patchsets = 2 })
  , ("gate-declaration-changed",   defaultScenario { gateMode = EvidenceShapeMoved })
  , ("gate-other-environment",     defaultScenario { gateMode = EvidenceOtherEnvironment })
  , ("gate-environment-unrecorded", defaultScenario { gateMode = EvidenceUnrecordedEnvironment })
  , ("gate-probe-failed",          defaultScenario { gateMode = EvidenceProbeFailed })
  , ("external-approved-open",     defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = openPolicy })
  , ("external-approved-danger",   defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved })
  , ("external-beside-local",      defaultScenario { externalVerdict = Just ExternalApproved })
  , ("external-changes-requested", defaultScenario { externalVerdict = Just ExternalChangesRequested })
  , ("external-over-waiver",       defaultScenario { reviewer = Nothing, debt = Just (1, Nothing), externalVerdict = Just ExternalChangesRequested })
  , ("external-rejected",          defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalRejected, policy = openPolicy })
  , ("extra-contributor",          defaultScenario { extraContributor = True })
  ]

-- generation

-- | A generator that reaches every feature the suite claims to exercise.
genAnyScenario :: Gen Scenario
genAnyScenario = do
  patchsets         <- choose (1, 3)
  verdictOnFirst    <- frequency [(2, pure False), (1, pure True)]
  reviewer          <- frequency [(1, pure Nothing), (3, Just <$> arbitrary), (2, pure (Just ActorIndependent))]
  verdict           <- elements [Approved, Approved, ChangesRequested, CommentOnly]
  provisional       <- frequency [(4, pure False), (1, pure True)]
  extraContributor  <- arbitrary
  externalVerdict   <- frequency [(3, pure Nothing), (2, pure (Just ExternalApproved)), (1, pure (Just ExternalChangesRequested)), (1, pure (Just ExternalRejected))]
  debt              <- frequency [(2, pure Nothing), (2, debtFor patchsets)]
  gateMode          <- frequency ((8, pure EvidenceCovered) : [ (1, pure mode) | mode <- [minBound .. maxBound], mode /= EvidenceCovered ])
  blockingFinding   <- frequency [(3, pure False), (1, pure True)]
  resolveFinding    <- frequency [(4, pure False), (1, pure True)]
  headMoved         <- frequency [(4, pure False), (1, pure True)]
  policy            <- elements [dangerPolicy, dangerPolicy, openPolicy, requireDeclaredPolicy]
  targetAfter       <- frequency [(4, pure False), (1, pure True)]
  policyAfter       <- frequency [(4, pure False), (1, pure True)]
  authorityWithheld <- frequency [(5, pure False), (1, pure True)]
  audit             <- frequency [(2, pure Nothing), (1, Just <$> ((,) <$> elements [Approved, ChangesRequested] <*> arbitrary))]
  episodeExpired    <- arbitrary
  pure Scenario {..}

debtFor :: Int -> Gen (Maybe (Int, Maybe DebtKind))
debtFor count = do
  index <- choose (1, count)
  kind  <- frequency
    [ (1, pure Nothing)
    , (1, Just <$> elements [NothingRead, MergeResolutionUnread, RepairUnread, ContributorOnly, IndependentReview])
    ]
  pure (Just (index, kind))

-- | A generator restricted to histories an integration would permit. These
-- are the histories a one-invalid-transition mutation is applied to.
genIntegratable :: Gen Scenario
genIntegratable = do
  count            <- choose (1, 3)
  withApproval     <- frequency [(3, pure True), (1, pure False)]
  extraContributor <- arbitrary
  externalVerdict  <- frequency [(3, pure Nothing), (1, pure (Just ExternalApproved))]
  debt             <- frequency [(2, pure Nothing), (2, debtFor count)]
  provisional      <- frequency [(4, pure False), (1, pure True)]
  episodeExpired   <- arbitrary
  audit            <- frequency [(2, pure Nothing), (1, Just <$> ((,) <$> elements [Approved, ChangesRequested] <*> pure True))]
  pure defaultScenario
    { patchsets        = count
    , reviewer         = if withApproval then Just ActorIndependent else Nothing
    , extraContributor = extraContributor
    , externalVerdict  = externalVerdict
    , debt             = if withApproval then debt else Just (count, Nothing)
    , provisional      = provisional
    , episodeExpired   = episodeExpired
    , audit            = audit
    , policy           = dangerPolicy
    }

instance Arbitrary Scenario where
  arbitrary = genAnyScenario
  shrink    = shrinkScenario

instance Arbitrary ActorPick where
  arbitrary    = elements [minBound .. maxBound]
  shrink value = [ candidate | candidate <- [minBound .. value], candidate /= value ]

instance Arbitrary GateMode where
  arbitrary    = elements [minBound .. maxBound]
  shrink value = [ candidate | candidate <- [minBound .. value], candidate /= value ]

{- | Structural shrinking. References are positions, so a shrink that would
leave a reference dangling is filtered out rather than edited: every
candidate keeps the causal references its events need.
-}
shrinkScenario :: Scenario -> [Scenario]
shrinkScenario scenario =
  [ candidate
  | candidate <- candidates
  , all (<= candidate.patchsets) (referencedPatchsets candidate)
  ]
  where
    candidates = concat
      [ [ scenario { patchsets = count }         | count <- [1 .. scenario.patchsets - 1] ]
      , [ scenario { verdictOnFirst = False }    | scenario.verdictOnFirst ]
      , [ scenario { reviewer = Nothing }        | scenario.reviewer /= Nothing ]
      , [ scenario { verdict = Approved }        | scenario.verdict /= Approved ]
      , [ scenario { provisional = False }       | scenario.provisional ]
      , [ scenario { extraContributor = False }  | scenario.extraContributor ]
      , [ scenario { externalVerdict = Nothing } | scenario.externalVerdict /= Nothing ]
      , [ scenario { debt = Nothing }            | scenario.debt /= Nothing ]
      , [ scenario { gateMode = mode }           | mode <- [minBound .. scenario.gateMode], mode /= scenario.gateMode ]
      , [ scenario { blockingFinding = False }   | scenario.blockingFinding ]
      , [ scenario { resolveFinding = False }    | scenario.resolveFinding ]
      , [ scenario { headMoved = False }         | scenario.headMoved ]
      , [ scenario { policy = openPolicy }       | scenario.policy /= openPolicy ]
      , [ scenario { targetAfter = False }       | scenario.targetAfter ]
      , [ scenario { policyAfter = False }       | scenario.policyAfter ]
      , [ scenario { authorityWithheld = False } | scenario.authorityWithheld ]
      , [ scenario { audit = Nothing }           | scenario.audit /= Nothing ]
      , [ scenario { episodeExpired = False }    | scenario.episodeExpired ]
      ]
    referencedPatchsets current = case current.debt of
      Nothing         -> []
      Just (index, _) -> [index]
