-- | The repository's declared integration policy, as observed at decision
-- time.
module Arc.Model.Policy ( Policy(..) ) where


data Policy = Policy
  { independentVerdictRequired :: !Bool  -- ^ The change touches a surface where a verdict must come from somebody other than its author.
  , forbidSelfApproval         :: !Bool  -- ^ A self-recorded approval is rejected rather than accepted.
  , requireDeclaredActor       :: !Bool  -- ^ An event whose author nobody claimed is refused.
  }
  deriving stock (Eq, Ord, Show)
