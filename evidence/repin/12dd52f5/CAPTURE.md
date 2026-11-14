# Public documentation capture

The clean installed binary reports source/build revision
`12dd52f5d003434fa07eb77908ea26af3c39af9d`. `binary.sha256` identifies
the executable copied before capture. `../capture.py` ran inside
`arc-model-sandbox`; every arc subprocess inherited its sealed environment.

`overview.txt` is bare `arc`; `guide.txt` is `arc guide --all`.
`topics.txt` is the index and `topics/` contains each listed guide route.
`help.txt` contains 240 recursive help surfaces; `commands.txt` is the inventory.
The old text is the retained 234-surface capture at `../b405104a/`.
The `*.from-b405104a.diff` files retain the complete text differences;
every changed line of the `guide.txt` diff appears in a topic file, so
`topics.from-b405104a.diff` is the same difference grouped by route.

This work began against the installed build
`510e3f0a680bbc5252a28bbd23fee268f7bff4ab` (SHA-256
`47bdf645e5c1e3d5cf776f8a171c506d9c8b8bff7ed43e0e55b4ce882d179e70`), whose
capture this directory first held. `guide.txt.from-510e3f0a.diff` and
`topics.from-510e3f0a.diff` retain the whole step to 12dd52f5: one paragraph
of `change-gates`. Recursive help and every other route are byte-identical
between the two builds. The comparisons run against 510e3f0a are kept under
`at-510e3f0a/`.

No arc implementation or checkout was read. The current public README is
not exposed by the installed binary and is not captured here.
