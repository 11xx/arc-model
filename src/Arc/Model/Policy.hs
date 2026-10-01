-- | The repository's declared integration policy, as observed at decision
-- time.
module Arc.Model.Policy
    ( Policy(..)
    , DangerScope(..)
    , independenceOwed
    , externalApprovalCountsAlone
    ) where


-- | Where a change stands against the repository's danger declarations.
data DangerScope = DangerScoped      -- ^ The change touches a declared danger path, was raised with @begin --dangerous@, or its danger could not be determined.
                 | DangerOutside     -- ^ Danger paths are declared and the change touches none of them.
                 | DangerUndeclared  -- ^ The repository declares no danger path, so one gate applies to every change.
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Policy = Policy
  { danger               :: !DangerScope
  , forbidSelfApproval   :: !Bool  -- ^ A self-recorded approval is rejected rather than accepted.
  , requireDeclaredActor :: !Bool  -- ^ An event whose author nobody claimed is refused.
  }
  deriving stock (Eq, Ord, Show)

-- C4
-- | Whether an approval must come from somebody other than the work's
-- author: the change is inside the gate, which a repository declaring no
-- danger path applies to every change, and self-approval is forbidden.
independenceOwed :: Policy -> Bool
independenceOwed policy = policy.forbidSelfApproval && policy.danger /= DangerOutside

-- C9
-- | Whether an external approval can be the authorization on its own:
-- never inside the danger gate, whatever self-approval policy
-- says, and elsewhere only where no independent review is owed.
externalApprovalCountsAlone :: Policy -> Bool
externalApprovalCountsAlone policy = policy.danger /= DangerScoped && not (independenceOwed policy)
