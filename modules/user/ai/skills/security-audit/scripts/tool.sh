#!/usr/bin/env bash
# Print the path of a usable binary for the security-audit skill.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash tool.sh <name>

Print the absolute path of a usable <name> binary on stdout.
Order: PATH, Nix (nixpkgs), release download (trivy and gitleaks only).
Nothing is installed system-wide.

Names: trivy gitleaks helm kustomize jsonnet vendir shellcheck

Downloads take the newest stable release that is at least 7 days old
(override: SECURITY_AUDIT_MIN_RELEASE_AGE_DAYS), check its SHA256 against
the release's checksums file and keep it in /tmp/opencode/tools/.

Exit codes: 0 found, 1 not available (reason on stderr), 2 unknown name.
Example: "$(bash tool.sh trivy)" --version
EOF
}

die() {
  echo "tool.sh: $*" >&2
  exit 1
}

[ $# -eq 1 ] || { usage >&2; exit 2; }
name=$1
case $name in
  -h | --help) usage; exit 0 ;;
  trivy | gitleaks | kustomize | vendir | shellcheck) attr=$name ;;
  helm) attr=kubernetes-helm ;;
  jsonnet) attr=go-jsonnet ;;
  *) echo "tool.sh: unknown name '$name'" >&2; usage >&2; exit 2 ;;
esac

if path=$(command -v "$name"); then
  echo "$path"
  exit 0
fi

if command -v nix >/dev/null; then
  if out=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths "nixpkgs#$attr" 2>/dev/null) &&
    [ -x "${out%%$'\n'*}/bin/$name" ]; then
    echo "${out%%$'\n'*}/bin/$name"
    exit 0
  fi
fi

case $name in
  trivy) repo=aquasecurity/trivy ;;
  gitleaks) repo=gitleaks/gitleaks ;;
  *) die "$name not on PATH and not available via Nix; no download source" ;;
esac

case $(uname -s) in
  Linux) os_trivy=Linux os_gitleaks=linux ;;
  Darwin) os_trivy=macOS os_gitleaks=darwin ;;
  *) die "unsupported OS $(uname -s)" ;;
esac
case $(uname -m) in
  x86_64 | amd64) arch_trivy=64bit arch_gitleaks=x64 ;;
  aarch64 | arm64) arch_trivy=ARM64 arch_gitleaks=arm64 ;;
  *) die "unsupported CPU $(uname -m)" ;;
esac

# A hijacked release is usually pulled within hours (Trivy v0.69.4 in March
# 2026 was gone after ~3 h); a week of public exposure is the safety margin.
min_age=${SECURITY_AUDIT_MIN_RELEASE_AGE_DAYS:-7}
cutoff=$(date -u -d "$min_age days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
  date -u -v-"${min_age}"d +%Y-%m-%dT%H:%M:%SZ)

feed=$(curl -sfL "https://github.com/$repo/releases.atom") || die "cannot read https://github.com/$repo/releases.atom"
# Each entry has <updated> before its release link; links inside the release
# notes come later and are skipped by resetting u. Feed dates are ISO 8601 UTC,
# so string comparison orders them.
tag=$(printf '%s' "$feed" | grep -oE '<updated>[^<]+|releases/tag/v[0-9]+\.[0-9]+\.[0-9]+"' |
  awk -v cut="$cutoff" '
    /^<updated>/ { u = substr($0, 10); next }
    u != "" { t = $0; sub(/^releases\/tag\//, "", t); sub(/"$/, "", t); if (u <= cut) { print t; exit } u = "" }')
[ -n "$tag" ] || die "no stable $name release older than $min_age days in the feed"
v=${tag#v}

if [ "$name" = trivy ]; then
  asset=trivy_${v}_${os_trivy}-${arch_trivy}.tar.gz
else
  asset=gitleaks_${v}_${os_gitleaks}_${arch_gitleaks}.tar.gz
fi
sums=${name}_${v}_checksums.txt
base=https://github.com/$repo/releases/download/$tag

tools=/tmp/opencode/tools
dest=$tools/$name-$v
if [ -x "$dest/$name" ]; then
  echo "$dest/$name"
  exit 0
fi

mkdir -p "$tools"
tmp=$(mktemp -d "$tools/.$name-$v.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

curl -sfL -o "$tmp/$asset" "$base/$asset" || die "download failed: $base/$asset"
curl -sfL -o "$tmp/sums" "$base/$sums" || die "download failed: $base/$sums"
want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$tmp/sums")
if command -v sha256sum >/dev/null; then
  got=$(sha256sum "$tmp/$asset" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)
fi
[ -n "$want" ] && [ "$want" = "$got" ] || die "checksum mismatch for $asset"

tar -xzf "$tmp/$asset" -C "$tmp" "$name" || die "$name not found in $asset"
chmod +x "$tmp/$name"
mkdir -p "$dest"
# rename() is atomic: a parallel run sees either no binary or a complete one.
mv -f "$tmp/$name" "$dest/$name"
echo "$dest/$name"
