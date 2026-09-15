{ lib, stdenvNoCC, fetchFromGitHub, glib }:

# https://github.com/dvdstelt/ClaudeCodeUsage
#
# Not (yet) packaged in nixpkgs, even though it's published on
# extensions.gnome.org (https://extensions.gnome.org/extension/10086/). The
# upstream repo has no git tags, so this is pinned to a `main` commit instead
# of a release tag; bump the rev/hash together when updating.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gnome-shell-extension-claude-usage";
  version = "1.4.1-unstable-2026-08-28";

  src = fetchFromGitHub {
    owner = "dvdstelt";
    repo = "ClaudeCodeUsage";
    rev = "4ded0ccd289e48c4f316b5ce7a1ab8c0c2147e55";
    hash = "sha256-If0KCyJj+ZKLdGSvJbIdCHNm6zptPNv2umiNb9nnCmA=";
  };

  nativeBuildInputs = [ glib ];

  dontConfigure = true;
  dontBuild = true;

  uuid = "claude-usage@dvdstelt.github.io";

  installPhase = ''
    runHook preInstall

    target=$out/share/gnome-shell/extensions/${finalAttrs.uuid}
    mkdir -p "$target"
    cp -r src/* "$target/"
    glib-compile-schemas "$target/schemas"

    runHook postInstall
  '';

  passthru.extensionUuid = finalAttrs.uuid;

  meta = {
    description = "Shows your Claude subscription tier and live usage limits in the GNOME top bar";
    homepage = "https://github.com/dvdstelt/ClaudeCodeUsage";
    changelog = "https://github.com/dvdstelt/ClaudeCodeUsage/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
})
