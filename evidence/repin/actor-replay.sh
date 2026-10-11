#!/bin/sh
# Run through arc-model-sandbox; the argument names the comparison binary.
set -eu
arc=$1
mkdir repo
cd repo
git init -q -b master
git config user.name Tester
git config user.email tester@example.invalid
git config commit.gpgsign false
mkdir .arc
printf '[policy]\nforbid_self_approval = false\nrequire_declared_actor = false\n' > .arc/policy.toml
printf 'fixture\n' > README.md
git add .
git commit -qm fixture
ARC_ACTOR=author "$arc" begin work --worktree "$PWD/../work"
cd ../work
printf 'edit\n' > work.txt
git add .
git commit -qm edit
ARC_ACTOR=author "$arc" snapshot work --solo
ARC_ACTOR=reviewer "$arc" review work --verdict approved --body review
git config --unset user.name
unset ARC_HARNESS ARC_SESSION ARC_ACTOR
set +e
"$arc" check work --json
printf 'check exit: %s\n' "$?"
"$arc" integrate work --dry-run
printf 'integration exit: %s\n' "$?"
