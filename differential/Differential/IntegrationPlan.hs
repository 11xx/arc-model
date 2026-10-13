{-# LANGUAGE OverloadedStrings #-}
-- | C19 plan fields, with replay-created coordinates named by their role.
module Differential.IntegrationPlan
    ( PlanView(..)
    , Coordinates(..)
    , projectPlan
    , expectedPlan
    , gateCommand
    , environmentCommand
    ) where

import Arc.Model
import Generators ( Built(..) )

import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types ( Parser )
import Data.List ( elemIndex )
import Data.Maybe ( fromMaybe )


newtype PlanView = PlanView Value
  deriving stock (Eq, Show)

data Coordinates = Coordinates
  { head     :: !String
  , target   :: !String
  , tree     :: !String
  , state    :: !Value
  }

gateCommand, environmentCommand :: String
gateCommand        = "test -z \"$GATE_FAIL\""
environmentCommand = "test -n \"$PROBE_ENV\" && echo $PROBE_ENV"

projectPlan :: Coordinates -> Value -> Parser PlanView
projectPlan coordinates = withObject "integration plan" $ \plan -> do
  schema <- plan .: "schema"
  if schema /= ("arc-integration-plan/1" :: String) then fail "unsupported integration plan schema" else pure ()
  authorization <- plan .: "authorization"
  policy <- authorization .: "policy"
  observedHead <- plan .: "approved_head"
  observedTarget <- plan .: "target_revision"
  observedTree <- plan .: "evaluated_tree"
  observedEvidence <- authorization .: "gate_evidence"
  verdict <- authorization .:? "verdict_event_id" :: Parser (Maybe String)
  debt <- authorization .:? "audit_debt_event_id" :: Parser (Maybe String)
  external <- authorization .:? "external_verdict"
  pure . PlanView $ object
    [ "target" .= field plan "target"
    , "patchset" .= field plan "approved_patchset_id"
    , "head" .= coordinate "head" coordinates.head observedHead
    , "target_revision" .= coordinate "target" coordinates.target observedTarget
    , "tree" .= coordinate "tree" coordinates.tree observedTree
    , "shape" .= field plan "shape"
    , "merge_commit" .= field plan "merge_commit"
    , "authorization" .= object
        ( [ "verdict" .= named "verdict" "verdicts" verdict | verdict /= Nothing ]
        <> [ "debt" .= namedDebt debt | debt /= Nothing ]
        <> [ "external" .= externalView value | Just value <- [external] ] )
    , "gate_evidence" .= Object (KM.map (namedValue "verification" verificationIds) observedEvidence)
    , "gates" .= field authorization "gates"
    , "forbid_self_approval" .= field policy "forbid_self_approval"
    , "require_declared_actor" .= field policy "require_declared_actor"
    , "danger" .= field authorization "danger"
    , "prerequisites" .= field authorization "prerequisites"
    , "blocking_findings" .= field authorization "blocking_findings"
    , "holds" .= field authorization "holds"
    ]
  where
    rows key = case coordinates.state of
      Object state -> fromMaybe [] (parseMaybeRows (field state key))
      _other       -> []
    parseMaybeRows value = case fromJSON value of
      Success found -> Just (found :: [Object])
      Error _       -> Nothing
    ids key = [ field row "event_id" | row <- rows key, key /= "verdicts" || field row "body" == toJSON ("review" :: String) ]
    verificationIds = [ field row "event_id" | row <- rows "verifications", field row "gate" == toJSON ("build" :: String) ]
    named prefix key value = namedValue prefix (ids key) (toJSON value)
    namedDebt value = case coordinates.state of
      Object state -> case field state "debt" of
        Object row | field row "event_id" == toJSON value -> toJSON ("debt" :: String)
        _other -> toJSON value
      _other -> toJSON value
    externalView = \case
      Object row ->
        let revision = field row "revision"
            normalized = case fromJSON revision of
              Success actual -> coordinate "head" coordinates.head actual
              Error _        -> revision
        in Object (KM.insert "revision" normalized (KM.delete "event_id" row))
      other -> other

field :: Object -> Key -> Value
field row key = fromMaybe Null (KM.lookup key row)

coordinate :: String -> String -> String -> Value
coordinate label expected actual = toJSON (if actual == expected then label else actual)

namedValue :: String -> [Value] -> Value -> Value
namedValue prefix values value = case elemIndex value values of
  Just index -> toJSON (prefix <> "-" <> show (index + 1))
  Nothing    -> value

expectedPlan :: Built -> ExecutionPlan -> PlanView
expectedPlan built plan = PlanView $ object
  [ "target" .= ("master" :: String)
  , "patchset" .= patchsetName record.patchset
  , "head" .= ("head" :: String)
  , "target_revision" .= ("target" :: String)
  , "tree" .= ("tree" :: String)
  , "shape" .= shape
  , "merge_commit" .= (record.policy.shape == ShapeMergeCommit)
  , "authorization" .= authorization
  , "gate_evidence" .= object [ Key.fromString name .= eventName "verification" (map (.event) built.state.verifications) event | (GateName name, event, _) <- record.gates ]
  , "gates" .= object [ Key.fromString name .= declarationView declaration | (GateName name, declaration) <- record.declarations ]
  , "forbid_self_approval" .= record.policy.forbidSelfApproval
  , "require_declared_actor" .= record.policy.requireDeclaredActor
  , "danger" .= danger
  , "prerequisites" .= map (\(ChangeId name, EventId event) -> (name, event)) record.prerequisites
  , "blocking_findings" .= ([] :: [String])
  , "holds" .= ([] :: [String])
  ]
  where
    record = plan.integration
    shape = case record.policy.shape of
      ShapeMergeCommit     -> "merge" :: String
      ShapeFastForwardOnly -> "fast-forward"
    patchsetName (PatchsetId index) = "ps-" <> (if index < 10 then "0" else "") <> show index
    eventName prefix events event = namedValue prefix (map toJSONId events) (toJSONId event)
    toJSONId (EventId event) = toJSON event
    authorization = object $ case record.authorization of
      AuthorizedByVerdict event -> [verdict event]
      AuthorizedByWaiver _      -> ["debt" .= ("debt" :: String)]
      AuthorizedByVerdictUnderWaiver event _ -> [verdict event, "debt" .= ("debt" :: String)]
      AuthorizedByExternalVerdict _ -> ["external" .= object
        [ "revision" .= ("head" :: String), "verdict" .= ("approved" :: String)
        , "decided_by" .= ("upstream" :: String), "reference" .= ("upstream/1" :: String) ]]
    verdict event = "verdict" .= eventName "verdict" (map (.event) built.state.verdicts) event
    declarationView declaration = object
      [ "command" .= gateCommand
      , "timeout" .= declaration.timeoutSeconds
      , "declared_by" .= ([".arc/gates.toml"] :: [String]) ]
    danger = object $ case record.policy.danger of
      DangerScoped -> ["dangerous" .= True, "rule" .= ("declared-path" :: String), "paths" .= (["danger.txt"] :: [String])]
      DangerOutside -> ["dangerous" .= False, "rule" .= ("untouched" :: String)]
      DangerUndeclared -> ["dangerous" .= True, "rule" .= ("not-declared" :: String)]
