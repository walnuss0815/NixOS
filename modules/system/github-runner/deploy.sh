#!/usr/bin/env bash
# Deploy the current checkout to one or more runner hosts and restart their
# runner service once no job is running.
#
# The module sets restartIfChanged = false, so `nixos-rebuild switch` alone
# leaves the runner (and Docker) on the old configuration until the next
# reboot. This script does the switch, waits until the runner is idle,
# restarts it and checks the result. Hosts are handled one at a time, so
# the other runners keep taking jobs.
#
# Usage (from a checkout of this repository):
#   modules/system/github-runner/deploy.sh rpp-github-runner1
#   modules/system/github-runner/deploy.sh rpp-github-runner2 rpp-github-runner3
#
# Environment:
#   DEPLOY_USER  SSH user on the hosts (default: alexander)
#   MAX_WAIT     seconds to wait for an idle runner per host (default: 7200)
#
# The hosts also pull github:walnuss0815/NixOS/wip every night. Deploy a
# branch that is not merged yet and the next nightly switch undoes it.
# The remote commands below are meant to expand their variables locally.
# shellcheck disable=SC2029
set -euo pipefail

user=${DEPLOY_USER:-alexander}
max_wait=${MAX_WAIT:-7200}
service=github-runner-rpp
work_dir=/var/lib/github-runner-work
home_dir=/var/lib/github-runner-home

[ $# -gt 0 ] || {
  echo "usage: $0 <host>..." >&2
  exit 2
}

# Counts url.*.insteadOf rules in the global git config of the runner user
# for the given HOME, without printing them (their names contain tokens).
count_rules() {
  ssh "$user@$1" "sudo -u github-runner env HOME=$2 git config --global --name-only --get-regexp '^url\\..*\\.insteadof\$' 2>/dev/null | wc -l"
}

for host in "$@"; do
  # The address is taken from the flake, so it cannot drift from the config.
  ip=$(nix eval --json ".#nixosConfigurations.$host.config.systemd.network.networks.\"10-lan\".address" |
    jq -r '.[0] | split("/")[0]')
  [ -n "$ip" ] && [ "$ip" != null ] || {
    echo "no address found for host: $host" >&2
    exit 2
  }
  echo "=== $host ($ip)"
  echo "--- insteadOf rules in the old HOME before: $(count_rules "$ip" "$work_dir")"

  echo "--- switching"
  nixos-rebuild switch --flake ".#$host" --target-host "$user@$ip" --sudo

  # Make sure the new HOME exists before the runner uses it.
  ssh "$user@$ip" "sudo systemd-tmpfiles --create --prefix=$home_dir"

  echo "--- waiting for the runner to be idle"
  waited=0
  # A Runner.Worker process exists only while a job runs. The bracket keeps
  # pgrep from matching the remote shell's own command line.
  while ssh "$user@$ip" 'pgrep -f "[R]unner.Worker" >/dev/null'; do
    [ "$waited" -lt "$max_wait" ] || {
      echo "a job is still running after ${max_wait}s on $host, not restarting it" >&2
      exit 1
    }
    sleep 15
    waited=$((waited + 15))
  done

  echo "--- restarting $service"
  ssh "$user@$ip" "sudo systemctl restart $service"
  sleep 10

  echo "--- checks"
  ssh "$user@$ip" "
    set -e
    systemctl is-active $service
    systemctl show $service -p Environment | sed 's/^Environment=//' | tr ' ' '\\n' |
      grep -E '^(HOME|ACTIONS_RUNNER_HOOK_JOB_(STARTED|COMPLETED))='
    stat -c '%U:%G %a %n' $home_dir
    sudo journalctl -u $service -n 5 --no-pager
  "
  echo "--- insteadOf rules after: old HOME $(count_rules "$ip" "$work_dir"), new HOME $(count_rules "$ip" "$home_dir")"
done
