# Settings shared by every host, including the headless adsb-pi1: locale,
# time zone, console keymap, nix features and the base user account. Hosts
# add their own groups and options on top (list options merge).
{ ... }:

{
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  console.keyMap = "de";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Pinned in /etc/ssh/ssh_known_hosts, which (unlike ~/.ssh/known_hosts,
  # replaced on every UpdateHostKeys rewrite) the opencode sandbox can
  # always read. github.com keys: https://api.github.com/meta;
  # gitlab.com keys: https://docs.gitlab.com/user/gitlab_com/#ssh-known_hosts-entries;
  # gitlab.opencode.de keys: ssh-keyscan, fingerprints checked against
  # the known_hosts of a trusted machine.
  programs.ssh.knownHosts = {
    "github.com-ed25519" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
    "github.com-ecdsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=";
    };
    "github.com-rsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=";
    };
    "gitlab.com-ed25519" = {
      hostNames = [ "gitlab.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";
    };
    "gitlab.com-ecdsa" = {
      hostNames = [ "gitlab.com" ];
      publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=";
    };
    "gitlab.com-rsa" = {
      hostNames = [ "gitlab.com" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9";
    };
    "gitlab.opencode.de-ed25519" = {
      hostNames = [ "gitlab.opencode.de" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZv8TTjbbH1Sy+pq5ZiQdMJuNXWlFplsLycAjSiZH0/";
    };
    "gitlab.opencode.de-ecdsa" = {
      hostNames = [ "gitlab.opencode.de" ];
      publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJnzzPgho4rAvvlCacw4J5mxDToE3Co1kYo+jjSH+PVlbM9dokao5GmUVP1bal8Z7BLIasRl3vowmm2xEMjmGKs=";
    };
    "gitlab.opencode.de-rsa" = {
      hostNames = [ "gitlab.opencode.de" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXGZ5sVmPJZBZ5MUcrQr1nFpfQLaXyJXJR8RgfhP4B+uDQmRea7nLHawhgWnuSLRN0QOalEGEPQK0QJMcsyRv0/JVA+yCzY8TtuP6S4w8K/0cjhek5XSA7UhDNi7wsDJaZSnP5A5NpCKThEkCoXB4CeL3aPJATnHRhEMsBMSHBGT2HyJHtQRB14SXil86lT5ZKwzutQs5Dqoa0GRf5uM2Zo5bLd9TQ9wSJiBJjybygVO/ARSx7DbfJGu3bJWYC3RzqS4IbzEZ2uuI3EEvZSWh3llDDxp0DxeuBEi30jrQAcNkC8HU+tF6M0uBcmtJAt+0KdzpmBqFotjs2mp22I6u4EWpZRLuJdwqOjIx+8cy5L8XhVQJTznWubu/heHNr1Plb4WNXLrF4HSz6k9KqHYWaBmeoa8YuDgZt3A1wo67Ns1zmwolpjxRcMEk5kEg/QRbD3RfnY5LU4ZXbiU5O8kJtp9FreEsnPb/+c+TXL4EN85x0qLfnElAWiJTC8AUCxcc=";
    };
  };

  users.users.alexander = {
    isNormalUser = true;
    description = "Alexander Weidemann";
    extraGroups = [ "wheel" ];
  };
}
