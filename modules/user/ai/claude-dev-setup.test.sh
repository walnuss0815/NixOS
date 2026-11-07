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

# Submodules: local file:// submodules are allowed for this test only.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
git init -q --bare -b main "$work/sub.git"
git clone -q "$work/sub.git" "$work/subw" 2>/dev/null
git -C "$work/subw" commit -q --allow-empty -m sub
git -C "$work/subw" push -q origin main 2>/dev/null
git init -q --bare -b main "$work/sup.git"
git clone -q "$work/sup.git" "$work/sup" 2>/dev/null
git -C "$work/sup" submodule add -q "$work/sub.git" ext 2>/dev/null
git -C "$work/sup" commit -q -m "add submodule"
git -C "$work/sup" push -q -u origin main 2>/dev/null
check "$(setup probe "$work/sup")" '.submodules and (.lfs | not)'
err="$(setup worktree "$work/sup" feat/s s 2>&1 >/dev/null)" && fail "worktree with submodules not refused"
[[ "$err" == *"use clone mode"* ]] || fail "worktree refusal without clone hint: $err"
s="$(setup clone "$work/sup.git" feat/s s)"
git -C "$(jq -r .path <<<"$s")/ext" rev-parse -q --verify HEAD >/dev/null || fail "submodule not checked out in clone"

# A submodule that cannot be fetched fails the clone without leftovers.
git clone -q "$work/sup.git" "$work/sup2w" 2>/dev/null
git -C "$work/sup2w" config -f .gitmodules submodule.ext.url "$work/missing.git"
git -C "$work/sup2w" commit -q -am "break submodule url"
git init -q --bare -b main "$work/sup2.git"
git -C "$work/sup2w" push -q "$work/sup2.git" HEAD:main 2>/dev/null
expect_exit 3 clone "$work/sup2.git" feat/u u
[ ! -e "$CLAUDE_DEV_ROOT/sup2-u" ] || fail "failed submodule clone left its directory"

# Existing local branches: reused when equal to origin, refused when ahead.
git -C "$pr" push -q origin origin/main:refs/heads/feat/r origin/main:refs/heads/feat/q 2>/dev/null
git -C "$pr" fetch -q origin
git -C "$pr" branch -q feat/r origin/feat/r
git -C "$pr" branch -q feat/q origin/feat/q
git -C "$pr" update-ref refs/heads/feat/q "$(git -C "$pr" commit-tree -p feat/q -m ahead 'feat/q^{tree}')"
check "$(setup worktree "$pr" feat/r pr-r --existing develop)" '.branch == "feat/r"'
err="$(setup worktree "$pr" feat/q pr-q --existing develop 2>&1 >/dev/null)" && fail "local branch ahead of origin not refused"
[[ "$err" == *differs* ]] || fail "unexpected refusal: $err"

# cleanup: worktree (branch stays), clone, in-place (checkout stays),
# unknown run, path outside the root, worktree already gone.
w2p="$(jq -r .path <<<"$w2")"
setup cleanup origin-x-slug-2 >/dev/null
[ ! -e "$w2p" ] && [ ! -e "$CLAUDE_DEV_ROOT-state/origin-x-slug-2" ] || fail "cleanup left the worktree run"
git -C "$repo" show-ref -q --verify refs/heads/feat/x-2 || fail "cleanup deleted the worktree's branch"
cp="$(jq -r .path <<<"$c")"
setup cleanup origin-z >/dev/null
[ ! -e "$cp" ] || fail "cleanup left the clone"
expect_exit 2 cleanup no-such-run
expect_exit 2 cleanup ../x
setup cleanup origin-feat-y >/dev/null
[ -d "$repo/.git" ] && [ ! -e "$CLAUDE_DEV_ROOT-state/origin-feat-y" ] || fail "cleanup of an in-place run touched the checkout"
mkdir "$work/outside"
f="$CLAUDE_DEV_ROOT-state/pr-pr-x2/run.json"
jq --arg p "$work/outside" '.path = $p' "$f" >"$f.new" && mv "$f.new" "$f"
expect_exit 2 cleanup pr-pr-x2
[ -d "$work/outside" ] && [ -f "$f" ] || fail "refused cleanup changed something"
git -C "$pr" worktree remove --force "$e1p"
check "$(setup cleanup pr-pr-x 2>/dev/null)" '.removed_path == null'
[ ! -e "$CLAUDE_DEV_ROOT-state/pr-pr-x" ] || fail "cleanup of a gone worktree kept its state dir"

echo "claude-dev-setup: all checks passed"
