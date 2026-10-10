-- | Historical run identities stay paired with their captured evidence.
module ProvenanceChecks ( provenanceChecks ) where

import Arc.Model ( comparisonRevision )
import Render ( Check, expectTrue )

import Data.List ( isInfixOf, isPrefixOf, tails )


provenanceChecks :: IO [Check]
provenanceChecks = do
  report <- readFile "REPORT.md"
  readme <- readFile "README.md"
  let resultLines = takeWhile (/= "## Comparison revision") (lines report)
        <> dropWhile (not . isPrefixOf "#### Results at arc `37b0e72`") (lines report)
      results = unlines resultLines
      comparison = unlines $ takeWhile (not . isPrefixOf "## ")
        $ drop 1 $ dropWhile (/= "## Comparison revision") (lines report)
  pure $
    [ expectTrue ("provenance: historical run " <> original)
        "historical revision must retain its paired rewritten source citation"
        (historicalLabel original `isInfixOf` results
          && pairedCitations original rewritten report)
    | (original, rewritten) <- revisionPairs
    ] <>
    [ expectTrue ("provenance: captured binary " <> short)
        "digest/build evidence or paired rewritten source citation missing"
        (all (`isInfixOf` resultBlock short report) [revision, digest]
          && pairedCitations revision rewritten report)
    | (short, revision, rewritten, digest) <- capturedBuilds
    ] <>
    [ expectTrue ("provenance: source mapping " <> original)
        "historical revision must retain an explicit rewritten source mapping"
        (("| `" <> original <> "` | `" <> rewritten <> "` |") `isInfixOf` comparison)
    | (original, rewritten) <- revisionPairs
    ] <>
    [ expectTrue "provenance: comparison source and binary identities"
        "comparison source pin must distinguish the captured binary's build"
        (all (`isInfixOf` comparison)
          [ comparisonRevision
          , "executable has build revision `3c0c53769114de1fac2a7179fdd0dcbf906d5142`"
          , "source revision"
          , "build revision"
          ])
    ] <>
    [ expectTrue "provenance: README explains signed source correspondence"
        "README must explain how historical result citations resolve"
        ("a rewritten id names the same tree in a signed commit" `isInfixOf` readme)
    ]

pairedCitations :: String -> String -> String -> Bool
pairedCitations original rewritten report =
  not (null occurrences) && all (isPrefixOf successor) occurrences
  where
    token = "`" <> original <> "`"
    successor = " (rewritten as `" <> rewritten <> "`)"
    mapping = "| " <> token <> " | `" <> rewritten <> "` |"
    citations = unlines $ filter (/= mapping) (lines report)
    occurrences = [drop (length token) suffix | suffix <- tails citations, token `isPrefixOf` suffix]

historicalLabel :: String -> String
historicalLabel "1170fb4" = "whose binary postdates arc `1170fb4`"
historicalLabel revision = "Results at arc `" <> revision <> "`"

resultBlock :: String -> String -> String
resultBlock revision = unlines . takeWhile (not . isPrefixOf "#") . drop 1
  . dropWhile (not . isInfixOf ("Results at arc `" <> revision <> "`")) . lines

revisionPairs :: [(String, String)]
revisionPairs =
  [ ("26f6bdc", "a5f9e03")
  , ("1170fb4", "c9f3ca1")
  , ("b320731", "5858200")
  , ("e10d981", "9464071")
  , ("01c618a", "0e178db")
  , ("3c0c537", "6de12b7")
  , ("37b0e72", "75d5610")
  ]

capturedBuilds :: [(String, String, String, String)]
capturedBuilds =
  [ ( "e10d981", "e10d981b01c1613fec0b5f0925492ed83df501f6"
    , "94640716c12a30791fe8af3278732d3d01833bfa"
    , "a23ef76b230a8e8a2501813dec724e985909ed97dd6f743b3c48d80848992a02" )
  , ( "01c618a", "01c618a92f08739edd4d4c5cb2573e637105571b"
    , "0e178db63f76e676774fc9356fd5761cba136ef7"
    , "a998a28104966ee53d47c254a7df4378c0c2ad0d10f10a79fadb622fb1b26555" )
  , ( "3c0c537", "3c0c53769114de1fac2a7179fdd0dcbf906d5142"
    , "6de12b7c75e9fc199eced539ce00c8e54fef41d6"
    , "4be7d0faa790f72a1f38bc9d0932c7dc9600c5f4bf0b81cab6ac953c411b5f3f" )
  , ( "37b0e72", "37b0e7274f772b03e8dbe9a9be4725536bffacfe"
    , "75d561037205db74feea3f14d3d9713c3bde111d"
    , "0887bd220854e3e9c75fc73ab463ee336171387f8f1091b61d60ddc62c9eeeea" )
  ]
