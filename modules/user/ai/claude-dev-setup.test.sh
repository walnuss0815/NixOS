#!/usr/bin/env bash
# Self-check for claude-dev-setup.sh against throwaway local repositories.
# Run: nix shell nixpkgs#jq -c bash modules/user/ai/claude-dev-setup.test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DEV_ROOT="$(mktemp -d /tmp/opencode/cdtest.XXXX)"
export CLAUDE_DEV_ROOT
work="$(mktemp -d /tmp/opencode/cdwork.XXXX)"
trap 'rm -rf "$CLAUDE_DEV_ROOT" "$CLAUDE_DEV_ROOT-state" "$work"' EXIT

# Isolate from the user's git config (commit signing, hooks, identity).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

setup() { bash "$here/claude-dev-setup.sh" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
check() { jq -e "$2" <<<"$1" >/dev/null || fail "$2 on $1"; }
expect_exit() {
  local want="$1" rc=0
  shift
  setup "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq "$want" ] || fail "expected exit $want, got $rc: $*"
}

(
  # shellcheck source=/dev/null
  source "$here/claude-dev-setup.sh"
  for u in https://github.com/o/r https://github.com/o/r.git https://github.com/o/r/tree/main o/r; do
    [ "$(clone_url "$u")" = git@github.com:o/r.git ] || fail "clone_url $u -> $(clone_url "$u")"
  done
  [ "$(clone_url https://gitlab.example/o/r.git)" = https://gitlab.example/o/r.git ] || fail "unknown host rewritten"
  for c in \
    "https://gitlab.com/g/s/p git@gitlab.com:g/s/p.git" \
    "https://gitlab.com/g/p.git git@gitlab.com:g/p.git" \
    "https://gitlab.com/g/p/ git@gitlab.com:g/p.git" \
    "https://gitlab.opencode.de/g/p/-/tree/main git@gitlab.opencode.de:g/p.git" \
    "https://gitlab.opencode.de/g/s/p/-/merge_requests/3 git@gitlab.opencode.de:g/s/p.git"; do
    set -- $c
    [ "$(clone_url "$1")" = "$2" ] || fail "clone_url $1 -> $(clone_url "$1")"
  done
)

git init -q --bare -b main "$work/origin.git"
git clone -q "$work/origin.git" "$work/repo" 2>/dev/null
repo="$work/repo"
git -C "$repo" commit -q --allow-empty -m one
git -C "$repo" commit -q --allow-empty -m two
git -C "$repo" push -q -u origin main 2>/dev/null

check "$(setup probe "$repo")" '.ahead == 0 and .dirty == false and .default_branch == "main" and .current_branch == "main"'
expect_exit 2 probe "$work"

w1="$(setup worktree "$repo" feat/x x-slug)"
w2="$(setup worktree "$repo" feat/x x-slug)"
check "$w1" '.branch == "feat/x" and (.path | endswith("/origin-x-slug"))'
check "$w2" '.branch == "feat/x-2" and (.path | endswith("/origin-x-slug-2"))'
[ "$(git -C "$(jq -r .path <<<"$w2")" branch --show-current)" = feat/x-2 ] || fail "worktree branch not checked out"
expect_exit 2 worktree "$repo" "feat/../x" x

c="$(setup clone "$work/origin.git" feat/z z)"
check "$c" '.mode == "clone" and .branch == "feat/z" and .default_branch == "main"'

expect_exit 2 in-place "$repo"
git -C "$repo" checkout -q -b feat/y
git -C "$repo" commit -q --allow-empty -m three
check "$(setup probe "$repo")" '.ahead == 1 and .current_branch == "feat/y"'
ip="$(setup in-place "$repo")"
check "$ip" ".base == \"$(git -C "$repo" merge-base origin/main HEAD)\" and .run == \"origin-feat-y\""
[ -f "$CLAUDE_DEV_ROOT-state/origin-feat-y/run.json" ] || fail "run.json not written"
check "$(setup in-place "$repo")" '.run == "origin-feat-y-2"'
touch "$repo/untracked"
expect_exit 2 in-place "$repo"
rm "$repo/untracked"

check "$(setup list)" 'length == 5'
f="$CLAUDE_DEV_ROOT-state/origin-x-slug/run.json"
jq '.done = true' "$f" >"$f.new" && mv "$f.new" "$f"
check "$(setup list)" 'length == 4 and all(.path_exists)'

echo "claude-dev-setup: all checks passed"
