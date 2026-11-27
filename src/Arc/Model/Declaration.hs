{- | Gate declarations and the vocabulary of one gate run.

A required check is declared with the exact command, timeout, confinement,
invariant list, and validated gate trailers it will be recognized by. Evidence
is green for a declaration, and a changed declaration is a check that has not
run. A declaration may also name an environment probe; evidence then has to
carry the identity that probe yields where the decision is made.
-}
module Arc.Model.Declaration
    ( GateResult(..)
    , ExecutionKind(..)
    , GateEvent(..)
    , Confinement(..)
    , resolveOpenConfinement
    , WitnessDeclaration(..)
    , ChangeSize(..)
    , GateTrailers(..)
    , GateTrailerRefusal(..)
    , validateGateTrailers
    , Declaration(..)
    , DeclarationShape(..)
    , declarationShape
    , declarationApplies
    , evidenceEvent
    ) where

import Arc.Model.Identifiers

import Data.Char ( isSpace )
import Data.List ( isPrefixOf )
import Data.Maybe ( catMaybes )
import Data.Set ( Set )
import Data.Set qualified as Set


-- | A command outcome, or an attempt in which no check was admitted.
data GateResult = GatePass
                | GateFail
                | GateNotAdmitted
  deriving stock (Eq, Ord, Show)

-- | How a record came to exist. Arc running the command itself is not the
-- same claim as somebody attesting that it ran.
data ExecutionKind = RanLocally
                   | Attested
                   | Bypassed
  deriving stock (Eq, Ord, Show)

data GateEvent = Integration
               | Publication
  deriving stock (Eq, Ord, Show)

-- | The writable roots a project declares for the commands arc runs on its
-- behalf, as declared, and whether enforcement is required.
data Confinement = Confinement
  { writes   :: !(Set String)
  , required :: !Bool
  }
  deriving stock (Eq, Ord, Show)

-- C43
{- | Effective write confinement for an open change from its destination,
operator, and committed change-head tables. When neither destination nor
operator declares a table, the head's table governs as written. Otherwise
operator roots supplement destination roots, the head's roots are ignored
(never refused, whether widening or narrowing), and @required = true@ on any
side requires enforcement.
-}
resolveOpenConfinement
  :: Maybe Confinement
  -> Maybe Confinement
  -> Maybe Confinement
  -> Maybe Confinement
resolveOpenConfinement Nothing Nothing headConfine = headConfine
resolveOpenConfinement destination operator headConfine = Just Confinement
  { writes   = Set.union (rootsOf destination) (rootsOf operator)
  , required = any (.required) (catMaybes [destination, operator, headConfine])
  }
  where
    rootsOf = maybe Set.empty (.writes)

-- | Validated @Witness:@ trailer declaration (@arc-gate-trailers/1@).
data WitnessDeclaration = WitnessNamed [String]  -- ^ One to three distinct single-token witness names, in first-seen order.
                        | WitnessExempt String   -- ^ Explicit @none (<REASON>)@ exemption with a non-empty reason.
  deriving stock (Eq, Ord, Show)

-- | Validated @Change-size:@ trailer declaration.
data ChangeSize = ChangeSizeInterface
  deriving stock (Eq, Ord, Show)

-- | Validated gate trailers bound into verification-reuse identity (C45).
data GateTrailers = GateTrailers
  { witnesses  :: !(Maybe WitnessDeclaration)
  , changeSize :: !(Maybe ChangeSize)
  }
  deriving stock (Eq, Ord, Show)

-- | Why a change's @Witness:@ or @Change-size:@ trailer block is refused.
data GateTrailerRefusal = WitnessEmpty
                        | WitnessMultiline
                        | WitnessNotSingleToken String
                        | WitnessExemptEmptyReason
                        | WitnessMixedWithExempt
                        | WitnessTooMany [String]
                        | ChangeSizeInvalid String
  deriving stock (Eq, Ord, Show)

