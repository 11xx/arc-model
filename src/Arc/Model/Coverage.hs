{- | Coverage obligations: what review is owed, and whether it was supplied.

Coverage obligation, verdict outcome, and historical authorization are
separate answers. A fulfilled read is not an approval, an approval is not
an effect, and neither is rewritten by later work.
-}
module Arc.Model.Coverage
    ( debtKindFor
    , ReadEvidence(..)
    , ReviewObligation(..)
    , CoverageAfterIntegration(..)
    , reviewObligation
    , coverageAfterIntegration
    , waiverUsed
    , debtsNotUsed
    , auditIsIndependent
    ) where

import Arc.Model.Decision ( newestWaiver )
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.Observed ( newest )
import Arc.Model.State

import Data.Maybe ( isJust, listToMaybe )
import Data.Set qualified as Set


{- | What kind of deficit a debt names. A declared kind wins; otherwise the
ledger derives one from the verdicts recorded on the shipped patchset.
Only a caller can say a merge resolution or a repair is what went unread,
so those two kinds are never derived.
-}
debtKindFor :: ChangeState -> Debt -> DebtKind
debtKindFor state debt = case debt.declaredKind of
  Just kind -> kind
  Nothing   -> case debt.patchset >>= patchsetById state of
    Nothing       -> NothingRead
    Just patchset ->
      case [ v | v <- state.verdicts, v.patchset == patchset.patchsetId ] of
        []       -> NothingRead
        verdicts
          | all ((`Set.member` effectiveContributors patchset) . effectiveActor) verdicts -> ContributorOnly
          | otherwise                                                                     -> IndependentReview

-- | A read somebody supplied.
data ReadEvidence = ReadByVerdict EventId
                  | ReadByAudit EventId
  deriving stock (Eq, Ord, Show)

-- | What review the change owes right now.
data ReviewObligation = CoveringRead ReadEvidence
                      | ReviewWaived DebtKind DebtId
                      | OwedReview DebtKind
                      | StandingRefusal VerdictKind EventId [FindingId]
  deriving stock (Eq, Ord, Show)

-- | The projection a lead reads: is there a covering read, a standing
-- refusal, or an owed review, and of what kind.
reviewObligation :: ChangeState -> ReviewObligation
reviewObligation state = case (governingVerdict state, latestPatchset state) of
  (Just verdict, Just patchset)
    | verdict.kind == Approved && verdict.patchset == patchset.patchsetId
      -> CoveringRead (ReadByVerdict verdict.event)
    | verdict.kind /= Approved && verdict.patchset == patchset.patchsetId
      -> StandingRefusal verdict.kind verdict.event (openBlockingFindings state)
  (_, Just patchset) -> case newestWaiver state patchset.patchsetId of
    Just debt -> ReviewWaived (debtKindFor state debt) debt.debtId
    Nothing   -> OwedReview owedKind
  _noPatchset -> OwedReview NothingRead
  where
    owedKind = case state.verdicts of
      []       -> NothingRead
      verdicts
        | any ((== ChangesRequested) . (.kind)) verdicts -> IndependentReview
        | otherwise                                      -> RepairUnread

{- | The post-integration projection. The read requirement, the verdict the
audit returned, and the authorization the merge actually rested on are
three separate fields, and an open audit finding never disappears because
the read was satisfied.
-}
data CoverageAfterIntegration = CoverageAfterIntegration
  { read          :: !(Maybe ReadEvidence)
  , debt          :: !(Maybe DebtId)
  , verdict       :: !(Maybe VerdictKind)
  , approved      :: !Bool
  , openFindings  :: ![FindingId]
  , authorization :: !(Maybe Authorization)
  }
  deriving stock (Eq, Ord, Show)

coverageAfterIntegration :: ChangeState -> CoverageAfterIntegration
coverageAfterIntegration state = case latestIntegration state of
  Nothing -> CoverageAfterIntegration
    { read          = Nothing
    , debt          = Nothing
    , verdict       = Nothing
    , approved      = False
    , openFindings  = []
    , authorization = Nothing
    }
  Just record -> CoverageAfterIntegration
    { read          = readEvidence record
    , debt          = listToMaybe (authorizationDebts record.authorization)
    , verdict       = (.kind) <$> newest state.audits
    , approved      = independentApproval record
    , openFindings  = openAuditFindings state
    , authorization = Just record.authorization
    }
  where
    -- only a verdict arc witnessed can be an independent read: a waiver is
    -- the absence of one, and an external decision names nobody arc can check
    independentVerdict record = do
      event <- case record.authorization of
        AuthorizedByVerdict event -> Just event
        _unwitnessed              -> Nothing
      verdict <- verdictByEvent state event
      verdictIsIndependent state verdict >> Just event
    auditRead record = ReadByAudit . (.event) <$> newest
      [ a
      | a <- state.audits
      , a.revision == record.head
      , auditIsIndependent state a
      ]
    readEvidence record = case independentVerdict record of
      Just event -> Just (ReadByVerdict event)
      Nothing    -> auditRead record
    independentApproval record
      = any (\a -> a.kind == Approved && auditIsIndependent state a) state.audits
      || isJust (independentVerdict record)

verdictByEvent :: ChangeState -> EventId -> Maybe Verdict
verdictByEvent state event = listToMaybe [ v | v <- state.verdicts, v.event == event ]

verdictIsIndependent :: ChangeState -> Verdict -> Maybe ()
verdictIsIndependent state verdict = do
  patchset <- patchsetById state verdict.patchset
  if verdict.assumed || effectiveActor verdict `Set.member` effectiveContributors patchset
    then Nothing
    else Just ()

{- | A read recorded after integration is independent when its identity was
declared and it is not one of the shipped patchset's contributors. The
same predicate the audit gate consults, so a projection and a refusal
cannot disagree about independence.
-}
auditIsIndependent :: ChangeState -> Audit -> Bool
auditIsIndependent state audit =
  case latestIntegration state >>= patchsetById state . (.patchset) of
    Nothing       -> False
    Just patchset -> not audit.assumed && audit.actor `Set.notMember` effectiveContributors patchset

{- | Whether an authorization actually consumed this debt. A debt recorded
beside a standing approval authorized nothing and is reported as recorded
debt, not as an authorization input.
-}
waiverUsed :: Authorization -> DebtId -> Bool
waiverUsed authorization debt = debt `elem` authorizationDebts authorization

-- | Every debt declaration that the given authorization did not consume.
debtsNotUsed :: ChangeState -> Authorization -> [DebtId]
debtsNotUsed state authorization = [ debt.debtId | debt <- state.debts, not (waiverUsed authorization debt.debtId) ]
