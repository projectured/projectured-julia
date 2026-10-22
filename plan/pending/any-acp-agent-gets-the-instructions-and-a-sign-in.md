# Any ACP agent gets the instructions and a sign-in

> **Status (2026-10-22): steps 1 and 2 done.** Branch `acp-neutral`, worktree
> `projectured-julia-acp-neutral`. The owner said yes to the new mechanism of
> step 2 (Q1). Step 3 waits for the owner.

## Goal

`ProjecturedACP` works with an ACP agent that is not a Claude agent, such as
`codex-acp`, the ACP agent for Codex. Two parts of the client are now shaped
for the Claude agents:

1. **The instructions of a session.** The client puts them only into
   `_meta.claudeCode.options.systemPrompt.append`. Another agent ignores that
   key, so it never gets the rules and the examples of the editor.
2. **The sign-in.** The client offers only a method of the type `terminal`. A
   method of the type `agent`, the default type of ACP, gets no button: the
   agent runs that sign-in itself when the client sends `authenticate`.

The owner asked for both fixes on 2026-10-22, before the question of a Julia
agent for Codex: "the ACP fixes are good anyway because some users may use the
official ACP".

## Facts (2026-10-22)

- `codex-acp` 2.2.2 (`agentclientprotocol/codex-acp`, Apache-2.0, TypeScript
  on Node.js) advertises `sessionCapabilities.systemPrompt` and reads the field
  `systemPrompt` of `session/new` and `session/resume`:
  `{"mode": "append", "content": [{"type": "text", "text": …}]}`. It refuses
  another mode and a block that is not text with `INVALID_PARAMS`. The field is
  unstable in the schema of ACP, and `AgentClientProtocol.jl` 0.1.0, made from
  the schema of SDK 1.7.0, has no property for it.
- Its sign-in methods are `chat-gpt` and `api-key`, both of the default type,
  and `chat-gpt-device-code` only for a client with URL elicitation. On
  `authenticate`, `chat-gpt` opens the browser and waits for the sign-in;
  `api-key` with no `_meta` reads `CODEX_API_KEY` or `OPENAI_API_KEY` from the
  environment of the agent. A sign-in that does not complete is the error
  `AUTHENTICATION_REQUIRED`.
- The schema of ACP v1 says of `AuthMethodAgent`: "Agent handles authentication
  itself through `authenticate`. This is the default authentication method
  type."
- ClaudeCodeACP 0.1.9 reads only the `_meta` key, and advertises no
  `sessionCapabilities.systemPrompt`.

## Steps

- [x] **1. The instructions go into `systemPrompt`** when the answer to
  `initialize` has `sessionCapabilities.systemPrompt`; else into the `_meta`
  key, as now. Never both, so an agent that reads both does not get the text
  twice. The request object takes the field on its JSON, so the library does
  not change. Tests on the fake agent: new and resume, with and without the
  capability. Guide: `acp.md`. Done: `_add_system_prompt!` in
  `AcpConnection.jl`; `test_acp()` 310/310, main 301/301.
- [x] **2. A sign-in that the agent runs** (new mechanism, Q1). The kernel:
  `AgentSignInMethod.command` becomes `Union{Cmd,Nothing}`, where `nothing`
  means that the agent runs the sign-in itself; a new generic
  `sign_in_agent!(connection, method_id) -> Bool` beside `sign_out_agent!`,
  with the default `false`. The adapter: a method of the type `agent` gives
  such a method, and `sign_in_agent!` sends `authenticate`. The assistant: the
  button of such a method calls it on a task, and the line of the card says how
  it went; a sign-in that worked starts the agent again, as a terminal sign-in
  does. The scripted agent of the kernel example gets such a method. Tests:
  adapter, turn, card. Guides: `agent.md`, `acp.md`, `assistant.md`.
  Done; decisions made in the implementation and after a review:
  - The sign-in holds the start lock of the session for its whole wait. The
    sign-in error stopped the agent, so the sign-in starts it; a turn or a
    start that comes meanwhile waits for the sign-in, because its own start
    would end the process that runs the sign-in. "Try again" stays enabled and
    waits in the same way.
  - The wait has a bound of five minutes, and a request with no answer in that
    time is withdrawn with `$/cancel_request`. A window that stops the agent,
    at the close of its tab, ends the sign-in at once; there is no stop button
    of its own.
  - An agent that started after a stop of the window stops again, and a
    sign-in that ends after that stop starts nothing.
  - An assistant whose agent stopped with its tab, such as after an undo of
    the close, makes a new session for the sign-in.
  - `_start_agent_task` holds the one way to run an agent task, for the start
    and for the sign-in.
- [ ] **3. A live check with `codex-acp`.** It needs Node.js 22 or newer on
  this machine and a ChatGPT sign-in; the owner decides.

## Questions

- **Q1 (answered yes by the owner, 2026-10-22).** Step 2 adds a generic to the
  agent seam of the kernel and lets the command of a sign-in method be `nothing`. The alternative with no new
  mechanism is a message only: the card says to sign in outside the editor,
  such as with `codex login`. Recommendation: the generic, because the sign-in
  of the default type of ACP then works with every agent.
