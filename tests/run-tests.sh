#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_REPO="$ROOT/test-git-repo"
PARENT_SCRIPT="$ROOT/scripts/git-swap-with-parent.sh"
CHILD_SCRIPT="$ROOT/scripts/git-swap-with-child.sh"

# Keep the fixture usable when its files were created by another Windows
# account, and avoid unrelated global excludes-file warnings.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0="$TEST_REPO"
export GIT_CONFIG_KEY_1=core.excludesFile
export GIT_CONFIG_VALUE_1=

initialize_fixture() {
  if [[ -e "$TEST_REPO" ]]; then
    if ! git -C "$TEST_REPO" rev-parse --git-dir >/dev/null 2>&1; then
      printf "'%s' exists but is not a Git repository. Remove it and run the tests again.\n" "$TEST_REPO" >&2
      exit 1
    fi
    return
  fi

  mkdir -p "$TEST_REPO"
  git -C "$TEST_REPO" init -q -b main
  git -C "$TEST_REPO" config user.name git-helper-tests
  git -C "$TEST_REPO" config user.email git-helper-tests@example.invalid

  printf 'root\n' > "$TEST_REPO/root.txt"
  git -C "$TEST_REPO" add root.txt
  git -C "$TEST_REPO" commit -q -m 'root fixture'

  printf 'A\n' > "$TEST_REPO/a.txt"
  git -C "$TEST_REPO" add a.txt
  git -C "$TEST_REPO" commit -q -m 'commit A fixture'

  printf 'B\n' > "$TEST_REPO/b.txt"
  git -C "$TEST_REPO" add b.txt
  git -C "$TEST_REPO" commit -q -m 'commit B fixture'
  git -C "$TEST_REPO" tag fixture-b

  printf 'C\n' > "$TEST_REPO/c.txt"
  git -C "$TEST_REPO" add c.txt
  git -C "$TEST_REPO" commit -q -m 'commit C fixture'

  printf 'D\n' > "$TEST_REPO/d.txt"
  git -C "$TEST_REPO" add d.txt
  git -C "$TEST_REPO" commit -q -m 'commit D fixture'
  git -C "$TEST_REPO" tag fixture-d
  git -C "$TEST_REPO" branch test-parent
  git -C "$TEST_REPO" branch test-child
}

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

initialize_fixture
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
