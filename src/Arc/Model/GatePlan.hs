-- | C29: a selector may justify reusing evidence, never invent a result.
module Arc.Model.GatePlan
    ( GateDelta(..)
    , SelectorRequest(..)
    , SelectorAnswer(..)
    , GatePlan(..)
    , ReuseReceipt(..)
    , planGate
    ) where

import Arc.Model.Declaration
import Arc.Model.Gate
import Arc.Model.Identifiers
import Arc.Model.Ledger.Verification ( Verification )
import Arc.Model.Observed

import Data.Set ( Set )
import Data.Set qualified as Set


data GateDelta = GateDelta
  { sourceTree :: !(Observed TreeId)
  , targetTree :: !TreeId
  , paths      :: !(Observed [FilePath])
  }
  deriving stock (Eq, Ord, Show)

data SelectorAnswer = SelectionMissing
                    | SelectionFailed
                    | SelectionMalformed
                    | SelectionIncomplete
                    | SelectionComplete SelectorRequest (Set GateName)
  deriving stock (Eq, Ord, Show)

data SelectorRequest = SelectorRequest
  { delta        :: !GateDelta
  , declarations :: ![(GateName, Declaration)]
  }
  deriving stock (Eq, Ord, Show)

data ReuseReceipt = ReuseReceipt
  { gate         :: !GateName
  , gateEvent    :: !GateEvent
  , sourceEvent  :: !EventId
  , delta        :: !GateDelta
  , selector     :: !String
  , declaration  :: !Declaration
  , declarations :: ![(GateName, Declaration)]
  , environment  :: !(Observed EnvironmentId)
  }
  deriving stock (Eq, Ord, Show)

data GatePlan = RunRequired
              | ReusePassing ReuseReceipt
  deriving stock (Eq, Ord, Show)

-- C29
-- | Only a complete answer naming known gates, excluding this required gate,
-- acknowledging the exact request and backed by green source evidence can
-- avoid a run.
planGate
  :: GateEvent
  -> [(GateName, Declaration)]
  -> GateName
  -> Declaration
  -> GateDelta
  -> Observed EnvironmentId
  -> [Verification]
  -> SelectorAnswer
  -> GatePlan
planGate event known gate declaration delta here verifications answer
  | event == Integration
  , Just selector <- declaration.selector
  , Observed source <- delta.sourceTree
  , Observed _paths <- delta.paths
  , SelectionComplete acknowledged affected <- answer
  , acknowledged == SelectorRequest delta known
  , affected `Set.isSubsetOf` Set.fromList (map fst known)
  , gate `Set.notMember` affected
  , Right reading <- gateGreenFor event gate (Just declaration) source here Nothing verifications
  , Covered sourceEvent <- reading.coverage
      = ReusePassing ReuseReceipt
          { gate         = gate
          , gateEvent    = event
          , sourceEvent  = sourceEvent
          , delta        = delta
          , selector     = selector
          , declaration  = declaration
          , declarations = known
          , environment  = here
          }
  | otherwise = RunRequired
