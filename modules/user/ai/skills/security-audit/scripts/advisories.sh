#!/usr/bin/env bash
# Look up OSV advisories that affect pinned component versions.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash advisories.sh <inventory.tsv> <out-dir>

<inventory.tsv>: one component per line, tab-separated:
  component  ecosystem  package  version
  e.g. "Argo CD<TAB>Go<TAB>github.com/argoproj/argo-cd/v3<TAB>3.6.2"
Ecosystems as OSV names them: Go, npm, PyPI, Maven, crates.io, ...
Blank lines and lines starting with # are skipped.

Queries OSV (https://api.osv.dev) for every component; only ecosystem,
package name and version leave the machine. Writes to <out-dir>:

  advisories.tsv  component, package, version, osv_id, aliases, severity,
                  fixed (fixed versions of this package, comma-separated),
                  summary, workaround (the advisory's workaround/mitigation
                  text, empty if it has none)
  unknown.tsv     components OSV has no advisories for at any version, plus
                  for github.com/<owner>/<repo> packages the repo's own
                  published advisories: github_advisories (count on page 1,
                  "+" if there are more pages, n/a without a GitHub repo,
                  error if the page didn't load), latest_published, ids
  errors.tsv      component, package, version, reason: not checked

Fetched advisories are kept in <out-dir>/vulns/ and reused on re-runs.

Exit codes: 0 done, 1 jq or curl not available, 2 bad arguments,
3 OSV not reachable (nothing was checked).
EOF
}

case ${1:-} in -h | --help) usage; exit 0 ;; esac
[ $# -eq 2 ] && [ -r "$1" ] || { usage >&2; exit 2; }
inv=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)
jq=$(bash "$here/tool.sh" jq) || exit 1
command -v curl >/dev/null || { echo "advisories.sh: curl not found" >&2; exit 1; }
# Overridable for tests only.
osv=${SECURITY_AUDIT_OSV_URL:-https://api.osv.dev}
mkdir -p "$out/vulns"
out=$(cd "$out" && pwd)

grep -Ev '^[[:space:]]*(#|$)' "$inv" >"$out/components.tsv" || true
n=$(wc -l <"$out/components.tsv")
[ "$n" -gt 0 ] || { echo "advisories.sh: no components in $inv" >&2; exit 2; }
# An empty version would make OSV list every advisory of the package.
bad=$(awk -F'\t' 'NF < 4 || $1 == "" || $2 == "" || $3 == "" || $4 == "" { print "  line " NR ": " $0 }' "$out/components.tsv")
if [ -n "$bad" ]; then
  echo "advisories.sh: each line needs 4 non-empty tab-separated fields (component, ecosystem, package, version):" >&2
  echo "$bad" >&2
  exit 2
fi
# shortcut: one querybatch takes 1000 queries (2 per component); split the
# inventory into several files if it ever has more than 500 components.
[ "$n" -le 500 ] || { echo "advisories.sh: more than 500 components; split $inv" >&2; exit 2; }

# Two queries per component: with the version (advisories affecting it) and
# without (does OSV know the package at all, or is it for the next source).
"$jq" -R -s '{queries: [split("\n")[] | select(length > 0) | split("\t")
  | ({package: {name: .[2], ecosystem: .[1]}, version: .[3]}, {package: {name: .[2], ecosystem: .[1]}})]}' \
  "$out/components.tsv" >"$out/query.json"
code=$(curl -s -m 120 -o "$out/batch.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  --data @"$out/query.json" "$osv/v1/querybatch") || code=000
case $code in
  200) ;;
  4??)
    # OSV rejects the whole batch for one bad query and names its index.
    msg=$("$jq" -r '.message // empty' "$out/batch.json" 2>/dev/null || true)
    idx=$(printf '%s' "$msg" | sed -n 's/.*index \([0-9][0-9]*\).*/\1/p')
    if [ -n "$idx" ]; then
      line=$((idx / 2 + 1))
      echo "advisories.sh: OSV rejected line $line ($(sed -n "${line}p" "$out/components.tsv" | tr '\t' ' ')): $msg" >&2
    else
      echo "advisories.sh: OSV rejected the query (HTTP $code): $msg" >&2
    fi
    exit 2
    ;;
  *)
    echo "advisories.sh: OSV not reachable at $osv (HTTP $code); nothing was checked" >&2
    exit 3
    ;;
