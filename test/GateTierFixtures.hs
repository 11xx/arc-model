-- | Public claims of C12, C14, C29 and C30, independent of replay encoding.
module GateTierFixtures ( gateTierChecks ) where

import Arc.Model
import Arc.Model.Declaration qualified as Declaration
import Arc.Model.GatePlan qualified as GatePlan
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observations qualified as Observations
import Arc.Model.State qualified as State
import Generators ( Built(..), build )
import Render
import Scenario ( defaultScenario )

import Data.Set qualified as Set


gateTierChecks :: [Check]
gateTierChecks = eventChecks <> selectorChecks <> publicationChecks

-- | Publication evidence cannot authorize integration, or hide its pass.
eventChecks :: [Check]
eventChecks =
  [ expectEq "tier/declaration: omitted selects both" [True, True]
      [ declarationApplies event buildDeclaration | event <- [Integration, Publication] ]
  , expectEq "tier/declaration: explicit publication excludes integration" [False, True]
      [ declarationApplies event publicationOnly | event <- [Integration, Publication] ]
  , expectEq "tier/evidence: legacy means integration" Integration (evidenceEvent Nothing)
  , expectTrue "tier/evidence: publication cannot satisfy integration" "event must be part of the evidence key"
      (not (green Integration [publicationPass]))
  , expectTrue "tier/evidence: integration cannot satisfy publication" "a publication guard needs its own evidence"
      (not (green Publication [integrationPass]))
  , expectTrue "tier/evidence: newer publication failure cannot hide integration pass" "other events never hide the required key"
      (green Integration [integrationPass, publicationPass { Verification.event = EventId 91, Verification.result = GateFail }])
  , expectEq "tier/integration: publication-only gate is not owed" (Right [])
      (gateEvidence (built.observation { Observations.declarations = [publicationOnly] }) (built.state { State.verifications = [] }))
  , expectEq "tier/publication: integration-only gate is not owed" (Right [])
      (publicationEvidence tree [(buildGate, integrationOnly)] [] [])
  ]
  where
    built = build defaultScenario
    integrationOnly = buildDeclaration { Declaration.events = Just (Set.singleton Integration) }

-- | A selector excludes work only with complete, known, observed facts and a
-- passing source record under the required event and environment.
selectorChecks :: [Check]
selectorChecks =
  [ expectTrue "selector/receipt: reuse retains its basis" "reuse must name source, target, selector, declaration, event and evidence" $
      case planned selected delta [integrationPass] (SelectionComplete Set.empty) of
        ReusePassing receipt -> receipt.delta == delta
          && receipt.sourceEvent == integrationPass.event
          && receipt.gateEvent == Integration
          && receipt.declaration == selected
          && receipt.declarations == [(buildGate, selected)]
          && receipt.selector == "select-checks"
          && receipt.environment == here
        RunRequired -> False
  , expectEq "selector/affected: selected gate runs" RunRequired
      (planned selected delta [integrationPass] (SelectionComplete (Set.singleton buildGate)))
  , expectEq "selector/unknown: unknown gate runs" RunRequired
      (planned selected delta [integrationPass] (SelectionComplete (Set.singleton (GateName "unknown"))))
  , expectEq "selector/absent-command: required check runs" RunRequired
      (planned buildDeclaration delta [integrationPass] (SelectionComplete Set.empty))
  , expectEq "selector/missing-source: required check runs" RunRequired
      (planned selected (delta { GatePlan.sourceTree = Omitted }) [integrationPass] (SelectionComplete Set.empty))
  , expectEq "selector/missing-paths: required check runs" RunRequired
      (planned selected (delta { GatePlan.paths = Omitted }) [integrationPass] (SelectionComplete Set.empty))
  , expectEq "selector/no-source-pass: required check runs" RunRequired
      (planned selected delta [] (SelectionComplete Set.empty))
  , expectEq "selector/source-failed: required check runs" RunRequired
      (planned selected delta [integrationPass { Verification.result = GateFail }] (SelectionComplete Set.empty))
  , expectEq "selector/other-event: required check runs" RunRequired
      (planned selected delta [publicationPass] (SelectionComplete Set.empty))
  , expectEq "selector/other-environment: required check runs" RunRequired
      (planned selected delta [integrationPass { Verification.environment = Just (EnvironmentId "elsewhere") }] (SelectionComplete Set.empty))
  , expectEq "selector/other-declaration: required check runs" RunRequired
      (planned selected delta [integrationPass { Verification.shape = DeclarationShape "other command" 60 }] (SelectionComplete Set.empty))
  , expectEq "selector/publication: changed tree runs the complete tier" RunRequired
      (planGate Publication [(buildGate, selected)] buildGate selected delta here [publicationPass] (SelectionComplete Set.empty))
  ] <>
  [ expectEq ("selector/conservative: " <> show answer) RunRequired
      (planned selected delta [integrationPass] answer)
  | answer <- [SelectionMissing, SelectionFailed, SelectionMalformed, SelectionIncomplete]
  ]
  where
    selected = buildDeclaration { Declaration.selector = Just "select-checks" }
    delta = GateDelta (Observed tree) (TreeId "tree-next") (Observed ["README.md"])
    planned declaration change evidence = planGate Integration [(buildGate, declaration)] buildGate declaration change here evidence

