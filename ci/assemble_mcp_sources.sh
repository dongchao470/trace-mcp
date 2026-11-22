#!/bin/sh
# Rebuilds the MCP server sources from the size-limited chunks committed under ci/mcp/.
set -eu
mkdir -p TraceCore/MCP
cat ci/mcp/MCPJSON.swift.part* > TraceCore/MCP/MCPJSON.swift
cat ci/mcp/TraceMCPServer.swift.part* > TraceCore/MCP/TraceMCPServer.swift
cat ci/mcp/TraceMCPTools.swift.part* > TraceCore/MCP/TraceMCPTools.swift
cat ci/mcp/TraceMCPPreferences.swift.part* > TraceCore/MCP/TraceMCPPreferences.swift
# Reviewed follow-up: loopback interface bind, peer diagnostics and runtime self test.
for patch in ci/ios16-mcp-server-a.patch ci/ios16-mcp-server-b.patch ci/ios16-mcp-server-c.patch ci/ios16-mcp-retain.patch; do
  git apply --check "$patch"
  git apply "$patch"
done
wc -c TraceCore/MCP/*.swift
