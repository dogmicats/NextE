#!/usr/bin/env bash
# Mirror upstream (author) main into the fork's main and copy new tags.
# Own work never lands on main; feature branches absorb upstream changes by
# merging main in afterwards. Run under Git Bash on Windows hosts.
set -euo pipefail

cd "$(dirname "$0")/.."

git fetch upstream --tags

# Refuse divergence: the mirror only ever fast-forwards to upstream main.
# The pushed commits are upstream's own CI-passed code and no own commit is
# created, so the mirror push is not gated on the local preflight; pushing
# own branches still requires it (AGENTS.md).
if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then
  git merge --ff-only upstream/main
else
  git fetch . upstream/main:main
fi

git push origin main
git push origin --tags

echo "fork main synced to $(git rev-parse --short upstream/main)"
