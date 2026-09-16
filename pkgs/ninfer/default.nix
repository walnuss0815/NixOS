{ lib, fetchFromGitHub, cudaPackages, cmake, ninja, pkg-config, ffmpeg, curl }:

# https://github.com/Neroued/ninfer
#
# From-scratch C++/CUDA inference engine hard-locked to a single NVIDIA
# GeForce RTX 5090 (CMAKE_CUDA_ARCHITECTURES=120a; the upstream CMakeLists.txt
# refuses to configure for any other architecture). Not packaged in nixpkgs,
# has no tagged releases and ships no prebuilt binaries, so this pins an
# explicit commit and builds from source.
#
# KNOWN OPEN ITEMS (see hosts/owhug-pc1/NINFER-SETUP.md):
#   - `hash` below is a placeholder (lib.fakeHash). The first build attempt
#     on owhug-pc1 will fail with the real sha256 in the error message;
#     paste that in and rebuild.
#   - Upstream's own measurements use CUDA 13.1 (`sm_120a`). This derivation
#     uses whatever `cudaPackages` resolves to by default in nixpkgs at
#     build time, which was CUDA 12.9 when last checked — verify this is
#     new enough to target sm_120a before spending time debugging unrelated
#     build failures. If it isn't, pin `cudaPackages_13` (or whatever the
#     current attribute is) explicitly via an overlay.
cudaPackages.backendStdenv.mkDerivation {
  pname = "ninfer";
  version = "unstable-2026-09-16";

  src = fetchFromGitHub {
    owner = "Neroued";
    repo = "ninfer";
    rev = "1d8587bcfe850fba310d8833552f3c0c07e3a4bd";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [ cmake ninja pkg-config cudaPackages.cuda_nvcc ];

  buildInputs = [
    cudaPackages.cuda_cudart
    cudaPackages.cudatoolkit
    ffmpeg
    curl
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_CUDA_ARCHITECTURES=120a"
    "-DNINFER_BUILD_APPS=ON"
    "-DBUILD_TESTING=OFF"
    "-DNINFER_BUILD_BENCHMARKS=OFF"
  ];

  # Upstream has no install target ("There is no install target or packaged
  # binary distribution; run NInfer from its source build tree" - README).
  # Ship the two product binaries (CLI + OpenAI/Anthropic-compatible server)
  # ourselves instead of the whole build tree.
  installPhase = ''
    runHook preInstall
    install -Dm755 apps/ninfer $out/bin/ninfer
    install -Dm755 apps/ninfer-serve $out/bin/ninfer-serve
    runHook postInstall
  '';

  meta = {
    description = "From-scratch single-GPU CUDA inference engine for Qwen3.5/3.6/3.8 dense and MoE checkpoints, hard-locked to one NVIDIA RTX 5090 (sm_120a)";
    homepage = "https://github.com/Neroued/ninfer";
    license = lib.licenses.asl20;
    mainProgram = "ninfer-serve";
    platforms = [ "x86_64-linux" ];
  };
}
