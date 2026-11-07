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

ocd=https://gitlab.opencode.de/walnuss0815/opendesk-backup
[ "$(setup gitlab-url "$ocd/-/work_items?sort=created_date&state=opened&show=eyJpaWQiOiIxIiwiZnVsbF9wYXRoIjoid2FsbnVzczA4MTUvb3BlbmRlc2stYmFja3VwIiwiaWQiOjE0MjU2NH0%3D")" = "$ocd/-/work_items/1" ] ||
  fail "gitlab-url did not decode show="
[ "$(setup gitlab-url "$ocd/-/issues/7?x=1")" = "$ocd/-/issues/7" ] || fail "gitlab-url changed a direct URL"
expect_exit 2 gitlab-url "$ocd/-/work_items?show=bm90IGpzb24"

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

# Existing PR/MR branches: main, develop (+1) and feat/x (on develop, +1).
git init -q --bare -b main "$work/pr.git"
git clone -q "$work/pr.git" "$work/pr" 2>/dev/null
pr="$work/pr"
git -C "$pr" commit -q --allow-empty -m one
git -C "$pr" push -q -u origin main 2>/dev/null
git -C "$pr" checkout -q -b develop
git -C "$pr" commit -q --allow-empty -m dev
git -C "$pr" checkout -q -b feat/x
git -C "$pr" commit -q --allow-empty -m x
git -C "$pr" push -q origin develop feat/x 2>/dev/null
git -C "$pr" checkout -q main
git -C "$pr" branch -q -D feat/x develop

e1="$(setup worktree "$pr" feat/x pr-x --existing main)"
e1p="$(jq -r .path <<<"$e1")"
check "$e1" ".branch == \"feat/x\" and .existing and .target == \"main\" and .base == \"$(git -C "$pr" merge-base origin/main origin/feat/x)\""
[ "$(git -C "$e1p" rev-parse HEAD)" = "$(git -C "$pr" rev-parse origin/feat/x)" ] || fail "existing worktree not at origin/feat/x"
expect_exit 2 worktree "$pr" feat/x pr-x --existing main
expect_exit 2 worktree "$pr" feat/none pr-none --existing main
expect_exit 2 worktree "$pr" main pr-main --existing develop

e2="$(setup clone "$work/pr.git" feat/x pr-x2 --existing develop)"
e2p="$(jq -r .path <<<"$e2")"
check "$e2" ".target == \"develop\" and .base == \"$(git -C "$e2p" merge-base origin/develop HEAD)\""
[ "$(git -C "$e2p" rev-parse --abbrev-ref '@{upstream}')" = origin/feat/x ] || fail "existing clone does not track origin/feat/x"
expect_exit 2 clone "$work/pr.git" feat/none pr-miss --existing main
[ ! -e "$CLAUDE_DEV_ROOT/pr-pr-miss" ] || fail "failed existing clone left its directory"

git -C "$pr" checkout -q -b feat/y origin/develop
git -C "$pr" commit -q --allow-empty -m y
check "$(setup in-place "$pr" --target develop)" ".existing and .target == \"develop\" and .base == \"$(git -C "$pr" merge-base origin/develop HEAD)\""
expect_exit 2 in-place "$pr" --target nope

echo "claude-dev-setup: all checks passed"
