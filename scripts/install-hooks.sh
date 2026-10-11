#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
EXISTING=$(git config --get core.hooksPath || true)
if [ -n "$EXISTING" ] && [ "$EXISTING" != 'scripts/git-hooks' ]; then
    echo 'Existing hooksPath found; refusing to replace it. Integrate the safety checks into your current hooks.' >&2
    exit 1
fi
git config --local core.hooksPath scripts/git-hooks
echo 'Private-key pre-commit and pre-push checks installed for this repository.'
