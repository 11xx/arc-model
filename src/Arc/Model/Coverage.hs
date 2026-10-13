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
    , assessmentBinding
    , auditClears
    , DebtStanding(..)
    , debtStanding
    ) where

import Arc.Model.Decision ( newestWaiver )
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.Observed ( newest )
import Arc.Model.State

import Control.Applicative ( (<|>) )
import Data.Maybe ( isJust, listToMaybe )
import Data.Set qualified as Set


-- C21
{- | What kind of deficit a debt names. A declared kind wins; otherwise the
ledger derives one for the patchset the debt binds to. A debt that binds
to none has nothing to derive from.
-}
debtKindFor :: ChangeState -> Debt -> DebtKind
debtKindFor state debt = case debt.declaredKind of
  Just kind -> kind
  Nothing   -> maybe NothingRead (derivedKind state) (debt.patchset >>= patchsetById state)

-- C21
{- | The review a patchset is missing, read from the ledger. The ledger sees
a merge resolution and a repair the same way, so work after an approval
that nobody read is a repair; only a declaration says it was a merge
resolution.
-}
derivedKind :: ChangeState -> Patchset -> DebtKind
derivedKind state patchset
  | null state.verdicts = NothingRead
  | otherwise = case [ v | v <- state.verdicts, v.patchset == patchset.patchsetId ] of
      []
        | any approvesEarlier state.verdicts -> RepairUnread
        | otherwise                          -> IndependentReview
      verdicts
        | all ((`Set.member` effectiveContributors patchset) . effectiveActor) verdicts -> ContributorOnly
        | otherwise                                                                     -> IndependentReview
  where
    approvesEarlier verdict = verdict.kind == Approved && maybe False earlier (patchsetById state verdict.patchset)
    earlier other = other.ordinal < patchset.ordinal

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

-- C8, C21
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
    Nothing   -> OwedReview (derivedKind state patchset)
  _noPatchset -> OwedReview NothingRead

{- | The post-integration projection. The read requirement, the verdict the
audit returned, and the authorization the merge actually rested on are
three separate fields, and an open audit finding never disappears because
the read was satisfied.
-}
data CoverageAfterIntegration = CoverageAfterIntegration
  { read          :: !(Maybe ReadEvidence)
  , debt          :: !(Maybe DebtId)  -- ^ The debt the basis consumed, otherwise the newest bound to the shipped patchset: owed either way until a read fulfils it.
  , verdict       :: !(Maybe VerdictKind)
  , approved      :: !Bool
  , openFindings  :: ![FindingId]
  , authorization :: !(Maybe Authorization)
  }
  deriving stock (Eq, Ord, Show)

-- C6, C9, C22
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
    , debt          = (.debtId) <$> standingDebt record
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
    -- the debt the basis consumed, otherwise the newest bound to the
    -- shipped patchset
    standingDebt record = (listToMaybe (authorizationDebts record.authorization) >>= debtById) <|> newestWaiver state record.patchset
    debtById identifier = listToMaybe [ d | d <- state.debts, d.debtId == identifier ]
    -- an ineligible-review debt is answered by an audit its assessment
    -- admits and by nothing else; a verdict never clears it
    readEvidence record = case standingDebt record of
      Just debt | debt.declaredKind == Just IneligibleReview
        -> ReadByAudit . (.event) <$> newest [ a | a <- state.audits, auditClears state debt a ]
      _otherKind -> case independentVerdict record of
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
  if verdict.assumed || effectiveActor verdict `Set.member` effectiveContributors patchset || implementerModelMatch patchset verdict.model
    then Nothing
    else Just ()

-- C4, C22
{- | A read recorded after integration is independent when its identity was
declared, it is not one of the shipped patchset's contributors, and the
model it recorded is none of the shipped range's implementers. The same
predicate the audit gate consults, so a projection and a refusal cannot
disagree about independence.
-}
auditIsIndependent :: ChangeState -> Audit -> Bool
auditIsIndependent state audit =
  case latestIntegration state >>= patchsetById state . (.patchset) of
    Nothing       -> False
    Just patchset -> not audit.assumed
      && audit.actor `Set.notMember` effectiveContributors patchset
      && not (implementerModelMatch patchset audit.model)

