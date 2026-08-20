# ai module entry point. opencode's own configuration lives in
# ./opencode.nix and the MCP servers it talks to in ./mcp.nix.
{ ... }: {
  imports = [
    ./opencode.nix
    ./mcp.nix
  ];
}