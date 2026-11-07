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
  die "usage: claude-dev-setup probe <repo> | list | worktree <repo> <branch> <slug> | clone <url> <branch> <slug> | in-place <repo>"
}

# Prints the top level of <repo>; refuses non-repos and repos without origin.
top_of() {
  local top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $1"
  git -C "$top" remote get-url origin >/dev/null 2>&1 || die "no origin remote in $top"
  printf '%s\n' "$top"
}

has_submodules_or_lfs() {
  [ -f "$1/.gitmodules" ] || grep -qs 'filter=lfs' "$1/.gitattributes"
}

# ls-remote is authoritative (origin/HEAD is never updated by fetch);
# symbolic-ref is the offline fallback.
default_branch() {
  local b
  b="$(git -C "$1" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)\tHEAD$|\1|p')"
  if [ -z "$b" ]; then
    b="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')" || true
  fi
  [ -n "$b" ] || die "cannot determine the default branch of origin"
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

check_names() {
  [[ "$1" =~ ^[a-z]+/[a-z0-9][a-z0-9-]*$ ]] || die "invalid branch name: $1 (want <type>/<kebab-slug>)"
  [[ "$2" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid slug: $2 (want kebab-case)"
}

# Writes run.json into the run's state dir and prints it.
emit_run() {
  local mode="$1" path="$2" branch="$3" base="$4" default="$5" origin="$6"
  shift 6
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
    --arg origin_url "$origin" \
    '{run: $run, mode: $mode, path: $path, state_dir: $state_dir, branch: $branch,
      base: $base, default_branch: $default_branch, origin_url: $origin_url,
      warnings: $ARGS.positional}' --args "$@")"
  printf '%s\n' "$json" >"$state_dir/run.json"
  printf '%s\n' "$json"
}

cmd_probe() {
  local top origin default current ahead dirty=false sub=false
  top="$(top_of "$1")"
  origin="$(git -C "$top" remote get-url origin)"
  default="$(default_branch "$top")"
  current="$(git -C "$top" branch --show-current)"
  ahead="$(git -C "$top" rev-list --count "origin/$default..HEAD" 2>/dev/null || echo 0)"
  is_dirty "$top" && dirty=true
  has_submodules_or_lfs "$top" && sub=true
  jq -n --arg path "$top" --arg origin_url "$origin" --arg default_branch "$default" \
    --arg current_branch "$current" --argjson ahead "$ahead" \
    --argjson dirty "$dirty" --argjson sub "$sub" \
    '{path: $path, origin_url: $origin_url, default_branch: $default_branch,
      current_branch: $current_branch, ahead: $ahead, dirty: $dirty,
      submodules_or_lfs: $sub}'
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

cmd_worktree() {
  local repo="$1" branch="$2" slug="$3" top origin default name p b n=1 suffix
  local warnings=()
  check_names "$branch" "$slug"
  top="$(top_of "$repo")"
  has_submodules_or_lfs "$top" && die "submodules and Git LFS are not supported"
  origin="$(git -C "$top" remote get-url origin)"
  git -C "$top" fetch -q origin || exit 3
  default="$(default_branch "$top")"
  name="$(repo_name "$origin")"
  while :; do
    suffix=""
    [ "$n" -gt 1 ] && suffix="-$n"
    p="$root/$name-$slug$suffix"
    b="$branch$suffix"
    if [ -e "$p" ] || [ -e "$state_root/$(basename "$p")" ] ||
      git -C "$top" show-ref -q --verify "refs/heads/$b" ||
      git -C "$top" show-ref -q --verify "refs/remotes/origin/$b"; then
      n=$((n + 1))
      continue
    fi
    break
  done
  mkdir -p "$root"
  git -C "$top" worktree add -q --detach "$p" "origin/$default"
  git -C "$p" checkout -q -b "$b"
  is_dirty "$top" && warnings+=("the original checkout has uncommitted changes; they are not included")
  [ "$(git -C "$top" rev-list --count HEAD --not --remotes=origin)" -gt 0 ] &&
    warnings+=("the original checkout has unpushed commits; they are not included")
  emit_run worktree "$p" "$b" "$(git -C "$p" rev-parse HEAD)" "$default" "$origin" "${warnings[@]}"
}

# GitHub HTTPS cannot authenticate non-interactively, so it becomes SSH;
# a path after owner/repo (e.g. /tree/main) is dropped. Other hosts as given.
clone_url() {
  local u="$1"
  if [[ "$u" =~ ^https://github\.com/([^/]+)/([^/]+) ]]; then
    printf 'git@github.com:%s/%s.git\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
  elif [[ "$u" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [ ! -e "$u" ]; then
    printf 'git@github.com:%s.git\n' "${u%.git}"
  else
    printf '%s\n' "$u"
  fi
}

cmd_clone() {
  local url branch="$2" slug="$3" name p n=1 b default
  check_names "$branch" "$slug"
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
  if has_submodules_or_lfs "$p"; then
    rm -rf "$p"
    die "submodules and Git LFS are not supported"
  fi
  default="$(default_branch "$p")"
  b="$branch"
  n=2
  while git -C "$p" show-ref -q --verify "refs/remotes/origin/$b"; do
    b="$branch-$n"
    n=$((n + 1))
  done
  git -C "$p" checkout -q -b "$b"
  emit_run clone "$p" "$b" "$(git -C "$p" rev-parse HEAD)" "$default" "$url"
}

cmd_in_place() {
  local top origin default current ahead
  top="$(top_of "$1")"
  has_submodules_or_lfs "$top" && die "submodules and Git LFS are not supported"
  is_dirty "$top" && die "the checkout has uncommitted changes; commit or stash them first"
  current="$(git -C "$top" branch --show-current)"
  [ -n "$current" ] || die "HEAD is detached; check out a branch first"
  origin="$(git -C "$top" remote get-url origin)"
  default="$(default_branch "$top")"
  [ "$current" != "$default" ] || die "on the default branch $default; work must be on a feature branch"
  ahead="$(git -C "$top" rev-list --count "origin/$default..HEAD" 2>/dev/null || echo 0)"
  [ "$ahead" -gt 0 ] || die "no commits ahead of origin/$default"
  emit_run in-place "$top" "$current" "$(git -C "$top" merge-base "origin/$default" HEAD)" "$default" "$origin"
}

# Sourcing (the test does) only defines the functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    probe) [ $# -eq 2 ] || usage; cmd_probe "$2" ;;
    list) [ $# -eq 1 ] || usage; cmd_list ;;
    worktree) [ $# -eq 4 ] || usage; cmd_worktree "$2" "$3" "$4" ;;
    clone) [ $# -eq 4 ] || usage; cmd_clone "$2" "$3" "$4" ;;
    in-place) [ $# -eq 2 ] || usage; cmd_in_place "$2" ;;
    *) usage ;;
  esac
fi
