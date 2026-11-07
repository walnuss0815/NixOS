#!/usr/bin/env bash
# Workspace setup for the claude-dev agents: deterministic git choreography
# (default branch, collision suffixes, worktree/clone/in-place) the
# orchestrator would otherwise do by hand. Prints one JSON object (or array)
# on stdout. Exit 2: refusal with a one-line reason on stderr. Exit 3: git
# network failure, git's stderr passed through.
set -euo pipefail

root="${CLAUDE_DEV_ROOT:-/tmp/opencode/claude-dev}"
state_root="${root}-state"

die() {
  echo "claude-dev-setup: $1" >&2
  exit "${2:-2}"
}

usage() {
  die "usage: claude-dev-setup probe <repo> | list | worktree <repo> <branch> <slug> [--existing <target>] | clone <url> <branch> <slug> [--existing <target> [--upstream <url>]] | pr-source <target-url> <branch> <pr-ref> <candidate-url>... | in-place <repo> [--target <target>] | gitlab-url <url> | cleanup <run>"
}

# Prints the top level of <repo>; refuses non-repos and repos without origin.
top_of() {
  local top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $1"
  git -C "$top" remote get-url origin >/dev/null 2>&1 || die "no origin remote in $top"
  printf '%s\n' "$top"
}

has_submodules() {
  [ -f "$1/.gitmodules" ]
}

has_lfs() {
  grep -qs 'filter=lfs' "$1/.gitattributes"
}

# Submodules are checked out read-only for builds and tests.
init_submodules() {
  git -C "$1" submodule update -q --init --recursive
}

# ls-remote is authoritative (origin/HEAD is never updated by fetch);
# symbolic-ref is the offline fallback.
default_branch() {
  local b remote="${2:-origin}"
  b="$(git -C "$1" ls-remote --symref "$remote" HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)\tHEAD$|\1|p')"
  if [ -z "$b" ]; then
    b="$(git -C "$1" symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null | sed "s|^$remote/||")" || true
  fi
  [ -n "$b" ] || die "cannot determine the default branch of $remote"
  printf '%s\n' "$b"
}

repo_name() {
  local name="${1%/}"
  name="${name##*/}"
  name="${name##*:}"
  printf '%s\n' "${name%.git}"
}

is_dirty() {
  [ -n "$(git -C "$1" status --porcelain)" ]
}

check_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid slug: $1 (want kebab-case)"
}

check_names() {
  [[ "$1" =~ ^[a-z]+/[a-z0-9][a-z0-9-]*$ ]] || die "invalid branch name: $1 (want <type>/<kebab-slug>)"
  check_slug "$2"
}

# An existing PR/MR branch keeps its own name, so only git's rules apply.
check_ref() {
  git check-ref-format --branch "$1" >/dev/null 2>&1 || die "invalid branch name: $1"
}

# Existing-branch runs: the branch must exist on origin and the target on
# its remote (upstream for fork PR/MRs), and the two must differ.
check_existing() {
  local dir="$1" branch="$2" target="$3" default="$4" tremote="${5:-origin}"
  [ "$branch" != "$default" ] && [ "$branch" != "$target" ] ||
    die "branch $branch is the default or target branch"
  git -C "$dir" show-ref -q --verify "refs/remotes/origin/$branch" ||
    die "branch $branch not found on origin (PR/MR from a fork?)"
  git -C "$dir" show-ref -q --verify "refs/remotes/$tremote/$target" ||
    die "target branch $target not found on $tremote"
}

