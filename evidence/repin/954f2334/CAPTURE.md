# Public documentation capture

The clean installed binary reports source/build revision
`954f23340cec1a7b96130fceb1ec311eb5f5cf9b`. `binary.sha256` identifies
the executable copied before capture
(`33f0e0c93d785cfbedc3e850c5e6d65134fcf75c594be9f5f196839aa8a82153`).
`../capture.py` ran inside `arc-model-sandbox`; every arc subprocess
inherited its sealed environment.

`overview.txt` is bare `arc`; `guide.txt` is `arc guide --all`.
`topics.txt` is the index and `topics/` contains each listed guide route.
`help.txt` contains 291 recursive help surfaces; `commands.txt` is the inventory.
The old text is the retained 240-surface capture at `../35f9501d/`.
The `*.from-35f9501d.diff` files retain the complete text differences;
every changed line of the `guide.txt` diff (66 hunks) appears in a topic file,
so `topics.from-35f9501d.diff` is the same difference grouped by route (32
changed topics and 2 new topics, `progress` and `milestones`).

No arc implementation or checkout was read. The current public README is
not exposed by the installed binary and is not captured here.
