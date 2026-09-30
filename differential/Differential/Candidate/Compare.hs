{- | Comparing the candidate model's answers with arc's candidate commands.

The model's answers are mapped into the channel's vocabulary, which is
arc's: a refusal is the set of codes @arc candidate select@ leads its
refusal lines with, a basis is the @candidate-selected@ basis
@arc candidate show --json@ reports, a promotion is the selection's status
and the code a retried @arc candidate promote@ refused with, and a
collection answer is whether @arc candidate retire@ deleted the pin or
refused naming a root. The mapping is the model's claim about how its
answers appear in arc's; a case where the claim fails is a disagreement,
and a disagreement is classified, never dropped.
-}
module Differential.Candidate.Compare
    ( expectedFound
    , refusalCodes
    , shortfallCode
    , readCode
    , writeCode
    , patchsetText
    , foundText
    , exercised
    , compareFound
    ) where

import Arc.Candidate
import Arc.Candidate.Retention qualified as Retention
import Arc.Model.Identifiers
import Differential.Candidate.Encoding ( Case(..), Encoding(..), contractFile )
import Differential.Candidate.Replay
import Differential.Compare ( Adjudication(..), Comparison(..), Kind(..) )
import Plan ( Built(..), EvidenceMode(..), Plan(..), build, probeRegistration, targetNow )

import Control.Monad ( filterM )
import Data.List ( intercalate, sortOn )
import Data.Map.Strict qualified as Map
import Data.Maybe ( listToMaybe )
import Data.Set qualified as Set
import Text.Printf ( printf )


-- | What arc is expected to answer for a plan, by the model, in the
-- replay's coordinates.
expectedFound :: Plan -> Built -> Encoding -> Coordinates -> Found
expectedFound = expectedUnder ModelReach

-- | Which objects a root reaches: the model's 'Retention.reachable', or
-- that reach without the registrations a selection's evaluations name.
data Reach = ModelReach
           | ParentsAndAdoptions
  deriving stock (Eq, Show)

expectedUnder :: Reach -> Plan -> Built -> Encoding -> Coordinates -> Found
expectedUnder reach plan built encoding coordinates = Found
  { probe      = either (WriteRefused . writeCode) (const WriteAccepted) <$> probeWritten
  , selection  = case built.decision of
      Left grounds -> SelectRefused (Set.fromList (concatMap refusalCodes grounds))
      Right basis  -> SelectRecorded (basisIn coordinates built basis)
  , promotion  = case (built.decision, built.promotion) of
      (Left _, _)                    -> NothingSelected
      (Right _, Just (Left refusal)) -> Unpromoted (listToMaybe (refusalCodes refusal))
      (Right basis, Just (Right _))
        | plan.promotionObserved     -> PromotedAs (patchsetText basis.destination.patchset) True
      _unobserved                    -> Unpromoted Nothing
  , collection = [ (candidate, collected candidate) | candidate <- encoding.retire, recorded candidate ]
  }
  where
    -- the probe is written after the selection and its promotion, as the
    -- replay writes it
    probeWritten = record built.finalState . Registered <$> probeRegistration plan
    final = case probeWritten of
      Just (Right written) -> written
      _unwritten           -> built.finalState
    recorded candidate = Map.member candidate final.registrations
    rooted = case reach of
      ModelReach          -> final
      ParentsAndAdoptions -> final { selections = Map.map withoutEvaluations final.selections }
    collected candidate = case Retention.collection rooted (CandidateObject candidate) of
      CollectionRefused _ -> RetireRefused
      NoRootReaches       -> Retired

-- | A basis whose evaluations reach nothing.
withoutEvaluations :: SelectionBasis -> SelectionBasis
withoutEvaluations basis = SelectionBasis
  { selectionId  = basis.selectionId
  , chosen       = basis.chosen
  , destination  = basis.destination
  , target       = basis.target
  , tree         = basis.tree
  , contributors = basis.contributors
  , selector     = basis.selector
  , gates        = []
  , review       = basis.review
  , reads        = basis.reads
  , reuse        = basis.reuse
  }