# Finds where a PR/MR's branch lives: the first candidate repository whose
# <branch> is exactly at the PR/MR head commit (<pr-ref> in the target).
cmd_pr_source() {
  local target="$1" branch="$2" ref="$3" turl sha c curl csha
  shift 3
  check_ref "$branch"
  [[ "$ref" =~ ^refs/(pull|merge-requests)/[0-9]+/head$ ]] || die "invalid PR/MR ref: $ref"
  turl="$(clone_url "$target")"
  sha="$(git ls-remote "$turl" "$ref")" || exit 3
  sha="$(awk -v r="$ref" '$2 == r {print $1}' <<<"$sha")"
  [ -n "$sha" ] || die "PR/MR head $ref not found in $target"
  for c in "$@"; do
    curl="$(clone_url "$c")"
    csha="$(git ls-remote "$curl" "refs/heads/$branch" 2>/dev/null || true)"
    csha="$(awk -v r="refs/heads/$branch" '$2 == r {print $1}' <<<"$csha")"
    if [ "$csha" = "$sha" ]; then
      jq -n --arg u "$curl" --argjson fork "$([ "$curl" = "$turl" ] && echo false || echo true)" \
        '{source_url: $u, fork: $fork}'
      return
    fi
  done
  die "no candidate has $branch at the PR/MR head $sha (or retry: PR/MR refs update shortly after a push)"
}

# Writes run.json into the run's state dir and prints it. A non-empty
# target marks a run on an existing PR/MR branch.
emit_run() {
  local mode="$1" path="$2" branch="$3" base="$4" default="$5" origin="$6" target="$7"
  shift 7
  local run state_dir json n=2
  run="$(basename "$path")"
  if [ "$mode" = in-place ]; then
    run="$(repo_name "$origin")-${branch//\//-}"
    # Worktree/clone names are already free; in-place reuses the repo path.
    local name="$run"
    while [ -e "$state_root/$run" ]; do
      run="$name-$n"
      n=$((n + 1))
    done
  fi
  state_dir="$state_root/$run"
  mkdir -p "$state_dir"
  json="$(jq -n \
    --arg run "$run" --arg mode "$mode" --arg path "$path" --arg state_dir "$state_dir" \
    --arg branch "$branch" --arg base "$base" --arg default_branch "$default" \
    --arg origin_url "$origin" --arg target "$target" \
    '{run: $run, mode: $mode, path: $path, state_dir: $state_dir, branch: $branch,
      base: $base, default_branch: $default_branch, origin_url: $origin_url,
      warnings: $ARGS.positional}
      + if $target == "" then {} else {existing: true, target: $target} end' --args "$@")"
  printf '%s\n' "$json" >"$state_dir/run.json"
  printf '%s\n' "$json"
}

cmd_probe() {
  local top origin default current ahead dirty=false sub=false lfs=false
  top="$(top_of "$1")"
  origin="$(git -C "$top" remote get-url origin)"
  default="$(default_branch "$top")"
  current="$(git -C "$top" branch --show-current)"
  ahead="$(git -C "$top" rev-list --count "origin/$default..HEAD" 2>/dev/null || echo 0)"
  is_dirty "$top" && dirty=true
  has_submodules "$top" && sub=true
  has_lfs "$top" && lfs=true
  jq -n --arg path "$top" --arg origin_url "$origin" --arg default_branch "$default" \
    --arg current_branch "$current" --argjson ahead "$ahead" \
    --argjson dirty "$dirty" --argjson sub "$sub" --argjson lfs "$lfs" \
    '{path: $path, origin_url: $origin_url, default_branch: $default_branch,
      current_branch: $current_branch, ahead: $ahead, dirty: $dirty,
      submodules: $sub, lfs: $lfs}'
}

