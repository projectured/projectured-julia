# Assistant collapse defaults + part-widget layout containment

> **Status: IMPLEMENTED (Stages 1–2); runtime test execution pending.** Two
> small, independent changes to the in-editor AI assistant rendering:
> 1. **Collapse-by-default for resource reads** (parallel to thinking, which is
>    already collapsed by default).
> 2. **Layout fix:** a collapsed/expanded part body must never draw outside its
>    own assistant message-part card.
>
> Code changes are in place (see per-stage **Done** notes). The targeted tests
> (`test_assistant_mvp()`, `test_printer(conversation_widget_example)`) were
> **not run in the implementation environment — it has no Julia toolchain and the
> network policy blocks installing one** (`install.julialang.org` → 403). They
> must be run in CI or a local checkout to confirm green; the changes are
> deliberately small and locally reviewed.

Builds on [conversation-thinking.md](../done/conversation-thinking.md) (Stage 5
established collapsed-by-default thinking and the `_maybe_clip` viewport-clip
collapse) and the turn/part redesign.

## Background — how collapse + clipping work today

- A `ConversationPart` carries a `collapsed::Bool`
  ([Conversation.jl:53](../../package/domain/src/document/Conversation.jl#L53)).
  Thinking parts default `collapsed = true` via `thinking_part`
  ([Conversation.jl:107](../../package/domain/src/document/Conversation.jl#L107)).
- `ConversationPartToWidget` / `ConversationTurnToWidgetComposite`
  ([ConversationToWidget.jl](../../package/domain/src/projection/primitive/ConversationToWidget.jl))
  render each part/turn as a `WidgetCard`. When `collapsed`, the body is wrapped
  by `_maybe_clip` in a `WidgetScrollPane` clipped to `_COLLAPSED_H = 30` px.
- Tool calls (incl. `read_resource` / `list_resources`) are appended in the
  agent loop as `EvaluatorForm` parts with **`collapsed = false`** (the
  `ConversationPart` default) — [WorkbenchAssistant.jl:657](../../package/domain/src/editor/WorkbenchAssistant.jl#L657).
  `eval_kind_label` already classifies `list_resources` / `read_resource` as
  `"resource"` ([Evaluator.jl:64](../../package/domain/src/document/Evaluator.jl#L64)).

### The layout bug (confirmed by reading the code)

`_maybe_clip` hardcodes the scroll-pane size to **`_CARD_WIDTH` (760)** for *both*
turn and part bodies
([ConversationToWidget.jl:88](../../package/domain/src/projection/primitive/ConversationToWidget.jl#L88)):

```julia
_maybe_clip(body, collapsed) =
    collapsed ? WidgetScrollPane(body; size = Point2D(_CARD_WIDTH, _COLLAPSED_H), …) : body
```

But a *part* card is `_PART_WIDTH = 720` wide. `WidgetScrollPane` prefers the
parent-allocated `available_width` and falls back to its own `size.x` only when
none was allocated ([WidgetToGraphics.jl:1928](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L1928)).
In the fallback case the collapsed pane reports a **760-wide** outer box, and the
enclosing `WidgetCard` sizes its width to `max_content_width + 2·padding`
([WidgetToGraphics.jl:2280](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2280)) — so a
collapsed part card balloons to ~760+ px, **40+ px past** the 720 it has when
expanded, and past its siblings. That is the "collapsed content goes out of the
part widget" symptom. (The card's own padding is `16`, set in the theme builder
at [WidgetToGraphics.jl:3560](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L3560).)

---

# Stages

Targeted tests only (per the repo testing guide — never `test_all`). The two
relevant examples are `conversation_widget_example` and `assistant_example`;
the assistant streaming path is covered by `test_assistant_mvp()`.

## Stage 1 — Collapse resource-read parts by default

**Goal.** A `read_resource` / `list_resources` tool-call part renders collapsed
by default, like thinking — it's lookup noise, secondary to the answer.

- In `_run_agent_loop!`
  ([WorkbenchAssistant.jl:657](../../package/domain/src/editor/WorkbenchAssistant.jl#L657)),
  pass `collapsed = _collapse_by_default(tu.name)` when building the tool-call
  `ConversationPart`.
- Add a small policy helper near the agent loop:
  ```julia
  # Resource reads (read_resource / list_resources) collapse by default —
  # lookup chatter, secondary to the answer; eval results stay expanded.
  _collapse_by_default(tool_name) = eval_kind_label(tool_name) == "resource"
  ```
  Reuse `eval_kind_label` (import it from `EvaluatorModule`, already a
  dependency). This keeps the resource/eval/tool classification single-sourced.
- **Open decision (resolve in implementation):** whether the doc *search* tools
  (`search_documentation`, `search_api`) should also collapse. They are reads
  too, but `eval_kind_label` labels them `"tool"`. Recommendation: keep Stage 1
  to the literal "resource" kind; widen the helper later if search noise is a
  problem. Note it, don't gold-plate.
- Thinking is already collapsed by default — no change there.

**Deliverable / test.** Extend `test_assistant_mvp()` (the tool-call scene, e.g.
`_mvp_test_*` around [AssistantMvpTest.jl:391](../../package/test/src/editor/AssistantMvpTest.jl#L391))
to drive a `read_resource` tool call and assert the produced part's `collapsed`
is `true`, while an `execute_julia_code` part stays `false`. `test_assistant_mvp()`
green.

**Done.** `_collapse_tool_default(tool_name) = eval_kind_label(tool_name) ==
"resource"` added before `_run_agent_loop!` in
[WorkbenchAssistant.jl](../../package/domain/src/editor/WorkbenchAssistant.jl)
(import of `eval_kind_label` added to the `EvaluatorModule` line); the tool-call
`ConversationPart` is now built with `collapsed = _collapse_tool_default(tu.name)`.
Thinking unchanged (already collapsed). Tests: a new `_mvp_test_resource_collapse()`
(drives a `read_resource` call, asserts `parts[1].collapsed == true`), registered
in `test_assistant_mvp()`, plus an added `collapsed == false` assertion on the
`execute_julia_code` part in `_mvp_test_tool_use_roundtrip()`. **Search tools left
expanded** (only the literal `"resource"` kind collapses) per the open decision.

## Stage 2 — Contain the collapsed body within its card

**Goal.** A collapsed part/turn body's clipped viewport is sized to its *own*
card's interior, so the card keeps its authored width and nothing overflows —
in both the live editor (available-width propagated) and isolated rendering
(fallback).

In [ConversationToWidget.jl](../../package/domain/src/projection/primitive/ConversationToWidget.jl):

- Add a `_CARD_PADDING = 16` constant mirroring the theme's `WidgetCard`
  padding (comment that the theme builder at
  [WidgetToGraphics.jl:3560](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L3560)
  is the source of truth).
- Parameterize the clip by the owning card's width and clip to the **interior**
  width (`width − 2·_CARD_PADDING`):
  ```julia
  _maybe_clip(body, collapsed, width) =
      collapsed ? WidgetScrollPane(body;
                      size = Point2D(width - 2*_CARD_PADDING, _COLLAPSED_H),
                      padding = inset_default) : body
  ```
- Turn body passes `_CARD_WIDTH`
  ([:122](../../package/domain/src/projection/primitive/ConversationToWidget.jl#L122));
  part body passes `_PART_WIDTH`
  ([:138](../../package/domain/src/projection/primitive/ConversationToWidget.jl#L138)).

Effect: in the live editor the scroll pane already fills the card's allocated
inner width (containment was only visually broken on the fallback path); this
fix makes the fallback width match the card interior so the collapsed card no
longer balloons past its authored width, and the part no longer uses the wrong
(turn) width.

**Deliverable / test.** `test_printer(conversation_widget_example)` green. Add an
assertion (walk the produced graphics for a collapsed part card) that the card's
width equals its expanded/authored width — i.e. the collapsed scroll pane did
not widen it. A `write_example_image` snapshot is a useful manual cross-check.

**Done (code).** `_maybe_clip` now takes the owning card's `width` and sizes the
collapsed `WidgetScrollPane` to the interior `width - 2*_CARD_PADDING` (new
`_CARD_PADDING = 16` constant mirroring the theme's `WidgetCard` padding). The
turn body passes `_CARD_WIDTH`, the part body passes `_PART_WIDTH` — fixing the
prior hardcoded `_CARD_WIDTH` that made a collapsed 720px part card balloon to
~760px on the fallback path. No domain-struct/serialization change.
**Verification still owed:** run `test_printer(conversation_widget_example)` and
add the width-equality graphics assertion in an environment with Julia.

## Stage 3 — Verify expanded bodies are also contained

**Goal.** Confirm the *expanded* case ("expanded content should not go out of
the part widget") and decide whether any further clamp is needed.

- When expanded, `_maybe_clip` returns the body unwrapped and the `WidgetCard`
  sizes to its content, so a part body is contained in its own card *by
  construction*. The thing to verify is that a wide body (long Julia/JSON line,
  unwrapped) doesn't push the **part** card wider than the **turn** card's
  interior.
- The card propagates `available_width` to its content
  ([WidgetToGraphics.jl:2304](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2304)),
  so wrappable text reflows; non-wrapping code is the only overflow risk.
- **Verification:** in the live panel (allocated width) check that the widest
  expanded part card ≤ the turn card interior. If code overflows, the minimal
  follow-up is to give *expanded* structured-code bodies a horizontal scroll
  pane (width-bound, height-free) — but only if observed; do not pre-emptively
  add it.

**Deliverable / test.** A printer walk of `conversation_widget_example` /
`assistant_example` under an allocated width asserting every part card's right
edge ≤ its turn card's content right edge. Document the result in the plan's
status note (this is the "verify this is the case" deliverable).

---

## Sequencing & risk

- Stages 1 and 2 are independent and individually green-able; do 1 then 2.
- Lowest-risk surface: Stage 1 touches one call site + one helper; Stage 2
  touches one helper + two call sites. No domain-struct or serialization changes,
  so the API round-trip (the fragile part of the thinking work) is untouched.
- Keep `conversation_widget_example` and `assistant_example` green per stage with
  targeted `test_printer(...)` / `test_assistant_mvp()`; never `test_all`.

## Open decisions

- **Search tools collapse?** Default no (Stage 1) — only the literal `"resource"`
  kind. Widen `_collapse_by_default` later if needed.
- **`_CARD_PADDING` duplication** — accept a documented constant mirroring the
  theme value (16); threading the real card padding through the projection
  context is out of scope for this fix.
- **Expanded wide-code clamp** — deferred to Stage 3's verification result.
