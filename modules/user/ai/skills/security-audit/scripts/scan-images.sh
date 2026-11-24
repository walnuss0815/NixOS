#!/usr/bin/env bash
# Scan container images with a local Trivy server and summarise the results.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scan-images.sh <image-list> <out-dir>

Scan every image in <image-list> (one reference per line) for
vulnerabilities with a local Trivy server, several images at a time, and
write to <out-dir>:

  summary.tsv  image, status, critical, high, medium, low, fixable
  fixes.tsv    image, cve, severity, package, installed, fixed, trivy_status
               (CRITICAL and HIGH only)
  fixes.md     the fixes.tsv rows as a Markdown table

Status: "scanned" (anonymous pull), "scanned (login: docker|podman)" (pulled
in the pass using that login file) or "not scanned (<reason>)". Images are
pulled straight from the registry: one pass per existing Docker/Podman login
file, then an anonymous pass for whatever is left. Results
already in <out-dir>/raw/ are reused, so re-running only scans what's missing.

Only one scan runs at a time across audits: a second call waits for the
lock /tmp/opencode/trivy-cache.lock. Run it in the foreground without a
shell timeout.

Exit codes: 0 done, 1 trivy not available, 2 bad arguments,
3 Trivy server did not start.
EOF
}

case ${1:-} in -h | --help) usage; exit 0 ;; esac
[ $# -eq 2 ] && [ -r "$1" ] || { usage >&2; exit 2; }
list=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)
trivy=$(bash "$here/tool.sh" trivy) || exit 1

# Kept between audits: vulnerability DB, Java DB and analysed layers.
cache=/tmp/opencode/trivy-cache
lock=/tmp/opencode/trivy-cache.lock
# shortcut: fixed port and shared cache, so scans are serialised by the lock;
# use a per-run port and cache if parallel scans are ever needed.
addr=127.0.0.1:4954
# 6 parallel pulls keep a typical line busy without tripping registry limits.
parallel=6
mkdir -p "$out/raw" "$cache"
out=$(cd "$out" && pwd)
raw=$out/raw

key() { printf '%s' "$1" | cksum | cut -d' ' -f1; }