basisIn :: Coordinates -> Built -> SelectionBasis -> Basis
basisIn coordinates built basis = Basis
  { destination  = coordinates.destination
  , target       = if basis.target == targetNow then coordinates.targetNow else coordinates.proposed
  , tree         = Map.findWithDefault (unTree basis.tree) basis.tree coordinates.trees
  , evaluations  = Set.fromList
      [ (unGate gate, Map.findWithDefault (unEvaluation evaluation) evaluation coordinates.evaluations, registrationOf evaluation)
      | (gate, evaluation) <- basis.gates
      ]
  , reads        = Set.fromList
      [ (contractFile <> "@" <> coordinates.base, extentText requirement.extent, unRecord toolRecord)
      | (requirement, toolRecord) <- basis.reads
      ]
  , reuse        = reuseText basis.reuse
  , contributors = Set.map unActor basis.contributors
  , selector     = unActor basis.selector
  }
  where
    registrationOf evaluation = maybe "" (\e -> unCandidate e.candidate) (Map.lookup evaluation built.state.evaluations)
    extentText = \case
      Whole         -> "whole"
      Lines from to -> "lines " <> show from <> "-" <> show to

-- | The codes arc's refusal lines lead with, for one of the model's
-- grounds.
refusalCodes :: Refusal -> [String]
refusalCodes = \case
  RefusedUnknownCandidate _                -> ["unknown-candidate"]
  RefusedTargetUnobserved                  -> ["target-unobserved"]
  RefusedTargetMoved _ _                   -> ["target-moved"]
  RefusedEnvironmentUnobserved             -> ["environment-unobserved"]
  RefusedGate _ []                         -> ["no-evaluation"]
  RefusedGate _ shortfalls                 -> map (shortfallCode . snd) shortfalls
  RefusedNoIndependentReview _             -> ["no-independent-review"]
  RefusedReadUnsatisfied _ shortfall       -> [readCode shortfall]
  RefusedBasisMoved _ _                    -> ["basis-moved"]

shortfallCode :: EvidenceShortfall -> String
shortfallCode = \case
  EvaluationUnrecorded  -> "unrecorded"
  OtherRegistration _   -> "other-registration"
  OtherTree _           -> "other-tree"
  OtherDeclaration _    -> "other-declaration"
  EnvironmentUnrecorded -> "environment-unrecorded"
  OtherEnvironment _    -> "environment-other"
  OutcomeUnknown        -> "outcome-unknown"
  OutcomeFailed         -> "failed"

readCode :: ReadShortfall -> String
readCode = \case
  ReadCoverageUnknown _ -> "unknown-coverage"
  ReadPartial _         -> "partial"
  OnlyDeclared _        -> "only-declared"
  OnlyInferred _        -> "only-inferred"
  OnlySupplied          -> "only-supplied"
  NotRead               -> "not-read"

-- | The code @arc candidate register@ refuses with for one of the model's
-- write refusals. Refusals no registration can meet have no arc code and
-- keep the model's name.
writeCode :: WriteRefusal -> String
writeCode = \case
  DuplicateCandidate _        -> "duplicate-candidate"
  UnknownCandidate _          -> "unknown-adopted"
  UnknownParent _             -> "unknown-parent"
  ParentOtherContract _ _     -> "parent-other-contract"
  AdoptionDropsProducer _ _ _ -> "adoption-drops-producer"
  UnknownEpisode _            -> "unknown-episode"
  NoProducers _               -> "no-producers"
  CitationUnresolved _        -> "unknown-citation"
  DuplicateToolRecord _       -> "duplicate-record"
  other                       -> "model:" <> show other

-- | arc's name for a destination patchset.
patchsetText :: PatchsetId -> String
patchsetText (PatchsetId number) = printf "ps-%02d" number

reuseText :: ReusePolicy -> String
reuseText = \case
  ReuseNever                 -> "never"
  ReuseOnMatchingCoordinates -> "matching-coordinates"

-- | The classes of answer a row exercised, as tallied beside a run.
exercised :: Found -> [String]
exercised found = concat
  [ [ "probe " <> writtenClass w | Just w <- [found.probe] ]
  , case found.selection of
      SelectRefused grounds -> [ "refused " <> code | code <- Set.toList grounds ]
      SelectRecorded _      -> ["selected"]
  , case found.promotion of
      NothingSelected     -> []
      PromotedAs _ _      -> ["promoted"]
      Unpromoted Nothing  -> ["unpromoted"]
      Unpromoted (Just c) -> ["promotion refused " <> c]
  , [ "retire refused" | any ((== RetireRefused) . snd) found.collection ]
  , [ "retired" | any ((== Retired) . snd) found.collection ]
  ]
  where
    writtenClass = \case
      WriteAccepted     -> "accepted"
      WriteRefused code -> "refused " <> code

