{ pkgs, config, ... }: {
  home.packages = with pkgs; [
    (bambu-studio.overrideAttrs (oldAttrs: {
      cmakeFlags = oldAttrs.cmakeFlags ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
    }))
  ];
}
