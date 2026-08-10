{ pkgs, config, ... }:

{
  # Provides the dynamic linker/loader that generic (non-NixOS) dynamically
  # linked binaries expect, e.g. standalone Python builds downloaded by
  # `uv`/`uvx`.
  # See: https://nix.dev/permalink/stub-ld
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [ ];
  };
}
