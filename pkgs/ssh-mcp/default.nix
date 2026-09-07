{ lib, buildNpmPackage, fetchurl }:

# https://github.com/tufantunc/ssh-mcp
#
# Not (yet) packaged in nixpkgs. The npm tarball ships a prebuilt
# build/index.js but no package-lock.json for its runtime dependencies.
#
# ./package.json and ./package-lock.json are vendored copies of the
# published package.json (with the unused "devDependencies"/"scripts"
# fields stripped) and a package-lock.json generated once via
# `npm install --package-lock-only` against its declared runtime
# dependencies. This makes npmDepsHash reproducible and lets the server be
# built fully offline/pinned by Nix instead of fetched at MCP-server-
# startup time via `npx ssh-mcp@<version>`.
buildNpmPackage rec {
  pname = "ssh-mcp";
  version = "2.8.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/ssh-mcp/-/ssh-mcp-${version}.tgz";
    hash = "sha512-jd/0hFQd0Yol+Es2wv5J6DhVGInZwPhPOb8CnpJwlqAssvHddIl8OYZcqO1enTtE9Sz0SA2XbK5d0EIG4uX5+Q==";
  };

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-OC+cplytKjrCuhMzg1ldYQMp2XvyBjdIW/DX568Jl+I=";

  # ssh2's optional `cpu-features`/`nan` native addon is just a CPU-detection
  # speed-up (pure-JS fallback works fine); skip its install script instead
  # of pulling in a C++ toolchain for it.
  npmFlags = [ "--ignore-scripts" ];

  # build/index.js is already built and published as-is.
  dontNpmBuild = true;

  meta = {
    description = "MCP server exposing policy-gated, audited SSH access for Linux and Windows hosts";
    homepage = "https://github.com/tufantunc/ssh-mcp";
    changelog = "https://github.com/tufantunc/ssh-mcp/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "ssh-mcp";
    platforms = lib.platforms.unix;
  };
}
