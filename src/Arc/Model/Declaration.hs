{- | Gate declarations and the vocabulary of one gate run.

A required check is declared with the exact command and timeout it will be
recognized by. Evidence is green for a declaration, and a changed
declaration is a check that has not run.
-}
module Arc.Model.Declaration
    ( GateResult(..)
    , ExecutionKind(..)
    , Declaration(..)
    , DeclarationShape(..)
    , declarationShape
    ) where

import Arc.Model.Identifiers


-- | Whether a gate command reported success or failure when it ran.
data GateResult = GatePass
                | GateFail
  deriving stock (Eq, Ord, Show)

-- | How a record came to exist. Arc running the command itself is not the
-- same claim as somebody attesting that it ran.
data ExecutionKind = RanLocally
                   | Attested
  deriving stock (Eq, Ord, Show)

data Declaration = Declaration
  { declarationId  :: !DeclarationId
  , command        :: !String
  , timeoutSeconds :: !Int
  }
  deriving stock (Eq, Ord, Show)

-- | The part of a declaration evidence is recognized by.
data DeclarationShape = DeclarationShape
  { command        :: !String
  , timeoutSeconds :: !Int
  }
  deriving stock (Eq, Ord, Show)

declarationShape :: Declaration -> DeclarationShape
declarationShape declaration = DeclarationShape
  { command        = declaration.command
  , timeoutSeconds = declaration.timeoutSeconds
  }
