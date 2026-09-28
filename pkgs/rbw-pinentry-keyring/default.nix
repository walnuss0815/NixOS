{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  libsecret,
  pinentry-gnome3,
}:

# https://github.com/doy/rbw/blob/main/bin/rbw-pinentry-keyring
#
# Official pinentry shim shipped in rbw's own repo. Used as rbw's
# `pinentry` (see modules/user/bitwarden/default.nix): on the "Master
# Password" prompt specifically, it looks up the password from the
# Secret Service keyring (GNOME Keyring) via secret-tool first; if
# nothing is stored yet, it falls back to a real pinentry-gnome3 prompt
# once and stores whatever is entered for next time. Every other prompt
# (2FA codes, etc.) always goes to the real pinentry-gnome3 - never
# auto-answered.
#
# Security note: this stores the Bitwarden master password in
# plaintext in the login keyring, which auto-unlocks at login. Run
# `rbw-pinentry-keyring clear` to remove it and fall back to manual
# entry again.

stdenvNoCC.mkDerivation rec {
  pname = "rbw-pinentry-keyring";
  version = "1.15.0";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/doy/rbw/${version}/bin/rbw-pinentry-keyring";
    hash = "sha256-DoIapbUy+YbKvtERTMZZ43wOXT0QYPTFO8CxeywWH84=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/rbw-pinentry-keyring
    wrapProgram $out/bin/rbw-pinentry-keyring \
      --prefix PATH : ${lib.makeBinPath [ libsecret pinentry-gnome3 ]}
    runHook postInstall
  '';

  meta = {
    description = "pinentry shim that caches rbw's master password in the system keyring";
    homepage = "https://github.com/doy/rbw";
    license = lib.licenses.mit;
    mainProgram = "rbw-pinentry-keyring";
    platforms = lib.platforms.linux;
  };
}
