# Public documentation capture

The clean installed binary reports source/build revision
`510e3f0a680bbc5252a28bbd23fee268f7bff4ab`. `binary.sha256` identifies
the executable copied before capture. `../capture.py` ran inside
`arc-model-sandbox`; every arc subprocess inherited its sealed environment.

`overview.txt` is bare `arc`; `guide.txt` is `arc guide --all`.
`topics.txt` is the index and `topics/` contains each listed guide route.
`help.txt` contains 240 recursive help surfaces; `commands.txt` is the inventory.
The old text is the retained 234-surface capture at `../b405104a/`.
The `*.from-b405104a.diff` files retain the complete text differences;
every changed line of the `guide.txt` diff appears in a topic file, so
`topics.from-b405104a.diff` is the same difference grouped by route.

No arc implementation or checkout was read. The current public README is
not exposed by the installed binary and is not captured here.
