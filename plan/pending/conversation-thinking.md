# Conversation thinking — extended-thinking support for the AI assistant

Add **extended thinking** ("reasoning") to the in-editor AI conversation. Claude
emits `thinking` content blocks before its text/tool-use blocks when adaptive
thinking is enabled; today the assistant pipeline ignores them entirely. This
plan makes thinking a first-class part of the conversation domain so it streams,
renders (collapsed by default), and — critically — round-trips back to the API
intact across tool-use turns.

Builds directly on the turn/part redesign in
[conversation-redesign.md](conversation-redesign.md). Same guiding model: **one
part type, the `content` document's type drives projection and serialization.**
A thinking block is just another `content` document kind, alongside `TextText`,
`JuliaDocument`, and `EvaluatorForm`.

## What thinking is, on the wire

The project defaults to `claude-opus-4-8` (Opus 4.x). On that model family:

- **Request:** enable with `thinking = {"type": "adaptive", "display": "summarized"}`.
  `budget_tokens`/`{"type":"enabled"}` are **removed on Opus 4.7/4.8 and return
  a 400** — do not use them. `display` defaults to `"omitted"` (empty thinking
  text); we must set `"summarized"` to receive any readable reasoning.
  `output_config = {"effort": "high"}` is optional and orthogonal.
- **Streaming:** thinking arrives as its own content block, interleaved before
  text/tool_use:
  - `content_block_start` with `content_block.type == "thinking"` (or
    `"redacted_thinking"`).
  - `content_block_delta` with `delta.type == "thinking_delta"` carrying
    `delta.thinking` (the reasoning text, accumulated like `text_delta`).
  - `content_block_delta` with `delta.type == "signature_delta"` carrying
    `delta.signature` — an opaque cryptographic signature that arrives near the
    end of the block.
  - `redacted_thinking` blocks carry an opaque `data` field instead of text and
    arrive without deltas.
- **Round-trip (the load-bearing constraint):** when an assistant turn contains
  thinking **and** is followed by tool use, the thinking blocks must be sent
  back to the API **unchanged — signature included — as the first blocks of the
  assistant message content**, ahead of the `tool_use` block. Stripping or
  reordering them breaks the tool-use continuation (400 / signature error). On a
  plain text turn with no tool call, echoing thinking back is optional, but we
  keep it uniform.

This signature/round-trip role is exactly parallel to how `EvaluatorForm`
carries `tool_use_id` today: API-protocol metadata that lives on the content
document and is re-serialized by `build_messages`.

## Guiding model: thinking is a content type

```
ConversationPart { content::Document, collapsed, selection }   # unchanged, ONE type
   content = ConversationThinking { text::Document, signature::String, redacted::Bool, data::String }   # NEW
```

A thinking part is an ordinary `ConversationPart` whose `content` is a new
`ConversationThinking` document. No new part subtype, no turn changes. The part
gets the same uniform reference path `turns[i].parts[j]`, the same `collapsed`
flag, and the same widget — it just renders and serializes differently because
its content type differs.

`ConversationThinking` fields:

- `text::Document` — the reasoning text (`TextText`; empty when `display` is
  `"omitted"` or for redacted blocks).
- `signature::String` — the opaque signature from `signature_delta` (`""` until
  one arrives; redacted blocks have none).
- `redacted::Bool` — `true` for a `redacted_thinking` block.
- `data::String` — the opaque payload for a redacted block (`""` otherwise).

Why a dedicated content type rather than reusing `TextText`: the `signature` and
`redacted`/`data` carriers are real API metadata that must survive
re-serialization, exactly like `EvaluatorForm.tool_use_id`. A bare `TextText`
would drop them and break the tool-use round-trip. Mirrors the Stage-1 decision
in the redesign plan (genuine carriers move into content document types).

---

# Stages

Each stage is independently testable and leaves the build green. Stages 1–2 are
the gate (model + streaming capture); 3 enables the request; 4 is the
round-trip; 5 is presentation; 6 wires the live panel. Per the repo testing
guide, never run `test_all` — use the targeted `test_*(example)` per stage.

## Stage 1 — Domain: the `ConversationThinking` content type

**Goal.** A content document that holds a thinking block's text + signature +
redaction state.

- Add `ConversationThinking` as a `@document struct` with the four fields above,
  plus a `selection::Reference`. Decide placement:
  - **Recommended:** in [program/src/document/Conversation.jl](../../program/src/document/Conversation.jl)
    (`ConversationModule`) — it is conversation-specific protocol state, and the
    module is already wired into the build, so no `Projectured.jl` registration
    churn. (Alternative: a tiny new `ThinkingModule` mirroring `EvaluatorModule`;
    only do this if a non-conversation consumer appears.)
  - Constructors: `ConversationThinking(text::AbstractString; signature="",
    redacted=false, data="")` wrapping the string in a `TextText`, and a
    `Document`-taking ctor. `show` like the other types.
