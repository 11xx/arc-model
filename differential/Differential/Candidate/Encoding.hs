{- | A candidate plan as arc commands.

The candidate model's ledger is the event list 'Plan.buildEvents' records;
arc's is what @arc candidate@ and @arc context@ append. The encoding walks
the model's own events and maps each to the one command that records it,
then adds what the plan observes around them: the target the proposal names,
the environment the selection is made in, the requirements the brief
declares, and whether the promotion's effect is observed.

Two steps come before the encoding. 'production' sets aside what the
candidate contract places outside the channel, for every plan alike, and
names what it set aside; the model then answers for the plan so projected.
'encode' refuses, naming why, a plan whose events or observations no arc
command can record. Neither ever approximates an event by a weaker one.

Coordinates the model names symbolically — trees, episodes, the brief's
file, declarations, environments, targets — are given arc meanings here and
realized by "Differential.Candidate.Replay":

* the destination is the change @work@, whose brief is the model's
  'briefRef'; 'otherBriefRef' is the brief of a second change, @other@;
* a read requirement or context reference at 'briefLocator' and
  'briefFirst' is the file @contract.md@ at the revision the brief is based
  on;
* a tree is a tree holding the fixture and a file naming the tree;
* an episode is a claim on the destination, held by an actor named after
  the episode and released before the next opens;
* a declaration is a gate command that names it, committed on the target
  before the runs and the selection that consume it;
* an environment is what the gate's probe prints;
* 'targetNow' is the target's head when the selection is asked, and any
  other target a proposal names is a head the target has since moved past.
-}
module Differential.Candidate.Encoding
    ( Case(..)
    , namedCases
    , SetAside(..)
    , setAsideText
    , production
    , Unexpressed(..)
    , unexpressedText
    , BriefOf(..)
    , Coverage(..)
    , Command(..)
    , Promoting(..)
    , Encoding(..)
    , encode
    , contractFile
    , destinationSlug
    , otherSlug
    ) where

import Arc.Candidate
import Arc.Model.Identifiers
import Arc.Model.Observed ( Observed(..) )
import Plan ( Built(..), EvidenceMode(..), Pick(..), Plan(..), Probe(..), ReadMode(..), ReviewerPick(..), TargetMode(..), briefFirst, briefLocator, briefRef, defaultPlan, otherBriefRef, probeRegistration, targetNow )

import Data.List ( nub )
import Data.Maybe ( listToMaybe )


-- | One row of the channel: a plan, and whether the required gate declares
-- an environment probe. Every generated plan declares one.
data Case = Case
  { label         :: !String
  , plan          :: !Plan
  , probeDeclared :: !Bool
  }

{- | The histories named for the channel, run before the generated ones:
the shapes arc's own candidate probes name, and the environment-probe
reading, which no generated plan reaches because every generated plan
declares a probe.
-}
namedCases :: [Case]
namedCases =
  [ named "candidate-default"                  defaultPlan
  , named "candidate-sibling-evidence-reused"  defaultPlan { Plan.evaluationOn = PickB, Plan.policy = ReuseOnMatchingCoordinates }
  , named "candidate-sibling-evidence-never"   defaultPlan { Plan.evaluationOn = PickB, Plan.policy = ReuseNever }
  , named "candidate-stale-target"             defaultPlan { Plan.targetMode = TargetStale }
  , named "candidate-stale-evaluation"         defaultPlan { Plan.evidence = EvidenceOtherDeclaration }
  , named "candidate-declared-only"            defaultPlan { Plan.readMode = BriefDeclaredOnly }
  , named "candidate-lead-repair"              defaultPlan { Plan.leadRepair = True }
  , named "candidate-basis-moved"              defaultPlan { Plan.targetAfter = True }
  , named "candidate-promotion-unobserved"     defaultPlan { Plan.promotionObserved = False }
  , named "candidate-parent-other-contract"    defaultPlan { Plan.probe = Just ProbeParentOtherContract }
  , named "candidate-adoption-drops-producer"  defaultPlan { Plan.probe = Just ProbeAdoptionDropsProducer }
  , named "candidate-different-trees"          defaultPlan { Plan.equalTree = False, Plan.thirdCandidate = True, Plan.probe = Just ProbeParentSameContract }
  , Case { label = "candidate-environment-unprobed", plan = defaultPlan { Plan.evidence = EvidenceEnvironmentOmitted }, probeDeclared = False }
  ]
  where
    named label plan = Case { label = label, plan = plan, probeDeclared = True }

