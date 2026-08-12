{ lib, python3, fetchFromGitHub }:

# https://github.com/realiti4/claude-swap
#
# Multi-account switcher for Claude Code: switch between multiple Claude
# accounts without logging out, with automatic rate-limit rotation, a
# usage dashboard, and parallel sessions.

python3.pkgs.buildPythonApplication rec {
  pname = "claude-swap";
  version = "0.25.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "realiti4";
    repo = "claude-swap";
    tag = "v${version}";
    hash = "sha256-BDfwyH7h7Ii7QYaunHDnf0Epk5nUEd8OdOH3QCf1CJU=";
  };

  build-system = with python3.pkgs; [ hatchling ];

  dependencies = with python3.pkgs; [ textual truststore ];

  # No test dependencies (pytest, pytest-asyncio, pytest-xdist) are wired up
  # here, and the suite needs a real terminal/keychain environment.
  doCheck = false;

  pythonImportsCheck = [ "claude_swap" ];

  meta = {
    description = "Switch between multiple Claude Code accounts, with automatic rate-limit rotation, usage dashboard, and parallel sessions";
    homepage = "https://github.com/realiti4/claude-swap";
    changelog = "https://github.com/realiti4/claude-swap/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "cswap";
    platforms = lib.platforms.unix;
  };
}
