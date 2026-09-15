{ pkgs, ... }:

let
  addons = pkgs.nur.repos.rycee.firefox-addons;

  # Extensions installed in both profiles today.
  sharedExtensions = [
    addons.bitwarden
    addons."multi-account-containers"
    addons."ublock-origin"
  ];
in
{
  # Profiles are pinned to their existing on-disk directories (see
  # ~/.mozilla/firefox/profiles.ini) so this takes over management of the
  # profiles you already have instead of creating new ones. Extensions that
  # aren't packaged in nur.repos.rycee.firefox-addons (bibbot, cookies-txt,
  # linkwarden, view-image-info-reborn, youtube-anti-translate,
  # clockify-time-tracker, ...) are intentionally left out and continue to
  # be self-managed through about:addons.
  programs.firefox = {
    enable = true;

    # Explicit rather than relying on the stateVersion-gated default, so a
    # future stateVersion bump can't silently switch this to the new XDG
    # path (~/.config/mozilla/firefox) and break the profile pinning above.
    configPath = ".mozilla/firefox";

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
    };

    profiles = {
      Private = {
        id = 0;
        isDefault = true;
        path = "tmv2fx59.default";
        storeId = "8e3d3fa2";

        extensions.packages = sharedExtensions ++ [
          addons.tampermonkey
          addons.sponsorblock
          addons.keepa
        ];
      };

      Work = {
        id = 1;
        path = "lq3gxhd1.Work";

        extensions.packages = sharedExtensions;
      };
    };
  };
}
