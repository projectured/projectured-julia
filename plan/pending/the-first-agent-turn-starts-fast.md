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
- [x] 3. The transcript says "Starting Claude Code…" while the session opens
  (a48fafca1): the turn shows at once with that part, leaves the conversation
  when the session is open, and comes back after the prompt, so a message that
  the person sends meanwhile stays above the answer; a start that fails leaves
  no turn. `test_external_agent_turn` 269 of 269.

## The cause, found 2026-10-12

The owner's second try took four minutes to start `claude`, with the machine
idle, and became fast at once when the owner closed the Assistants tab. The
elapsed column of that table reads the frame clock of the editor while a turn
runs, and `compute_wait_timeout` answers `FRAME_INTERVAL` (0.01 s) while any
cell depends on that clock, so the window redraws without a pause for the whole
turn. The tasks of the agent (the ACP connection, the readers of `claude`, and
the HTTP servers, which HTTP.jl starts in the interactive pool, the thread of
the editor) get only the gaps between those frames. More threads do not help:
with more than one thread the SDL backend waits in 100 ms slices, and the start
took 80 s instead of 37 s.

So step 1 aims at a cause that the evidence does not support. Question to the
owner: replace step 1 by a clock of whole seconds for a label such as the
elapsed time, which wakes the loop once a second and not on every frame?

## Not in this plan

The tasks of the agent move off the thread of the editor.