-- C45
{- | Validate raw @Witness:@ and @Change-size:@ trailer values from
@merge-base..head@. Invalid, empty, multiline, mixed, or excessive (> 3
distinct) declarations refuse; valid declarations normalize into reuse
identity.
-}
validateGateTrailers :: [String] -> [String] -> Either GateTrailerRefusal GateTrailers
validateGateTrailers rawWitnesses rawChangeSizes = do
  parsedWitnesses <- parseWitnesses rawWitnesses
  parsedSize      <- parseChangeSizes rawChangeSizes
  pure GateTrailers
    { witnesses  = parsedWitnesses
    , changeSize = parsedSize
    }
  where
    hasNewline value = '\n' `elem` value || '\r' `elem` value
    trimText = dropWhile isSpace . reverse . dropWhile isSpace . reverse
    parseWitnesses [] = Right Nothing
    parseWitnesses entries = do
      parsed <- traverse parseOneWitness entries
      combineWitnesses parsed
    parseOneWitness raw
      | hasNewline raw = Left WitnessMultiline
      | null trimmed   = Left WitnessEmpty
      | trimmed == "none" = Left WitnessExemptEmptyReason
      | Just reason <- parseExempt trimmed =
          if null (trimText reason)
            then Left WitnessExemptEmptyReason
            else Right (Left (trimText reason))
      | any isSpace trimmed = Left (WitnessNotSingleToken trimmed)
      | otherwise = Right (Right trimmed)
      where
        trimmed = trimText raw
    parseExempt text
      | "none (" `isPrefixOf` text && reverse (take 1 (reverse text)) == ")"
        = Just (initSafe (drop 6 text))
      | "none(" `isPrefixOf` text && reverse (take 1 (reverse text)) == ")"
        = Just (initSafe (drop 5 text))
      | otherwise = Nothing
    initSafe text = case reverse text of
      []       -> []
      _ : rest -> reverse rest
    combineWitnesses items =
      let exempts = [ reason | Left reason <- items ]
          names   = dedupe [ name | Right name <- items ]
      in case (exempts, names) of
        (_ : _, _ : _)             -> Left WitnessMixedWithExempt
        (reason : _, [])           -> Right (Just (WitnessExempt reason))
        ([], [])                   -> Left WitnessEmpty
        ([], _) | length names > 3 -> Left (WitnessTooMany names)
                | otherwise        -> Right (Just (WitnessNamed names))
    dedupe = go Set.empty
      where
        go _ [] = []
        go seen (x : xs)
          | Set.member x seen = go seen xs
          | otherwise         = x : go (Set.insert x seen) xs
    parseChangeSizes [] = Right Nothing
    parseChangeSizes entries = do
      _ <- traverse parseOneSize entries
      Right (Just ChangeSizeInterface)
    parseOneSize raw
      | hasNewline raw || trimText raw /= "interface" = Left (ChangeSizeInvalid raw)
      | otherwise                                     = Right ChangeSizeInterface

data Declaration = Declaration
  { declarationId  :: !DeclarationId
  , command        :: !String
  , timeoutSeconds :: !Int
  , environment    :: !(Maybe ProbeCommand)  -- ^ The probe whose identity evidence must carry, when the gate declares one.
  , events         :: !(Maybe (Set GateEvent))
  , selector       :: !(Maybe String)
  , confinement    :: !(Maybe Confinement)   -- ^ The effective write confinement; absent where no layer declares one.
  , invariants     :: !(Maybe String)        -- ^ Optional target-branch invariant list path; binds reuse identity (C45).
  , gateTrailers   :: !(Maybe GateTrailers)  -- ^ Validated gate trailers in force; binds reuse identity (C45).
  }
  deriving stock (Eq, Ord, Show)

-- | The part of a declaration evidence is recognized by. The environment is
-- not part of it: it decides where evidence applies, not which check ran.
-- Evidence that recorded no confinement carries 'Nothing', so it answers
-- only an unconfined declaration.
data DeclarationShape = DeclarationShape
  { command        :: !String
  , timeoutSeconds :: !Int
  , confinement    :: !(Maybe Confinement)
  , invariants     :: !(Maybe String)
  , gateTrailers   :: !(Maybe GateTrailers)
  }
  deriving stock (Eq, Ord, Show)

-- C12, C43, C45
declarationShape :: Declaration -> DeclarationShape
declarationShape declaration = DeclarationShape
  { command        = declaration.command
  , timeoutSeconds = declaration.timeoutSeconds
  , confinement    = declaration.confinement
  , invariants     = declaration.invariants
  , gateTrailers   = declaration.gateTrailers
  }

-- C12
-- | An omitted declaration event set requires the check for both operations.
declarationApplies :: GateEvent -> Declaration -> Bool
declarationApplies event declaration = maybe True (Set.member event) declaration.events

-- C14
-- | A verification that recorded no event is integration evidence.
evidenceEvent :: Maybe GateEvent -> GateEvent
evidenceEvent = maybe Integration id
