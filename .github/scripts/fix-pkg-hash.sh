#!/usr/bin/env bash
# Recomputes the Nix fetch hash for a pkgs/<name>/default.nix after its
# `version` has been bumped (e.g. by a Renovate PR) and rewrites the
# `hash = "...";` line in place. Does not touch `npmDepsHash` (that hash
# depends on the vendored package-lock.json's runtime deps, not on the
# tool's own version - see the comments in git-mcp-server/ssh-mcp).
#
# Supports the two fetcher shapes used under pkgs/:
#   - fetchurl from registry.npmjs.org: the new hash is read straight from
#     the npm registry's own `dist.integrity` field, no build required.
#   - fetchFromGitHub: the new hash is computed with nix-prefetch-github,
#     since GitHub's source-archive hashing isn't exposed via a simple API
#     and must go through Nix's actual fetcher to match bit-for-bit.
#
# Usage: fix-pkg-hash.sh pkgs/<name>/default.nix
set -euo pipefail

file="$1"

version=$(grep -oP '^\s*version = "\K[^"]+' "$file" | head -1)
old_hash=$(grep -oP '^\s*hash = "\K[^"]+' "$file" | head -1)

if [ -z "$version" ] || [ -z "$old_hash" ]; then
  echo "::error file=$file::could not find version/hash fields" >&2
  exit 1
fi

echo "== $file: version=$version current hash=$old_hash"

new_hash=""

if grep -q 'fetchFromGitHub' "$file"; then
  owner=$(grep -oP '^\s*owner = "\K[^"]+' "$file" | head -1)
  repo=$(grep -oP '^\s*repo = "\K[^"]+' "$file" | head -1)
  tag_template=$(grep -oP '^\s*tag = "\K[^"]+' "$file" | head -1)
  tag=${tag_template//\$\{version\}/$version}

  echo "Prefetching github:$owner/$repo@$tag"
  # nix-prefetch-github talks to the GitHub API and downloads a source
  # archive; both are occasionally flaky on shared CI runner IPs
  # (rate limiting, transient network errors), so retry a few times
  # before giving up. --verbose (captured to a temp file, not printed
  # unless we're about to fail) shows which step actually failed instead
  # of just the tool's generic "unable to calculate hash sum" message.
  attempt=0
  max_attempts=3
  err_log=$(mktemp)
  trap 'rm -f "$err_log"' EXIT
  until new_hash=$(nix run nixpkgs#nix-prefetch-github -- --verbose "$owner" "$repo" --rev "$tag" --json 2>"$err_log" | jq -r '.hash'); do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "::error file=$file::nix-prefetch-github failed after $attempt attempts" >&2
      cat "$err_log" >&2
      exit 1
    fi
    sleep_for=$((attempt * 5))
    echo "nix-prefetch-github attempt $attempt failed, retrying in ${sleep_for}s..." >&2
    cat "$err_log" >&2
    sleep "$sleep_for"
  done
elif grep -q 'fetchurl' "$file"; then
  url_template=$(grep -oP '^\s*url = "\K[^"]+' "$file" | head -1)
  url=${url_template//\$\{finalAttrs.version\}/$version}
  url=${url//\$\{version\}/$version}

  if [[ "$url" != https://registry.npmjs.org/* ]]; then
    echo "::error file=$file::don't know how to handle non-npm fetchurl source: $url" >&2
    exit 1
  fi

  # Greedy capture: package names can contain "/" (scoped packages like
  # "@cyanheads/git-mcp-server"), but never contain the "/-/" tarball
  # path separator npm inserts before the filename, so greedy matching
  # up to the last "/-/" in the URL is what we want here.
  pkg=$(sed -E 's#https://registry.npmjs.org/(.*)/-/.*#\1#' <<<"$url")
  echo "Fetching npm registry metadata for $pkg@$version"
  new_hash=$(curl -sfL "https://registry.npmjs.org/$pkg/$version" | jq -r '.dist.integrity')
else
  echo "::error file=$file::unrecognised fetcher (expected fetchFromGitHub or fetchurl)" >&2
  exit 1
fi

if [ -z "$new_hash" ] || [ "$new_hash" = "null" ]; then
  echo "::error file=$file::failed to compute new hash for version $version" >&2
  exit 1
fi

if [ "$new_hash" = "$old_hash" ]; then
  echo "Hash already up to date, nothing to do."
  exit 0
fi

sed -i "s|hash = \"$old_hash\"|hash = \"$new_hash\"|" "$file"
echo "Updated $file: $old_hash -> $new_hash"