foundText :: Found -> String
foundText found = "{" <> intercalate "; " parts <> "}"
  where
    parts = concat
      [ [ "probe " <> writtenText w | Just w <- [found.probe] ]
      , [ selectedText found.selection ]
      , [ promotedText found.promotion ]
      , [ "retire " <> unwords [ unCandidate c <> "=" <> collectedText answer | (c, answer) <- found.collection ] ]
      ]
    writtenText = \case
      WriteAccepted     -> "accepted"
      WriteRefused code -> "refused " <> code
    selectedText = \case
      SelectRefused grounds -> "refused " <> unwords (Set.toList grounds)
      SelectRecorded basis  -> "selected " <> basisText basis
    promotedText = \case
      NothingSelected          -> "no selection"
      PromotedAs patchset held -> "promoted " <> patchset <> (if held then " retained" else " unretained")
      Unpromoted retried       -> "unpromoted" <> maybe "" (" after " <>) retried
    collectedText = \case
      Retired       -> "retired"
      RetireRefused -> "rooted"
    basisText basis = "[" <> intercalate ", "
      [ "destination " <> basis.destination
      , "target " <> short basis.target
      , "tree " <> short basis.tree
      , "evaluations " <> unwords [ g <> ":" <> short e <> "@" <> c | (g, e, c) <- Set.toList basis.evaluations ]
      , "reads " <> unwords [ short r <> " " <> x <> " by " <> t | (r, x, t) <- Set.toList basis.reads ]
      , "reuse " <> basis.reuse
      , "contributors " <> unwords (Set.toList basis.contributors)
      , "selector " <> basis.selector
      ] <> "]"
    short = take 12

{- | A classified reading of the candidate contract: when it applies to a
case, the model's answer as the reading states it. A disagreement is
adjudicated only when arc's answer is, field for field, the model's under
the fewest readings that explain it.
-}
data Reading = Reading
  { applies      :: !(Case -> Bool)
  , rereadPlan   :: !(Plan -> Plan)
  , reach        :: !Reach
  , adjudication :: !Adjudication
  }

readings :: [Reading]
readings =
  [ Reading
      { applies      = \given -> not given.probeDeclared && given.plan.evidence == EvidenceEnvironmentOmitted
      , rereadPlan   = \plan -> plan { evidence = EvidenceCovered }
      , reach        = ModelReach
      , adjudication = Adjudication
          { kind   = Unsettled
          , reason = "a gate that declares no environment probe: arc takes a candidate evaluation from any environment, as C15 has such a gate take patchset evidence; the candidate model binds every evaluation to a recorded environment"
          }
      }
  , Reading
      { applies      = const True
      , rereadPlan   = id
      , reach        = ParentsAndAdoptions
      , adjudication = Adjudication
          { kind   = Unsettled
          , reason = "what a root reaches: arc's selection and promotion reach the chosen registration and what its parents and adoptions carry; the model's selection also reaches the registration of every evaluation it relies on"
          }
      }
  ]

-- | Compare the expected answers with arc's, and classify a disagreement a
-- reading explains.
compareFound :: Case -> Encoding -> Coordinates -> Found -> Found -> Comparison
compareFound given encoding coordinates wanted found
  | wanted == found = Agreed
  | otherwise = case [ chosen | chosen <- sortOn length (filterM (const [False, True]) applicable), uniform chosen, explains chosen ] of
      chosen : _ -> Adjudicated (combined chosen)
      []         -> Disagreed
  where
    applicable = [ reading | reading <- readings, reading.applies given ]
    -- readings of different kinds are no single classification
    uniform chosen = case map (.adjudication.kind) chosen of
      kind : kinds -> all (== kind) kinds
      []           -> False
    explains chosen =
      let plan  = foldr (.) id (map (.rereadPlan) chosen) given.plan
          reach = if any ((== ParentsAndAdoptions) . (.reach)) chosen then ParentsAndAdoptions else ModelReach
      in expectedUnder reach plan (build plan) encoding coordinates == found
    combined chosen = Adjudication
      { kind   = maybe Unsettled (.adjudication.kind) (listToMaybe chosen)
      , reason = intercalate "; and " (map (.adjudication.reason) chosen)
      }

unTree :: TreeId -> String
unTree (TreeId name) = name

unGate :: GateName -> String
unGate (GateName name) = name

unEvaluation :: EvaluationId -> String
unEvaluation (EvaluationId name) = name

unRecord :: ToolRecordId -> String
unRecord (ToolRecordId name) = name

unActor :: ActorId -> String
unActor (ActorId name) = name

unCandidate :: CandidateId -> String
unCandidate (CandidateId name) = name