cmd_list() {
  local f path base ahead exists out='[]'
  for f in "$state_root"/*/run.json; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.done // false' "$f")" = true ] && continue
    path="$(jq -r .path "$f")"
    base="$(jq -r .base "$f")"
    exists=false
    ahead=0
    if [ -d "$path" ]; then
      exists=true
      ahead="$(git -C "$path" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)"
    fi
    out="$(jq --slurpfile r "$f" --argjson exists "$exists" --argjson ahead "$ahead" \
      '. + [$r[0] | {run, mode, path, path_exists: $exists, branch, origin_url,
        commits_ahead_of_base: $ahead}]' <<<"$out")"
  done
  printf '%s\n' "$out"
}

# Prints the worktree that has <branch> checked out, if any.
worktree_of() {
  git -C "$1" worktree list --porcelain |
    awk -v b="refs/heads/$2" '/^worktree /{w=substr($0,10)} $0=="branch " b{print w}'
}

# With a target, works on the existing branch <branch> (a PR/MR) instead
# of creating one; only the path then gets a collision suffix.
cmd_worktree() {
  local repo="$1" branch="$2" slug="$3" target="${4:-}" top origin default name p b n=1 suffix held base created
  local warnings=()
  if [ -n "$target" ]; then
    check_slug "$slug"
    check_ref "$branch"
    check_ref "$target"
  else
    check_names "$branch" "$slug"
  fi
  top="$(top_of "$repo")"
  # git-worktree's own docs call submodule support in worktrees incomplete.
  has_submodules "$top" && die "repository has submodules; use clone mode"
  has_lfs "$top" && die "Git LFS is not supported"
  origin="$(git -C "$top" remote get-url origin)"
  git -C "$top" fetch -q origin || exit 3
  default="$(default_branch "$top")"
  [ -n "$target" ] && check_existing "$top" "$branch" "$target" "$default"
  name="$(repo_name "$origin")"
  while :; do
    suffix=""
    [ "$n" -gt 1 ] && suffix="-$n"
    p="$root/$name-$slug$suffix"
    b="$branch"
    [ -z "$target" ] && b="$branch$suffix"
    if [ -e "$p" ] || [ -e "$state_root/$(basename "$p")" ] ||
      { [ -z "$target" ] && { git -C "$top" show-ref -q --verify "refs/heads/$b" ||
        git -C "$top" show-ref -q --verify "refs/remotes/origin/$b"; }; }; then
      n=$((n + 1))
      continue
    fi
    break
  done
  mkdir -p "$root"
  created=true
  if [ -z "$target" ]; then
    git -C "$top" worktree add -q --detach "$p" "origin/$default" || die "git worktree add failed for $p"
    git -C "$p" checkout -q -b "$b" || die "cannot create branch $b"
  elif git -C "$top" show-ref -q --verify "refs/heads/$b"; then
    created=false
    held="$(worktree_of "$top" "$b")"
    [ -z "$held" ] || die "branch $b is checked out in $held; run from there"
    [ "$(git -C "$top" rev-parse "$b")" = "$(git -C "$top" rev-parse "origin/$b")" ] ||
      die "local $b differs from origin/$b"
    git -C "$top" worktree add -q "$p" "$b" || die "git worktree add failed for $p"
  else
    git -C "$top" worktree add -q --track -b "$b" "$p" "origin/$b" || die "git worktree add failed for $p"
  fi
  # The checked-out branch may add submodules the original checkout lacks.
  if has_submodules "$p"; then
    git -C "$top" worktree remove --force "$p"
    [ "$created" = true ] && git -C "$top" branch -q -D "$b"
    die "repository has submodules; use clone mode"
  fi
  if [ -z "$target" ]; then
    base="$(git -C "$p" rev-parse HEAD)"
  else
    base="$(git -C "$p" merge-base "origin/$target" HEAD)"
  fi
  is_dirty "$top" && warnings+=("the original checkout has uncommitted changes; they are not included")
  [ "$(git -C "$top" rev-list --count HEAD --not --remotes=origin)" -gt 0 ] &&
    warnings+=("the original checkout has unpushed commits; they are not included")
  emit_run worktree "$p" "$b" "$base" "$default" "$origin" "$target" "${warnings[@]}"
}

# HTTPS cannot authenticate non-interactively, so GitHub and the GitLab
# hosts with MCP servers become SSH; a path after the project (GitHub:
# after owner/repo, GitLab: from /-/ on, groups may be nested) is
# dropped. Other hosts as given.
clone_url() {
  local u="$1" p
  if [[ "$u" =~ ^https://github\.com/([^/]+)/([^/]+) ]]; then
    printf 'git@github.com:%s/%s.git\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
  elif [[ "$u" =~ ^https://(gitlab\.com|gitlab\.opencode\.de)/(.+)$ ]]; then
    p="${BASH_REMATCH[2]%%/-/*}"
    p="${p%/}"
    printf 'git@%s:%s.git\n' "${BASH_REMATCH[1]}" "${p%.git}"
  elif [[ "$u" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [ ! -e "$u" ]; then
    printf 'git@github.com:%s.git\n' "${u%.git}"
  else
    printf '%s\n' "$u"
  fi
}

# GitLab's work item list opens an item in a side panel and only names it
# in `show=` (base64 JSON with iid and full_path); the MCP tools need the
# item's own URL. Direct item URLs pass through unchanged.
cmd_gitlab_url() {
  local u="$1" host show json iid path
  if [[ "$u" =~ ^https://[^/]+/.+/-/(work_items|issues|epics)/[0-9]+([?#].*)?$ ]]; then
    printf '%s\n' "${u%%[?#]*}"
    return
  fi
  [[ "$u" =~ ^https://([^/]+)/.*[?\&]show=([^\&#]+) ]] || die "not a GitLab work item URL: $u"
  host="${BASH_REMATCH[1]}"
  show="${BASH_REMATCH[2]//%3D/=}"
  show="${show//%2B/+}"
  show="${show//%2F//}"
  while [ $((${#show} % 4)) -ne 0 ]; do show="$show="; done
  json="$(printf '%s' "$show" | base64 -d 2>/dev/null)" || die "cannot decode show= in $u"
  iid="$(jq -r '.iid // empty' <<<"$json" 2>/dev/null)" || true
  path="$(jq -r '.full_path // empty' <<<"$json" 2>/dev/null)" || true
  [[ "$iid" =~ ^[0-9]+$ && -n "$path" ]] || die "no iid/full_path in show= of $u"
  printf 'https://%s/%s/-/work_items/%s\n' "$host" "$path" "$iid"
}

# With an upstream (fork PR/MRs), the clone is the fork and the target
# branch and base come from the upstream repository.
cmd_clone() {
  local url branch="$2" slug="$3" target="${4:-}" upstream="${5:-}" name p n=1 b default base tremote=origin
  if [ -n "$target" ]; then
    check_slug "$slug"
    check_ref "$branch"
    check_ref "$target"
  else
    check_names "$branch" "$slug"
  fi
  url="$(clone_url "$1")"
  name="$(repo_name "$url")"
  while :; do
    p="$root/$name-$slug"
    [ "$n" -gt 1 ] && p="$p-$n"
    if [ -e "$p" ] || [ -e "$state_root/$(basename "$p")" ]; then
      n=$((n + 1))
      continue
    fi
    break
  done
  mkdir -p "$root"
  git clone -q "$url" "$p" || exit 3
  if has_lfs "$p"; then
    rm -rf "$p"
    die "Git LFS is not supported"
  fi
  if [ -n "$upstream" ]; then
    tremote=upstream
    git -C "$p" remote add upstream "$(clone_url "$upstream")"
    if ! git -C "$p" fetch -q upstream; then
      rm -rf "$p"
      exit 3
    fi
  fi
  default="$(default_branch "$p" "$tremote")"
  if [ -n "$target" ]; then
    (check_existing "$p" "$branch" "$target" "$default" "$tremote") || {
      rm -rf "$p"
      exit 2
    }
    b="$branch"
    git -C "$p" checkout -q --track -b "$b" "origin/$b"
    base="$(git -C "$p" merge-base "$tremote/$target" HEAD)"
  else
    b="$branch"
    n=2
    while git -C "$p" show-ref -q --verify "refs/remotes/origin/$b"; do
      b="$branch-$n"
      n=$((n + 1))
    done
    git -C "$p" checkout -q -b "$b"
    base="$(git -C "$p" rev-parse HEAD)"
  fi
  if has_submodules "$p" && ! init_submodules "$p"; then
    rm -rf "$p"
    exit 3
  fi
  emit_run clone "$p" "$b" "$base" "$default" "$url" "$target"
}

# Without a target, the work must be ahead of the default branch; with
# one (a PR/MR into another branch), ahead of that branch.
cmd_in_place() {
  local target="${2:-}" top origin default current ahead against
  local warnings=()
  top="$(top_of "$1")"
  has_lfs "$top" && die "Git LFS is not supported"
  is_dirty "$top" && die "the checkout has uncommitted changes; commit or stash them first"
  current="$(git -C "$top" branch --show-current)"
  [ -n "$current" ] || die "HEAD is detached; check out a branch first"
  origin="$(git -C "$top" remote get-url origin)"
  default="$(default_branch "$top")"
  [ "$current" != "$default" ] || die "on the default branch $default; work must be on a feature branch"
  against="$default"
  if [ -n "$target" ]; then
    check_ref "$target"
    [ "$current" != "$target" ] || die "on the target branch $target; work must be on a feature branch"
    git -C "$top" show-ref -q --verify "refs/remotes/origin/$target" ||
      die "target branch $target not found on origin"
    against="$target"
  fi
  ahead="$(git -C "$top" rev-list --count "origin/$against..HEAD" 2>/dev/null || echo 0)"
  [ "$ahead" -gt 0 ] || die "no commits ahead of origin/$against"
  if has_submodules "$top" && git -C "$top" submodule status --recursive | grep -q '^-'; then
    init_submodules "$top" || exit 3
    warnings+=("submodules were initialized in the checkout")
  fi
  emit_run in-place "$top" "$current" "$(git -C "$top" merge-base "origin/$against" HEAD)" "$default" "$origin" "$target" "${warnings[@]}"
}

# Removes a run's worktree or clone and its state dir. Only paths below
# the root are ever deleted; an in-place run's path is the user's own
# checkout and is never touched.
cmd_cleanup() {
  local run="$1" f mode path rroot rpath common removed=""
  [[ "$run" =~ ^[A-Za-z0-9._-]+$ && "$run" != . && "$run" != .. ]] || die "invalid run name: $run"
  f="$state_root/$run/run.json"
  [ -f "$f" ] || die "no such run: $run"
  mode="$(jq -r .mode "$f")"
  path="$(jq -r .path "$f")"
  if [ "$mode" != in-place ]; then
    rroot="$(realpath -m "$root")"
    rpath="$(realpath -m "$path")"
    [[ "$rpath" == "$rroot/"* ]] || die "run path $path is outside $root; nothing removed"
    if [ "$mode" = worktree ]; then
      if [ -d "$rpath" ]; then
        common="$(git -C "$rpath" rev-parse --path-format=absolute --git-common-dir)"
        git -C "${common%/.git}" worktree remove --force "$rpath"
        removed="$rpath"
      else
        echo "claude-dev-setup: worktree $path is gone; git worktree prune in the original checkout clears its entry" >&2
      fi
    elif [ -d "$rpath" ]; then
      rm -rf "$rpath"
      removed="$rpath"
    fi
  fi
  rm -rf "${state_root:?}/$run"
  jq -n --arg run "$run" --arg removed "$removed" '{run: $run, removed_path: (if $removed == "" then null else $removed end)}'
}

# Sourcing (the test does) only defines the functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    probe) [ $# -eq 2 ] || usage; cmd_probe "$2" ;;
    list) [ $# -eq 1 ] || usage; cmd_list ;;
    worktree | clone)
      [ $# -ge 4 ] || usage
      cmd="cmd_$1" src="$2" br="$3" sl="$4" tg="" up=""
      shift 4
      while [ $# -gt 0 ]; do
        case "$1" in
          --existing) [ $# -ge 2 ] || usage; tg="$2"; shift 2 ;;
          --upstream) [ "$cmd" = cmd_clone ] && [ $# -ge 2 ] || usage; up="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [ -z "$up" ] || [ -n "$tg" ] || usage
      "$cmd" "$src" "$br" "$sl" "$tg" "$up"
      ;;
    pr-source) [ $# -ge 5 ] || usage; shift; cmd_pr_source "$@" ;;
    in-place)
      if [ $# -eq 4 ] && [ "$3" = --target ]; then
        cmd_in_place "$2" "$4"
      else
        [ $# -eq 2 ] || usage
        cmd_in_place "$2"
      fi
      ;;
    gitlab-url) [ $# -eq 2 ] || usage; cmd_gitlab_url "$2" ;;
    cleanup) [ $# -eq 2 ] || usage; cmd_cleanup "$2" ;;
    *) usage ;;
  esac
fi
