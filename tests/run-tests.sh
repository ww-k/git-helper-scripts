#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_REPO="$ROOT/test-git-repo"
PARENT_SCRIPT="$ROOT/scripts/git-swap-with-parent.sh"
CHILD_SCRIPT="$ROOT/scripts/git-swap-with-child.sh"

restore() {
  for branch in test-parent test-child; do
    git -C "$TEST_REPO" switch -q "$branch" 2>/dev/null || true
    git -C "$TEST_REPO" reset --hard -q fixture-d 2>/dev/null || true
  done
  git -C "$TEST_REPO" switch -q main 2>/dev/null || true
}
trap restore EXIT

assert_order() {
  local expected actual
  expected="$1"
  actual=$(git -C "$TEST_REPO" log --format='%s' --reverse)
  if [[ "$actual" != "$expected" ]]; then
    printf '提交顺序不符合预期:\n%s\n' "$actual" >&2
    exit 1
  fi
}

restore
git -C "$TEST_REPO" switch -q test-parent
(cd "$TEST_REPO" && "$PARENT_SCRIPT" fixture-b >/dev/null)
assert_order $'root fixture\ncommit B fixture\ncommit A fixture\ncommit C fixture\ncommit D fixture'
printf 'parent swap: ok\n'

git -C "$TEST_REPO" reset --hard -q fixture-d
git -C "$TEST_REPO" switch -q test-child
(cd "$TEST_REPO" && "$CHILD_SCRIPT" fixture-b >/dev/null)
assert_order $'root fixture\ncommit A fixture\ncommit C fixture\ncommit B fixture\ncommit D fixture'
printf 'child swap: ok\n'
