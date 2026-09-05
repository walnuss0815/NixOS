{ lib, buildNpmPackage, fetchurl }:

# https://github.com/cyanheads/git-mcp-server
#
# Not (yet) packaged in nixpkgs. Upstream builds its published dist/index.js
# with bun (bun.lock, not npm's package-lock.json format) and doesn't ship a
# package-lock.json in the npm tarball, so buildNpmPackage can't vendor its
# runtime dependencies out of the box.
#
# ./package.json and ./package-lock.json are vendored copies of the
# published package.json (with the (unused, bun-only) "devDependencies" and
# "scripts" fields stripped - "scripts.prepare" runs `bunx husky`, which
# would otherwise fail during `npm pack` in the install phase since bun
# isn't part of this build) and a package-lock.json generated once via
# `npm install --package-lock-only` against its 3 runtime dependencies
# (cross-spawn, pino, pino-pretty). This makes npmDepsHash reproducible
# without a bun toolchain, and offline/pinned by Nix instead of fetched at
# MCP-server-startup time via `npx @cyanheads/git-mcp-server@<version>`.
buildNpmPackage rec {
  pname = "git-mcp-server";
  version = "2.15.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@cyanheads/git-mcp-server/-/git-mcp-server-${version}.tgz";
    hash = "sha512-IuBjTfFhyNCceNwfTWcda2SPiQaGqyo3fw2OVwXzRzPT+vKAybFH4ntZTbZt5VRlpdTIpVevUkmGC0ZY09roLQ==";
  };

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-C9LOlePtzIKtliEosFslqWhQxiKuWVkatn/FaBWnsAw=";

  # dist/index.js is already built and published as-is; only the 3 runtime
  # deps need vendoring, there's nothing left to build.
  dontNpmBuild = true;

  meta = {
    description = "Secure, scalable Git MCP server enabling AI agents to perform Git version-control operations via STDIO/HTTP";
    homepage = "https://github.com/cyanheads/git-mcp-server";
    changelog = "https://github.com/cyanheads/git-mcp-server/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "git-mcp-server";
    platforms = lib.platforms.unix;
  };
}