-- | A part of a plan the channel sets aside before the model answers.
data SetAside = ReviewSetAside
              | DeclaredRootSetAside
              | ExpirySetAside
              | AmendmentSetAside
              | UnrequiredClaimSetAside
  deriving stock (Eq, Ord, Show, Enum, Bounded)

setAsideText :: SetAside -> String
setAsideText = \case
  ReviewSetAside          -> "review (ReviewRecord, the review shortfalls, Requirements.independentReview): outside the candidate contract; review authority binds to the destination patchset after promotion"
  DeclaredRootSetAside    -> "declared roots: arc builds none; its roots are selections and promotions"
  ExpirySetAside          -> "episode expiry: arc holds one live claim per change, so every episode is released before the next opens; liveness gates no write in either"
  AmendmentSetAside       -> "a later version of read context: it changes only what a reference resolves to, which no arc command reports for a candidate"
  UnrequiredClaimSetAside -> "an inference or a supply nothing requires: arc records neither for a candidate, and no compared answer rests on one"

{- | The plan as production states it, and what was set aside to get there.
'Requirements.independentReview' is 'False' in every production-mapped
plan, so a plan's review fields go with it.
-}
production :: Plan -> (Plan, [SetAside])
production plan = (projected, concat [ [ aside | changed ] | (aside, changed) <- asides ])
  where
    asides =
      [ (ReviewSetAside,          plan.reviewRequired || plan.reviewer /= ReviewerNone)
      , (DeclaredRootSetAside,    plan.declaredRoot /= Nothing)
      , (ExpirySetAside,          plan.episodeExpired)
      , (AmendmentSetAside,       plan.briefAmended)
      , (UnrequiredClaimSetAside, unrequiredClaim)
      ]
    unrequiredClaim = not plan.readRequired && plan.readMode `elem` [BriefInferredOnly, BriefSuppliedOnly]
    projected = plan
      { Plan.reviewRequired = False
      , Plan.reviewer       = ReviewerNone
      , Plan.declaredRoot   = Nothing
      , Plan.episodeExpired = False
      , Plan.briefAmended   = False
      , Plan.readMode       = if unrequiredClaim then BriefUnread else plan.readMode
      }

-- | Why a production plan has no encoding.
data Unexpressed = TargetUnobservable
                 | OutcomeAlwaysRecorded
                 | EvaluationAtOtherTree
                 | InferenceUnrecordable
                 | SupplyUnrecordable
                 | ReviewUnrecordable
                 | RootUnrecordable
                 | ExpiryUnrecordable
                 | ContextElsewhere
                 | ReadWithoutSubject
                 | BriefElsewhere
  deriving stock (Eq, Ord, Show)

unexpressedText :: Unexpressed -> String
unexpressedText = \case
  TargetUnobservable    -> "an unobserved target: arc reads the target at every selection"
  OutcomeAlwaysRecorded -> "an unknown outcome: arc records the result of every gate run"
  EvaluationAtOtherTree -> "an evaluation at a tree its registration does not name: arc runs a candidate's gates at its own tree"
  InferenceUnrecordable -> "only-inferred: arc records no inference a read requirement could rest on alone"
  SupplyUnrecordable    -> "only-supplied: arc's supplied context is the contract's own plan or opening artifact, never context supplied to an episode"
  ReviewUnrecordable    -> "a candidate review: production records none"
  RootUnrecordable      -> "a declared root: arc builds none"
  ExpiryUnrecordable    -> "an expiry apart from the release every episode ends with"
  ContextElsewhere      -> "context other than the brief's file at its first version"
  ReadWithoutSubject    -> "a read by an episode no registration cites: arc records a read on a subject"
  BriefElsewhere        -> "a brief other than the destination's or the other change's"