-- | A publication guard needs no change or verdict, and covers its current
-- branch tree completely rather than inheriting integration success.
publicationChecks :: [Check]
publicationChecks =
  [ expectEq "publication/standalone: passing publication tier permits" (Right [(buildGate, publicationPass.event, buildDeclaration.declarationId)])
      (publicationEvidence tree [(buildGate, buildDeclaration)] environments [publicationPass])
  , expectTrue "publication/failure: a red required gate refuses" "a pass at integration is no publication approval"
      (case publicationEvidence tree [(buildGate, buildDeclaration)] environments [integrationPass] of Left _ -> True; Right _ -> False)
  , expectEq "publication/current-tree: old tree cannot authorize publication" (Left [GateEvaluatedOtherTree buildGate tree])
      (publicationEvidence (TreeId "tree-next") [(buildGate, buildDeclaration)] environments [publicationPass])
  , expectEq "publication/profile-without-gates: empty tier permits" (Right [])
      (publicationEvidence tree [] [] [])
  , expectEq "publication/queued-revision: a moved branch refuses even at the same tree"
      (Left (PublicationRevisionMoved (Revision "queued") (Revision "current")))
      (publicationAt (Revision "current") (Just (Revision "queued")) tree [] [] [])
  , expectEq "publication/queued-revision: the observed queued head permits"
      (Right [(buildGate, publicationPass.event, buildDeclaration.declarationId)])
      (publicationAt (Revision "rev1") (Just (Revision "rev1")) tree [(buildGate, buildDeclaration)] environments [publicationPass])
  ]

publicationOnly :: Declaration
publicationOnly = buildDeclaration { Declaration.events = Just (Set.singleton Publication) }

buildDeclaration :: Declaration
buildDeclaration = Declaration (DeclarationId "build") "cargo build" 60 (Just (ProbeCommand "probe")) Nothing Nothing

buildGate :: GateName
buildGate = GateName "build"

tree :: TreeId
tree = TreeId "tree1"

here :: Observed EnvironmentId
here = Observed (EnvironmentId "env-here")

environments :: [(ProbeCommand, Observed EnvironmentId)]
environments = [(ProbeCommand "probe", here)]

integrationPass, publicationPass :: Verification
integrationPass = Verification (EventId 90) buildGate buildDeclaration.declarationId (declarationShape buildDeclaration)
  (Revision "rev1") tree GatePass RanLocally Nothing True (Just (EnvironmentId "env-here")) (Observed CleanWorktree) Nothing
publicationPass = integrationPass { Verification.gateEvent = Just Publication }

green :: GateEvent -> [Verification] -> Bool
green event = either (const False) (const True) . gateGreenFor event buildGate (Just buildDeclaration) tree here Nothing
