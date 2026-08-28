{ lib, stdenv, fetchurl }:

# https://github.com/containers/kubernetes-mcp-server
#
# Not (yet) packaged in nixpkgs. Upstream only publishes it to npm, as a
# thin JS shim ("kubernetes-mcp-server") that spawns a prebuilt, statically
# linked Go binary shipped as a separate per-platform optionalDependency
# (e.g. "kubernetes-mcp-server-linux-amd64"). Fetching that platform
# binary tarball directly and installing it verbatim gives the exact same
# binary `npx kubernetes-mcp-server@<version>` would run, but pinned by
# Nix and available offline after the first build - no npm/network
# fetch at MCP-server-startup time.
stdenv.mkDerivation (finalAttrs: {
  pname = "kubernetes-mcp-server";
  version = "0.0.66";

  src = fetchurl {
    url = "https://registry.npmjs.org/kubernetes-mcp-server-linux-amd64/-/kubernetes-mcp-server-linux-amd64-${finalAttrs.version}.tgz";
    hash = "sha512-kIp988KslasSKw8Vo6ZCePxVMX8GZvAb+WVWW1YtZAswxF/k2vFVYS858trw4Hnjp6pCqThd60yiizroiNC2xw==";
  };

  # Keep the extracted "package/" prefix instead of the default behaviour
  # of cd-ing into it, since installPhase below references that path.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 package/bin/kubernetes-mcp-server-linux-amd64 $out/bin/kubernetes-mcp-server
    runHook postInstall
  '';

  meta = {
    description = "Model Context Protocol (MCP) server for Kubernetes and OpenShift";
    homepage = "https://github.com/containers/kubernetes-mcp-server";
    changelog = "https://github.com/containers/kubernetes-mcp-server/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "kubernetes-mcp-server";
    platforms = [ "x86_64-linux" ];
  };
})