- Convenience: `thinking_part(text; …) = ConversationPart(ConversationThinking(text; …))`
  and a `_thinking_text(t)` accessor (mirror `EvaluatorModule.result_text` /
  `_eval_*`).

**Deliverable / test.** Construct a `ConversationThinking`, wrap it in a part and
a turn, `show`/walk it. Extend `conversation_example` with a thinking part and
keep `test_printer(conversation_example)` green.

## Stage 2 — Streaming: capture thinking blocks

**Goal.** `_handle_sse_event!` materializes thinking blocks into parts as deltas
arrive, the same way it already does for text blocks.

In [program/src/editor/WorkbenchAssistant.jl](../../program/src/editor/WorkbenchAssistant.jl)
`_handle_sse_event!` ([WorkbenchAssistant.jl:484](../../program/src/editor/WorkbenchAssistant.jl#L484)):

- `content_block_start`: when `block_type == "thinking"`, push a
  `ConversationPart(ConversationThinking(""))` and stash it as
  `state[:current_thinking]` (parallel to the `:current_block` text path). When
  `block_type == "redacted_thinking"`, push a `ConversationThinking("";
  redacted=true, data=String(get(block_data, :data, "")))` and finalize
  immediately (no deltas follow).
- `content_block_delta`: add `dtype == "thinking_delta"` →
  `_append_thinking_delta!(state[:current_thinking], delta.thinking)` (rebuild
  the `text` `TextText` from accumulated content, mirroring
  `_append_text_delta!`); add `dtype == "signature_delta"` → set
  `current_thinking.content.signature` from `delta.signature`.
- `content_block_stop`: clear `state[:current_thinking]` (no markdown parse —
  thinking is plain prose, unlike the text block's `parse_markdown_blocks`).
- Add `:current_thinking => nothing` to the per-turn `state` dict in
  `_run_agent_loop!` ([WorkbenchAssistant.jl:432](../../program/src/editor/WorkbenchAssistant.jl#L432)).

Note the empty-thinking-prose-part guard: `_run_agent_loop!` drops an assistant
turn with no parts ([WorkbenchAssistant.jl:450](../../program/src/editor/WorkbenchAssistant.jl#L450)).
A turn that produced *only* thinking + a tool call still has its thinking part,
so it should **not** be dropped (we need it for the round-trip) — verify the
guard keys off "no parts" and a thinking part counts as a part.

**Deliverable / test.** Drive `_handle_sse_event!` with a synthetic thinking
sequence (block_start → thinking_delta×N → signature_delta → block_stop) and
assert the turn gains one `ConversationThinking` part with the right text and
signature. Use the Stage-3 `FakeLlm` extension to script it.

## Stage 3 — Request: enable thinking + FakeLlm synthesis

**Goal.** Send the `thinking` parameter and let `FakeLlm` emit thinking events
for deterministic tests.

- [program/src/editor/Anthropic.jl](../../program/src/editor/Anthropic.jl)
  `stream_message`: add a `thinking` keyword (default `nothing`); when set,
  `body["thinking"] = thinking` ([Anthropic.jl:46](../../program/src/editor/Anthropic.jl#L46)).
  Optionally an `output_config` keyword for `{"effort": …}`. Thread it through
  `AnthropicLlm.stream_turn` in [program/src/editor/Llm.jl](../../program/src/editor/Llm.jl).
- Decide where the value comes from: a field on `WorkbenchAssistant` (e.g.
  `thinking::Bool` or a config dict) read in `_run_agent_loop!`, defaulting to
  `{"type": "adaptive", "display": "summarized"}` for Opus models. **Do not**
  emit `budget_tokens` — it 400s on Opus 4.7/4.8.
- `FakeLlm` ([Llm.jl:94](../../program/src/editor/Llm.jl#L94)): add an optional
  `thinking::String` (default `""`); when non-empty, before the text block emit a
  `content_block_start{type:"thinking"}`, stream `thinking_delta`s, emit one
  `signature_delta{signature:"sig_fake"}`, then `content_block_stop`. Keeps the
  whole thinking path exercisable offline.

**Deliverable / test.** `test_cell`-style: run the agent loop with
`FakeLlm("Hello"; thinking="Let me reason…")` and assert the assistant turn has a
thinking part (text + `signature == "sig_fake"`) followed by the text part.
Confirm the request body carries `thinking` (inspect the dict `build_messages`
feeds, or a stubbed `stream_message`).

## Stage 4 — Serialization: round-trip thinking through `build_messages`

**Goal.** Re-emit thinking blocks back to the API in the correct shape and order,
so tool-use continuation doesn't break.

In `build_messages` / `_assistant_content`
([WorkbenchAssistant.jl:308](../../program/src/editor/WorkbenchAssistant.jl#L308),
[:382](../../program/src/editor/WorkbenchAssistant.jl#L382)):

- For a `ConversationThinking` content in an `:assistant` turn, emit a block:
  - normal: `{"type": "thinking", "thinking": text, "signature": signature}`.
  - redacted: `{"type": "redacted_thinking", "data": data}`.
- **Ordering:** thinking blocks must come **first** in the assistant message's
  `content` array, before any text or `tool_use` block. In `_assistant_content`,
  collect thinking blocks and prepend them; ensure the lookahead that appends
  `tool_use` blocks ([:351](../../program/src/editor/WorkbenchAssistant.jl#L351))
  keeps them after thinking.
- The standalone eval-turn branch ([:329](../../program/src/editor/WorkbenchAssistant.jl#L329))
  emits a bare `tool_use`; if a thinking-only assistant turn precedes a separate
  eval turn (the 1:1 message→turn mapping from redesign Stage 1), make sure the
  thinking turn's blocks land on the assistant message that carries the
  `tool_use`, not a separate message — the API pairs signature↔tool_use within
  one assistant message. This is the trickiest interaction; cover it with a test.
- `:user` turns never contain thinking — skip/ignore defensively.
- Only echo thinking for the **same model**; if the assistant `model` differs
  from the one that produced the thinking, other models drop the blocks
  (harmless, unbilled). v1 assumes a stable model per conversation, so no
  per-block model tracking needed — note as a limitation.

**Deliverable / test.** `build_messages` over a turn = `[thinking, text,
tool_use(EvaluatorForm)]` → assert the assistant message content is
`[thinking, text, tool_use]` in that order, `thinking` carries its `signature`,
and the following user message carries the `tool_result`. Add a redacted-block
case.

## Stage 5 — Presentation: render thinking parts (collapsed by default)

**Goal.** Thinking shows as a distinct, de-emphasized, collapsed-by-default part
in the widget projection.

In [program/src/projection/primitive/ConversationToWidget.jl](../../program/src/projection/primitive/ConversationToWidget.jl):

- `_kind_glyph` / `_kind_label` ([:63](../../program/src/projection/primitive/ConversationToWidget.jl#L63)):
  add `ConversationThinking` → glyph (e.g. `"🧠"`/`"…"`/`"∴"`) + label `"thinking"`.
- `ConversationPartToWidget` ([:127](../../program/src/projection/primitive/ConversationToWidget.jl#L127)):
  a thinking part's body is its `content.text` (`TextText`), recursed like any
  other text content. No special body shape needed (unlike `EvaluatorForm`'s
  code-over-result).
- **Collapsed by default:** thinking is verbose and secondary. Default a
  thinking part's domain `collapsed` to `true` when the part is created in
  Stage 2 (`ConversationPart(content; collapsed = content isa
  ConversationThinking)` or set it explicitly in the streaming handler). The
  existing `_maybe_clip` viewport-clip collapse + header-click toggle from
  redesign Stage 2 then work unchanged.
- Empty thinking text (when `display == "omitted"`): render a placeholder/elided
  body rather than an empty card; or skip creating the part when both text and
  data are empty. Decide during implementation.

**Deliverable / test.** Add a thinking part to `conversation_widget_example`;
printer walk 0 errors; collapsed thinking clips to one row; header click yields
`ToggleCollapseOperation` on the thinking part's domain node;
`write_image_example` snapshot.

## Stage 6 — Integrate into the live WorkbenchAssistant panel

**Goal.** Real Claude turns stream thinking into the live panel.

- Set the assistant's thinking config (Stage 3) on the real `AnthropicLlm` path;
  confirm `display: "summarized"` so thinking text is non-empty.
- Verify the streamed thinking part renders collapsed in the panel and that a
  follow-up tool-use turn round-trips (Stage 4) without an API error.
- Update existing assistant tests for the new part kind; the
  `test_assistant_mvp` typing scenes should be unaffected (thinking is
  assistant-only).

**Deliverable / test.** Assistant example end-to-end with `FakeLlm` thinking;
existing `test_*(assistant_example)` updated and green. A real-key smoke test is
manual (network), not in the suite.

---

## Sequencing notes

- **Stages 1–2 are the gate.** 3 (request + FakeLlm) unlocks deterministic
  tests for 2 and 4. 5 (presentation) can proceed in parallel after 1. 6 needs
  2–5.
- **The round-trip (Stage 4) is the only part that can break real API calls** —
  thinking-block ordering and signature preservation across a tool-use turn.
  Test it hard; everything else is additive and low-risk.
- Keep `conversation_example` / `conversation_widget_example` updated and green
  per stage. Use targeted `test_*` functions; never `test_all`.

## Open decisions (resolve as stages start)

- **Where `ConversationThinking` lives** — `ConversationModule` (recommended, no
  build wiring) vs. a new `ThinkingModule` (only if reused outside conversations).
- **Thinking config source** — a `WorkbenchAssistant` field vs. a constant
  default; and whether to expose `effort` in the UI.
- **Empty-thinking parts** (`display: "omitted"`) — render elided vs. skip
  creating the part.
- **Cross-model thinking** — v1 assumes one model per conversation and echoes
  thinking unconditionally; per-block model tracking deferred.
- **Collapse default** — thinking collapsed-by-default (recommended) vs.
  expanded; both reuse the existing per-part `collapsed`.