esac

fetch() {
  [ -s "$out/vulns/$1.json" ] && return 0
  if curl -sf -m 60 -o "$out/vulns/$1.json.tmp" "$osv/v1/vulns/$1"; then
    mv "$out/vulns/$1.json.tmp" "$out/vulns/$1.json"
  else
    rm -f "$out/vulns/$1.json.tmp"
  fi
}
export -f fetch
export out osv
# 8 parallel requests are well within what api.osv.dev serves.
# shellcheck disable=SC2016 # $1 belongs to the inner bash
"$jq" -r '[.results | to_entries[] | select(.key % 2 == 0) | .value.vulns[]?.id] | unique[]' "$out/batch.json" |
  xargs -P 8 -I{} bash -c 'fetch "$1"' _ {}
find "$out/vulns" -name '*.json' -exec cat {} + | "$jq" -s 'map({key: .id, value: .}) | from_entries' >"$out/vulns.json"

# shellcheck disable=SC2016 # jq program, $vars are jq variables
"$jq" -r --slurpfile v "$out/vulns.json" --rawfile comps "$out/components.tsv" '
  def clean: tostring | gsub("[\t\r\n]+"; " ") | gsub("^ +| +$"; "");
  # OSV matches names case-insensitively (PyPI also folds - _ .); so must we.
  def norm: ascii_downcase | gsub("[-_.]+"; "-");
  def heading: "^\\s*(#+\\s*|\\*\\*)?(workarounds?|mitigations?)\\b";
  # Text of the first Workarounds/Mitigation section, up to the next heading.
  def workaround:
    ((.details // "") | gsub("\r"; "") | split("\n")) as $l
    | ([range(0; $l | length) | select($l[.] | test(heading; "i"))] | first) as $i
    | if $i == null then "" else
        ($l[$i] | sub(heading + "\\**\\s*:?\\s*"; ""; "i")) as $rest
        | ($l[$i + 1:] | (map(test("^\\s*#")) | index(true)) as $e | if $e == null then . else .[:$e] end) as $body
        | ([$rest] + $body | join(" ") | clean | .[0:300])
      end;
  ($comps | split("\n") | map(select(length > 0) | split("\t"))) as $c
  | .results as $r
  | range(0; $c | length) as $i
  | $c[$i] as [$comp, $eco, $pkg, $ver]
  | if ($r[2 * $i + 1].vulns // [] | length) == 0 and $r[2 * $i + 1].next_page_token == null then
      ["U", $comp, $eco, $pkg, $ver] | map(clean) | @tsv
    else
      # shortcut: more pages are reported, not fetched; add page_token
      # queries if a real component ever has 1000+ affecting advisories.
      (if $r[2 * $i].next_page_token != null then
        ["E", $comp, $pkg, $ver, "OSV result truncated (more pages); advisories may be missing"] | map(clean) | @tsv
      else empty end),
      ($r[2 * $i].vulns[]?.id as $id
      | $v[0][$id] as $d
      | if $d == null then ["E", $comp, $pkg, $ver, "advisory \($id) could not be fetched"] | map(clean) | @tsv
        elif $d.withdrawn != null then empty
        else ["A", $comp, $pkg, $ver, $id, ($d.aliases // [] | join(",")),
            ($d.database_specific.severity // $d.affected[0].ecosystem_specific.severity // $d.severity[0].score // ""),
            ([$d.affected[]? | select((.package.ecosystem | norm) == ($eco | norm) and (.package.name | norm) == ($pkg | norm))
              | .ranges[]?.events[]? | .fixed // empty] | unique | join(",")),
            ($d.summary // "" | clean | .[0:120]),
            ($d | workaround)] | map(clean) | @tsv
        end)
    end
' "$out/batch.json" >"$out/rows.tsv"

printf 'component\tpackage\tversion\tosv_id\taliases\tseverity\tfixed\tsummary\tworkaround\n' >"$out/advisories.tsv"
printf 'component\tecosystem\tpackage\tversion\n' >"$out/unknown.tsv"
printf 'component\tpackage\tversion\treason\n' >"$out/errors.tsv"
awk -F'\t' -v a="$out/advisories.tsv" -v u="$out/unknown.tsv" -v e="$out/errors.tsv" '
  { t = $1; sub(/^[AUE]\t/, "") }
  t == "A" { print >> a } t == "U" { print >> u } t == "E" { print >> e }' "$out/rows.tsv"

# OSV-unknown packages hosted on GitHub: does the repo publish advisories at
# all? Repo-level advisories without an ecosystem mapping never reach OSV.
gh=${SECURITY_AUDIT_GITHUB_URL:-https://github.com} # overridable for tests only
mkdir -p "$out/github"
ghcheck() {
  local f=$out/github/${1//\//__}.html
  [ -s "$f" ] && return 0
  if curl -sfL -m 30 -o "$f.tmp" "$gh/$1/security/advisories?state=published"; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
  fi
}
export -f ghcheck
export gh
tail -n +2 "$out/unknown.tsv" >"$out/unknown.base"
# 4 parallel page loads stay well below github.com's anonymous limits.
# shellcheck disable=SC2016 # $1 belongs to the inner bash
cut -f3 "$out/unknown.base" | awk -F/ '$1 == "github.com" && NF >= 3 { print $2 "/" $3 }' | sort -u |
  xargs -P 4 -I{} bash -c 'ghcheck "$1"' _ {}
printf 'component\tecosystem\tpackage\tversion\tgithub_advisories\tlatest_published\tids\n' >"$out/unknown.tsv"
while IFS=$'\t' read -r c e p v; do
  latest=
  ids=
  case $p in
    github.com/*/*)
      r=$(printf '%s' "$p" | cut -d/ -f2,3)
      f=$out/github/${r//\//__}.html
      if [ -s "$f" ]; then
        all=$(grep -ioE "/$r/security/advisories/GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}" "$f" | sed 's|.*/||' | awk '!s[$0]++' || true)
        count=$(printf '%s' "$all" | grep -c . || true)
        # Page 1 only; "+" says there are more pages.
        if grep -qE 'rel="next"|aria-label="Next' "$f"; then count="$count+"; fi
        ids=$(printf '%s\n' "$all" | head -10 | paste -sd, -)
        latest=$(grep -oE 'datetime="[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" | cut -d'"' -f2 | sort -r | head -1 || true)
      else
        count=error
      fi
      ;;
    *) count=n/a ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$e" "$p" "$v" "$count" "$latest" "$ids" >>"$out/unknown.tsv"
done <"$out/unknown.base"

rows=$(($(wc -l <"$out/advisories.tsv") - 1))
ids=$(tail -n +2 "$out/advisories.tsv" | cut -f4 | sort -u | grep -c . || true)
unknown=$(($(wc -l <"$out/unknown.tsv") - 1))
errors=$(($(wc -l <"$out/errors.tsv") - 1))
triage=$(tail -n +2 "$out/unknown.tsv" | awk -F'\t' '
  $5 == "0" { z++ } $5 == "n/a" { na++ } $5 == "error" { er++ } $5 ~ /^[1-9][0-9]*\+?$|^0\+$/ { adv++ }
  END { printf "github 0: %d, with advisories: %d, no github repo: %d, errors: %d", z, adv, na, er }')
echo "components: $n, unknown to OSV $unknown, errors $errors"
echo "advisories: $rows rows, $ids distinct"
echo "unknown: $unknown ($triage)"
echo "files: $out/advisories.tsv $out/unknown.tsv $out/errors.tsv"
