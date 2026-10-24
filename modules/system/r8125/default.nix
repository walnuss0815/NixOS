# shortcut: backport of nixpkgs master's r8125 fix (install via
# modules_install so kmodigest's .ko.cer is produced); drop this module
# and its flake.nix imports once it reaches nixos-unstable.
{ ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      linuxPackages_latest = prev.linuxPackages_latest.extend (
        lpFinal: lpPrev: {
          r8125 = lpPrev.r8125.overrideAttrs (old: {
            preBuild = "";
            postPatch = ''
              substituteInPlace src/Makefile --replace-fail "BASEDIR :=" "BASEDIR ?="
            '';
            makeFlags = old.makeFlags ++ [
              "INSTALL_MOD_PATH=${placeholder "out"}"
              "INSTALL_MOD_DIR=kernel/drivers/net/ethernet/realtek"
              "INSTALL_MOD_STRIP=1"
              "DEPMOD=true"
            ];
            installPhase = null;
            installTargets = [ "modules_install" ];
            installFlags = [
              "-C"
              "${lpFinal.kernel.dev}/lib/modules/${lpFinal.kernel.modDirVersion}/build"
              "M=$(PWD)/src"
            ];
          });
        }
      );
    })
  ];
}
