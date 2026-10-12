# The first turn of an agent starts fast, and says that it starts

> **Status:** in progress (the owner asked for 1, 2 and 3 on 2026-10-12)

## Goal

The owner ran `bin/projectured --assistant=acp`, sent a prompt, and saw nothing
for more than a minute. The session of Claude Code shows why: the agent got the
prompt at once, but the two MCP servers in the editor process (the tools of the
editor and the permission tool of ClaudeCodeACP) did not answer within the 30 s
that `claude` gives them, so the agent ran without them, and its answer came
when the owner closed the editor. The first use of the code of the agent
compiles on the thread of the editor, which the HTTP servers share, and the
machine had a load of 50 to 60.

## Steps

- [ ] 1. A precompile workload covers the path of the first turn of an agent, so
  that it does not compile on the thread of the editor.
- [x] 2. ClaudeCodeACP 0.1.8 starts `claude` with `MCP_TIMEOUT=120000` unless the
  environment sets it (branch `mcp-timeout`, 290f793; 165 tests pass).
- [ ] 3. The transcript says "Starting Claude Code…" while the session opens.

## Not in this plan

The tasks of the agent move off the thread of the editor.
