{- | Gate declarations and the vocabulary of one gate run.

A required check is declared with the exact command and timeout it will be
recognized by. Evidence is green for a declaration, and a changed
declaration is a check that has not run. A declaration may also name an
environment probe; evidence then has to carry the identity that probe
yields where the decision is made.
-}
module Arc.Model.Declaration
    ( GateResult(..)
    , ExecutionKind(..)
    , GateEvent(..)
    , Declaration(..)
    , DeclarationShape(..)
    , declarationShape
    , declarationApplies
    , evidenceEvent
    ) where

import Arc.Model.Identifiers

import Data.Set ( Set )
import Data.Set qualified as Set


-- | Whether a gate command reported success or failure when it ran.
data GateResult = GatePass
                | GateFail
  deriving stock (Eq, Ord, Show)

-- | How a record came to exist. Arc running the command itself is not the
-- same claim as somebody attesting that it ran.
data ExecutionKind = RanLocally
                   | Attested
  deriving stock (Eq, Ord, Show)

data GateEvent = Integration
               | Publication
  deriving stock (Eq, Ord, Show)

data Declaration = Declaration
  { declarationId  :: !DeclarationId
  , command        :: !String
  , timeoutSeconds :: !Int
  , environment    :: !(Maybe ProbeCommand)  -- ^ The probe whose identity evidence must carry, when the gate declares one.
  , events         :: !(Maybe (Set GateEvent))
  , selector       :: !(Maybe String)
  }
  deriving stock (Eq, Ord, Show)

-- | The part of a declaration evidence is recognized by. The environment is
-- not part of it: it decides where evidence applies, not which check ran.
data DeclarationShape = DeclarationShape
  { command        :: !String
  , timeoutSeconds :: !Int
  }
  deriving stock (Eq, Ord, Show)

-- C12
declarationShape :: Declaration -> DeclarationShape
declarationShape declaration = DeclarationShape
  { command        = declaration.command
  , timeoutSeconds = declaration.timeoutSeconds
  }

-- C12
-- | An omitted declaration event set requires the check for both operations.
declarationApplies :: GateEvent -> Declaration -> Bool
declarationApplies event declaration = maybe True (Set.member event) declaration.events

-- C14
-- | A verification that recorded no event is integration evidence.
evidenceEvent :: Maybe GateEvent -> GateEvent
evidenceEvent = maybe Integration id