-- C22
{- | How an assessment answers to the audit that carries it. The auditor is
judged first: the audit must have recorded a model, the assessment must list
identities for its reviewer, the model must be one of them, and the efforts
must agree where both are named. Only then is the work judged: the
assessment's authors must answer to every @Implemented-by@ model of the
integrated range, which the debt's production record keeps, otherwise the
range itself. A range whose lines cannot be established is not an empty one.
-}
assessmentBinding :: ChangeState -> Debt -> Audit -> Assessment -> AssessmentBinding
assessmentBinding state debt audit assessment = case audit.model of
  Nothing -> ModelUnrecorded
  Just model
    | Set.null assessment.reviewerIdentities     -> IdentitiesUnstated
    | model.slug `Set.notMember` assessment.reviewerIdentities -> ModelMismatch
    | effortsDiffer model                         -> EffortMismatch
    | otherwise -> case implementers of
        Nothing     -> AuthorsUnread
        Just needed -> case needed `Set.difference` answered of
          uncovered | Set.null uncovered -> Bound
                    | otherwise          -> AuthorsUncovered uncovered
  where
    effortsDiffer model = case (model.effort, assessment.reviewerEffort) of
      (Just recorded, Just assessed) -> recorded /= assessed
      _unnamed                       -> False
    implementers = debt.trailerImplementers <|> (latestIntegration state >>= patchsetById state . (.patchset) >>= (.implementers))
    answered     = Set.unions assessment.authors

-- C22
{- | Whether an audit clears an @ineligible-review@ debt: it was recorded
after the debt, by an independent auditor, with an assessment that says the
auditor is eligible and is bound to both the auditor and the work. No
verdict ever does.
-}
auditClears :: ChangeState -> Debt -> Audit -> Bool
auditClears state debt audit = case audit.assessment of
  Nothing         -> False
  Just assessment -> audit.event > debt.event
    && auditIsIndependent state audit
    && assessment.independence == Eligible
    && assessmentBinding state debt audit assessment == Bound

-- | Where a debt stands: nothing is owed before the change integrates.
data DebtStanding = StandingDeclared
                  | StandingOwed
                  | StandingDischarged ReadEvidence
  deriving stock (Eq, Ord, Show)

-- C27
{- | The one standing every reading of a debt shares. An integrated change's
debt is discharged by the read the integration's coverage names: an
independent read of the shipped revision, or for @ineligible-review@ an
audit that clears it.
-}
debtStanding :: ChangeState -> Debt -> DebtStanding
debtStanding state debt = case latestIntegration state of
  Nothing     -> StandingDeclared
  Just record -> maybe StandingOwed StandingDischarged (answering record)
  where
    answering record
      | debt.declaredKind == Just IneligibleReview
        = ReadByAudit . (.event) <$> newest [ a | a <- state.audits, auditClears state debt a ]
      | otherwise = case verdictAfter record of
          Just event -> Just (ReadByVerdict event)
          Nothing    -> ReadByAudit . (.event) <$> newest
            [ a | a <- state.audits, a.revision == record.head, a.event > debt.event, auditIsIndependent state a ]
    verdictAfter record = fmap (.event) . newest $
      [ v
      | v <- state.verdicts
      , v.patchset == record.patchset
      , v.event > debt.event
      , verdictIsIndependent state v == Just ()
      ]

-- C6
{- | Whether an authorization actually consumed this debt. A debt recorded
beside a standing approval authorized nothing and is reported as recorded
debt, not as an authorization input.
-}
waiverUsed :: Authorization -> DebtId -> Bool
waiverUsed authorization debt = debt `elem` authorizationDebts authorization

-- C6
-- | Every debt declaration that the given authorization did not consume.
debtsNotUsed :: ChangeState -> Authorization -> [DebtId]
debtsNotUsed state authorization = [ debt.debtId | debt <- state.debts, not (waiverUsed authorization debt.debtId) ]