data BriefOf = DestinationBrief
             | OtherBrief
  deriving stock (Eq, Show)

data Coverage = CoversWhole
              | CoversLines !Int !Int
              | CoversUnknown
  deriving stock (Eq, Show)

-- | One arc or Git action of a replay, in the order it runs.
data Command
  = Claim !EpisodeId                               -- ^ Claim the destination as the episode's actor, and release it.
  | Register !BriefOf !Registration                -- ^ @candidate register@.
  | ReadContext !CandidateId !EpisodeId !ToolRecordId !Coverage  -- ^ @context read@ of the brief's file.
  | Declare !CandidateId !DeclaredKind !ActorId !(Maybe ToolRecordId)  -- ^ @context declare@ of the brief's file.
  | CaptureReport !ToolRecordId !Capture           -- ^ @context capture@.
  | Judge !Judgement                               -- ^ @candidate judge@.
  | DeclareGate !DeclarationId                     -- ^ Commit the required gate's declaration on the target, when it differs.
  | Evaluate !EvaluationId !CandidateId !ActorId !(Observed EnvironmentId) !Bool  -- ^ @candidate verify@; True fails the gate.
  deriving stock (Eq, Show)

-- | What becomes of a permitted selection's promotion.
data Promoting = PromoteAtSelection        -- ^ @select@ promotes at once.
               | StandDown                 -- ^ A dirty destination checkout refuses the effect: the effect is never observed.
               | StandDownThenMoveTarget   -- ^ The effect is refused, the target moves, and @candidate promote@ retries.
  deriving stock (Eq, Show)

data Encoding = Encoding
  { reuse         :: !ReusePolicy
  , probeDeclared :: !Bool
  , mustRead      :: ![Extent]                   -- ^ The brief's file, at the brief's base, over each extent.
  , trees         :: ![TreeId]
  , commands      :: ![Command]
  , declaration   :: !DeclarationId               -- ^ In force at the selection.
  , targetStale   :: !Bool                        -- ^ The proposal names a head the target has moved past.
  , chosen        :: !CandidateId
  , evaluations   :: ![EvaluationId]
  , environment   :: !(Observed EnvironmentId)    -- ^ What the probe prints where the selection is asked.
  , selector      :: !ActorId
  , promoting     :: !Promoting
  , probe         :: !(Maybe (BriefOf, Registration))
  , retire        :: ![CandidateId]               -- ^ Every registration, the probe last.
  }

-- | The file every read requirement and context reference names.
contractFile :: FilePath
contractFile = "contract.md"

destinationSlug, otherSlug :: String
destinationSlug = "work"
otherSlug       = "other"

