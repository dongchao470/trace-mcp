# Trace MCP endpoint

- JSON-RPC over HTTP on loopback: `POST http://127.0.0.1:6180/mcp`
- Health probe: `GET http://127.0.0.1:6180/health`
- UI: Settings -> Integrations -> MCP Server (enable, port, status, self test, tool list)
- Hosted by the app while it is active, and by the tunnel extension while the VPN runs
- The listener binds the loopback interface and falls back to a wildcard bind guarded by a peer check
- Runtime state (listening, last error, last peer, self check) is mirrored to `mcp-status.json` in the app group container
- Tools: trace_status, list_sessions, list_requests, get_request, search_requests, replay_request, list_rewrite_rules, clear_requests
- Build 3: settings screen imports Combine and Foundation for the refresh timer.