# --- lock -------------------------------------------------------------------
owned=0
spid=
xpid=
cleanup() {
  if [ -n "$xpid" ]; then kill "$xpid" 2>/dev/null || true; fi
  if [ -n "$spid" ]; then
    kill "$spid" 2>/dev/null || true
    wait "$spid" 2>/dev/null || true
  fi
  if [ "$owned" = 1 ]; then rm -rf "$lock"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

waited=0
until mkdir "$lock" 2>/dev/null; do
  owner=$(cat "$lock/owner.pid" 2>/dev/null || true)
  # Alive means the PID still runs scan-images (not a reused PID); ps needs no
  # signal permission, so other sandboxes' scans count as alive too.
  if [ -n "$owner" ] && ps -p "$owner" -o args= 2>/dev/null | grep -q scan-images; then
    if [ $((waited % 60)) -eq 0 ]; then
      echo "scan-images: waiting for scan lock held by PID $owner" >&2
    fi
  elif [ -n "$owner" ] || [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    # Owner is gone (or never wrote its PID): stop its server, take over.
    # shortcut: two waiters taking over the same stale lock can race; delete
    # the lock by hand if two servers ever fight over the port.
    old=$(cat "$lock/server.pid" 2>/dev/null || true)
    if [ -n "$old" ] && ps -p "$old" -o comm= 2>/dev/null | grep -q trivy; then
      echo "scan-images: stopping leftover Trivy server PID $old" >&2
      kill "$old" 2>/dev/null || true
      while kill -0 "$old" 2>/dev/null; do sleep 1; done
    fi
    rm -rf "$lock"
    continue
  fi
  sleep 5
  waited=$((waited + 5))
done
owned=1
echo $$ >"$lock/owner.pid"

# --- logins -----------------------------------------------------------------
# Trivy reads only one login file, so each one gets its own pass. The file is
# symlinked as config.json, never copied or read.
# An explicit empty config keeps Trivy anonymous: without one it falls back
# to ~/.docker/config.json and fails hard if that can't be opened.
anon=$out/auth/anonymous
mkdir -p "$anon"
echo '{}' >"$anon/config.json"
dirs=()
labels=()
add_login() {
  local f=$1 d
  # Opening (not reading) the file catches sandboxes that pass test -r.
  [ -n "$f" ] && (: <"$f") 2>/dev/null || return 0
  for d in "${dirs[@]+"${dirs[@]}"}"; do [ "$(readlink "$d/config.json")" = "$f" ] && return 0; done
  d=$out/auth/${#dirs[@]}
  mkdir -p "$d"
  ln -sf "$f" "$d/config.json"
  dirs+=("$d")
  labels+=("$2")
}
add_login "${DOCKER_CONFIG:-$HOME/.docker}/config.json" docker
add_login "${REGISTRY_AUTH_FILE:-}" podman
[ -n "${XDG_RUNTIME_DIR:-}" ] && add_login "$XDG_RUNTIME_DIR/containers/auth.json" podman
add_login "${XDG_CONFIG_HOME:-$HOME/.config}/containers/auth.json" podman
# Anonymous always comes last: public images still scan when a login file's
# credential helper is broken or missing.
dirs+=("$anon")
labels+=(anonymous)
clean_env=(-u TRIVY_USERNAME -u TRIVY_PASSWORD -u TRIVY_REGISTRY_TOKEN)

# --- server -----------------------------------------------------------------
# The databases are public: fetch them anonymously.
env "${clean_env[@]}" DOCKER_CONFIG="$anon" "$trivy" image --download-java-db-only --cache-dir "$cache" --quiet >&2 ||
  echo "scan-images: Java DB download failed; Java images may be incomplete" >&2
env "${clean_env[@]}" DOCKER_CONFIG="$anon" "$trivy" server --listen "$addr" --cache-dir "$cache" >"$out/server.log" 2>&1 &
spid=$!
echo "$spid" >"$lock/server.pid"
# The first start downloads the vulnerability DB; 5 minutes covers slow lines.
for _ in $(seq 300); do
  kill -0 "$spid" 2>/dev/null || break
  curl -sf --noproxy "*" "http://$addr/healthz" >/dev/null 2>&1 && break
  sleep 1
done
if ! kill -0 "$spid" 2>/dev/null || ! curl -sf --noproxy "*" "http://$addr/healthz" >/dev/null 2>&1; then
  echo "scan-images: Trivy server did not start; see $out/server.log" >&2
  exit 3
fi

# --- scans ------------------------------------------------------------------
scan_one() {
  local img=$1 cfg=$2 label=$3 timeout=$4 k
  k=$(key "$img")
  [ -e "$raw/$k.tsv" ] && return 0
  if env -u TRIVY_USERNAME -u TRIVY_PASSWORD -u TRIVY_REGISTRY_TOKEN DOCKER_CONFIG="$cfg" "$trivy" image --server "http://$addr" --image-src remote \
    --scanners vuln --skip-java-db-update --cache-dir "$cache" --timeout "$timeout" \
    --quiet --format template --template "@$tpl" --output "$raw/$k.tmp" "$img" \
    </dev/null 2>"$raw/$k.err"; then
    echo "$label" >"$raw/$k.via"
    mv "$raw/$k.tmp" "$raw/$k.tsv"
  else
    rm -f "$raw/$k.tmp"
  fi
}
export -f scan_one key
export trivy addr cache raw
export tpl=$here/trivy-vulns.tpl

images() { grep -v '^[[:space:]]*\(#\|$\)' "$list"; }
pending() {
  local img
  while IFS= read -r img; do [ -e "$raw/$(key "$img").tsv" ] || echo "$img"; done < <(images)
}
reused=$(($(images | wc -l) - $(pending | wc -l)))

run_pass() {
  pending | xargs -P "$parallel" -I{} bash -c 'scan_one "$@"' _ {} "$1" "$2" "$3" &
  xpid=$!
  wait "$xpid" || true
  xpid=
}
# 15 minutes fits all but the largest images; they get 30 in the last pass.
for i in "${!dirs[@]}"; do run_pass "${dirs[$i]}" "${labels[$i]}" 15m; done
run_pass "${dirs[0]}" "${labels[0]}" 30m

# --- outputs ----------------------------------------------------------------
printf 'image\tstatus\tcritical\thigh\tmedium\tlow\tfixable\n' >"$out/summary.tsv"
printf 'image\tcve\tseverity\tpackage\tinstalled\tfixed\ttrivy_status\n' >"$out/fixes.tsv"
{
  echo '| Image | CVE | Severity | Package | Installed | Fixed | Trivy status |'
  echo '|---|---|---|---|---|---|---|'
} >"$out/fixes.md"
failed=()
while IFS= read -r img; do
  k=$(key "$img")
  if [ -e "$raw/$k.tsv" ]; then
    via=$(cat "$raw/$k.via")
    case $via in anonymous) status=scanned ;; *) status="scanned (login: $via)" ;; esac
    awk -F'\t' -v img="$img" -v st="$status" -v s="$out/summary.tsv" -v f="$out/fixes.tsv" -v m="$out/fixes.md" '
      function md(x) { gsub(/\|/, "\\|", x); return x }
      NF < 6 { next }
      { n[$1]++ }
      $1 == "CRITICAL" || $1 == "HIGH" {
        if ($5 != "") fx++
        print img "\t" $2 "\t" $1 "\t" $3 "\t" $4 "\t" $5 "\t" $6 >> f
        print "| " md(img) " | " md($2) " | " $1 " | " md($3) " | " md($4) " | " md($5) " | " $6 " |" >> m
      }
      END { printf "%s\t%s\t%d\t%d\t%d\t%d\t%d\n", img, st, n["CRITICAL"], n["HIGH"], n["MEDIUM"], n["LOW"], fx >> s }
    ' "$raw/$k.tsv"
  else
    # Drop URL query strings (signed URLs, token scopes) but keep the error after them.
    reason=$(grep -v '^[[:space:]]*$' "$raw/$k.err" 2>/dev/null | tail -1 | tr '\t' ' ' |
      sed -e 's/?[^ ]*//g' -e 's/^[[:space:]]*\*[[:space:]]*//' | cut -c1-160)
    printf '%s\tnot scanned (%s)\t\t\t\t\t\n' "$img" "${reason:-unknown error}" >>"$out/summary.tsv"
    failed+=("$img: ${reason:-unknown error}")
  fi
done < <(images)

total=$(images | wc -l)
echo "images: $((total)) (reused $reused), scanned $((total - ${#failed[@]})), not scanned ${#failed[@]}"
echo "summary: $out/summary.tsv"
echo "fixes: $out/fixes.tsv"
echo "fixes (markdown): $out/fixes.md"
if [ ${#failed[@]} -gt 0 ]; then
  for f in "${failed[@]:0:10}"; do echo "not scanned: $f"; done
fi