{- | The commands that record a production plan's events and ask its
selection, or why there are none.
-}
encode :: Case -> Built -> Either Unexpressed Encoding
encode given built = do
  observedTarget built.observations.target
  mapM_ requirement built.requirements.reads
  requireNoReview
  recorded <- concat <$> mapM event built.events
  probed   <- traverse registered (probeRegistration given.plan)
  (_gate, required) <- maybe (Left ContextElsewhere) Right (listToMaybe built.requirements.gates)
  pure Encoding
    { reuse         = given.plan.policy
    , probeDeclared = given.probeDeclared
    , mustRead      = [ r.extent | r <- built.requirements.reads ]
    , trees         = nub ([ r.tree | Registered r <- built.events ] <> [ r.tree | Just (_, r) <- [probed] ])
    , commands      = recorded <> captured
    , declaration   = required
    , targetStale   = built.proposal.target /= targetNow
    , chosen        = built.proposal.chosen
    , evaluations   = built.proposal.evaluations
    , environment   = built.observations.environment
    , selector      = built.proposal.selector
    , promoting     = if given.plan.targetAfter then StandDownThenMoveTarget
                      else if given.plan.promotionObserved then PromoteAtSelection
                      else StandDown
    , probe         = probed
    , retire        = [ r.candidateId | Registered r <- built.events ] <> [ r.candidateId | Just (_, r) <- [probed] ]
    }
  where
    observedTarget = \case
      Observed _ -> Right ()
      Omitted    -> Left TargetUnobservable
    requirement r
      | r.locator == briefLocator && r.version == briefFirst = Right ()
      | otherwise                                            = Left ContextElsewhere
    -- a provider's report is per read record in arc and per referenced
    -- version in the model: every read of a reported version carries it
    captured =
      [ CaptureReport toolRead.record guarantee
      | ContextRecorded (Read toolRead) <- built.events
      , Just key       <- [contextKey toolRead.reference]
      , Just guarantee <- [lookup key built.observations.captures]
      ]
    requireNoReview
      | built.requirements.independentReview = Left ReviewUnrecordable
      | otherwise                            = Right ()
    registered r
      | r.brief == briefRef      = Right (DestinationBrief, r)
      | r.brief == otherBriefRef = Right (OtherBrief, r)
      | otherwise                = Left BriefElsewhere
    atBrief reference
      | reference.locator == briefLocator && reference.version == Observed briefFirst = Right ()
      | otherwise                                                                    = Left ContextElsewhere
    event = \case
      EpisodeOpened episode -> Right [Claim episode]
      EpisodeExpired _      -> Left ExpiryUnrecordable
      Registered r          -> pure . uncurry Register <$> registered r
      ContextRecorded relation -> case relation of
        Read toolRead -> do
          atBrief toolRead.reference
          subject <- maybe (Left ReadWithoutSubject) Right (subjectOf toolRead.episode)
          pure [ReadContext subject toolRead.episode toolRead.record (coverageOf toolRead.reference.coverage)]
        Declared declared -> do
          atBrief declared.reference
          pure [Declare declared.candidate declared.kind declared.declarant declared.citation]
        Inferred _ -> Left InferenceUnrecordable
        Supplied _ -> Left SupplyUnrecordable
      Judged judgement -> Right [Judge judgement]
      EvaluationRecorded evaluation -> do
        case registration built.state evaluation.candidate of
          Just r | r.tree == evaluation.tree -> Right ()
          _elsewhere                         -> Left EvaluationAtOtherTree
        fails <- case evaluation.outcome of
          Observed Passed -> Right False
          Observed Failed -> Right True
          Omitted         -> Left OutcomeAlwaysRecorded
        pure
          [ DeclareGate evaluation.declaration
          , Evaluate evaluation.evaluationId evaluation.candidate evaluation.evaluator evaluation.environment fails
          ]
      ReviewRecorded _      -> Left ReviewUnrecordable
      RootDeclared _ _      -> Left RootUnrecordable
      SelectionRecorded _   -> Right []
      PromotionRecorded _   -> Right []
    -- a read is recorded on the registration it counts for: the first along
    -- the chosen registration's parent chain that cites its episode, or
    -- else any registration that does
    subjectOf episode = listToMaybe (onChain <> citing)
      where
        citing  = candidatesOf built.state episode
        onChain = case registration built.state built.proposal.chosen of
          Just chosenRegistration -> [ r.candidateId | r <- lineage built.state chosenRegistration, episode `elem` r.episodes ]
          Nothing                 -> []
    coverageOf = \case
      Observed Whole         -> CoversWhole
      Observed (Lines a b)   -> CoversLines a b
      Omitted                -> CoversUnknown
