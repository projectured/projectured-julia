# WorkbenchAssistant MVP: type-in + stubbed reply + reactive chat view

## Goal

The smallest possible end-to-end loop in the assistant panel:

1. user types `Hello` into the input
2. user presses **Enter**
3. user message `Hello` appears in the chat above
4. assistant message `Yes, sir!` appears under it
5. user types `What?` + **Enter**
6. another `Yes, sir!` appears

No network. No SSE. No agent loop. Just typing → submit → fixed reply. Once this round-trip is solid, swapping in the real Claude streaming is a localised change inside `evaluate_operation(::SubmitProseOperation, …)`.

## Current state (after [workbench-assistant.md](workbench-assistant.md))

`WorkbenchAssistant` already exists with the full set of fields ([program/src/document/Workbench.jl:255-302](../program/src/document/Workbench.jl#L255-L302)):

```julia
@document struct WorkbenchAssistant <: WorkbenchDocument
    conversation::ConversationConversation
    input::TextText           # ← will become PrimitiveString
    model::String
    system::String
    api_key::String
    status::Symbol
    selection::Reference
end
```

`SubmitProseOperation` exists and runs an `@async` agent loop against Anthropic ([program/src/editor/WorkbenchAssistant.jl:113-138](../program/src/editor/WorkbenchAssistant.jl#L113-L138)). For the MVP we will keep the operation but replace its body with the canned reply.

`ConversationToWidget` projects every conversation type to a widget tree, but it does so **eagerly** at `projection_print` time — a single static `WidgetComposite` is built and stored. The reactive cell graph propagates *value* changes (e.g. a `TextString.content` rewrite) but **not structural ones** (adding/removing messages). Making the chat scroll-back update is the load-bearing problem of this MVP — it is addressed in step 4.

## Plan overview

| # | Change | File(s) |
|---|---|---|
| 1 | `WorkbenchAssistant.input` becomes a `PrimitiveString` so typing/backspace work via the existing `PrimitiveStringToSyntaxLeaf` reader. | [Workbench.jl](../program/src/document/Workbench.jl) |
| 2 | Stub `SubmitProseOperation` to append `Hello`-then-`Yes, sir!`, synchronous, no `@async`. | [WorkbenchAssistant.jl](../program/src/editor/WorkbenchAssistant.jl) |
| 3 | Make the input projection chain reach `PrimitiveString` so it renders + accepts keys. | [Workbench.jl example](../example/src/projection/Workbench.jl) |
| 4 | Make `ConversationToWidget` use a **reactive `CellVector`-with-thunk** so appended messages show up without re-running `projection_print`. | [ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl) |
| 5 | Same thunk treatment for `ConversationAssistantMessage.blocks` so streaming (later) and the v1 canned reply both light up. | [ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl) |
| 6 | Pre-seed the initial selection so the assistant input has focus on startup (so typing goes there immediately). | [Workbench.jl example](../example/src/document/Workbench.jl) or a small `make_assistant_example`. |
| 7 | Adjust `build_messages` and `SubmitJuliaOperation` for the input type change. | [WorkbenchAssistant.jl](../program/src/editor/WorkbenchAssistant.jl) |

The order matters: 1 → 3 → 4 → 5 → 2 → 6 → 7. Steps 4 and 5 are the only ones that aren't a mechanical rewrite.

## Detailed steps

### 1. Switch `input` from `TextText` to `PrimitiveString`

Edit [program/src/document/Workbench.jl](../program/src/document/Workbench.jl):

```julia
import ..PrimitiveModule: PrimitiveString

@document struct WorkbenchAssistant <: WorkbenchDocument
    conversation::ConversationConversation
    input::PrimitiveString             # changed
    …
end

function WorkbenchAssistant(; conversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              …)
    WorkbenchAssistant(Cell(conversation), Cell(input), …)
end
```

This gives the input field two benefits for free, courtesy of `PrimitiveStringToSyntaxLeaf` ([program/src/projection/primitive/PrimitiveToSyntax.jl:163-198](../program/src/projection/primitive/PrimitiveToSyntax.jl#L163-L198)):

- `KeyPress` (any printable character) → `StringReplaceRangeOperation` that inserts at the cursor.
- `KeyDown` with `:backspace` / `:delete` → `StringReplaceRangeOperation` that deletes.

Both update `input.selection` to a zero-width cursor at the new position, so subsequent keys land in the right place.

### 2. Stub the assistant response

Edit `evaluate_operation(::SubmitProseOperation, _)` in [program/src/editor/WorkbenchAssistant.jl](../program/src/editor/WorkbenchAssistant.jl):

```julia
function evaluate_operation(op::SubmitProseOperation, _document)
    a = op.assistant
    text = something(a.input.value, "")
    isempty(strip(text)) && return nothing

    push!(a.conversation, ConversationUserMessage(text))
    a.input.value = ""                                  # clear input
    a.input.selection = ConcreteReferencePath(           # cursor back to 0
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))

    # ── stubbed reply (delete this block when wiring Claude back in) ──
    reply = ConversationAssistantMessage(stop_reason = :end_turn)
    push!(reply.blocks, Cell(ConversationTextBlock("Yes, sir!")))
    push!(a.conversation, reply)
    # ────────────────────────────────────────────────────────────────

    a.status = :idle
    nothing
end
```

Leave the existing `_run_agent_loop!`, `_handle_sse_event!`, `parse_markdown_blocks`, etc. untouched — they're dead in MVP but needed by the real wiring. Just don't call them.

`SubmitJuliaOperation` reads from `a.input` the same way; only the `_text_to_string` helper needs to change (step 7).

### 3. Add `PrimitiveDocument` to the workbench projection chain

The example projection at [example/src/projection/Workbench.jl](../example/src/projection/Workbench.jl) builds a combined `WidgetToGraphics` over a `TypeDispatchingProjection`. It currently knows about `TextDocument`, `JsonDocument`, `JuliaDocument`, … but not `PrimitiveDocument`. Add:

```julia
Pair{DataType,Any}[
    …,
    PrimitiveDocument => SequentialProjection(
        RecursiveProjection(PrimitiveToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    ),
]
```

This makes `WorkbenchAssistant.input` (a `PrimitiveString`) project as a quoted, editable string. If unquoted, monospace plain text is preferable visually, drop the quote/value distinction by passing `string_kw = (; quote_color = …)` — non-blocking, can be tuned later.

### 4. Make the conversation widget list reactive

This is the meat of the MVP. Today, [ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl):103-118 produces a static composite:

```julia
widgets = Any[]
for i in eachindex(c.messages)
    iomap = _recurse(recursion, c.messages[i], …)
    push!(widgets, iomap.output)
end
composite = WidgetComposite(Point2D(0, 0),
                            Any[_wrap_widget(e) for e in widgets];
                            padding=_PAD5)
```

If we now `push!(c.messages, msg)`, the cells that change are inside `c.messages`, but the `WidgetComposite` has already captured a fixed `Vector`. The renderer reads `composite.elements`, sees the same two-or-three items, and never re-projects the new message.

The fix is the same pattern `TextText(f::Function)` uses ([program/src/document/Text.jl:228](../program/src/document/Text.jl#L228)): build the widget's `elements` `CellVector` with a thunk, so reading it re-projects the current `c.messages`.

```julia
function projection_print(::ConversationConversationToWidgetComposite,
                          c::ConversationConversation, recursion, reference)
    # capture once
    rec = recursion
    ref = reference

    # thunk: read c.messages on demand; for each message, run projection_print
    # and return its output widget.
    elements_cv = CellVector(() -> begin
        msgs = c.messages          # reads the messages CellVector cell
        ws = Any[]
        for i in eachindex(msgs)
            child_ref = append_reference(ref, FieldReference("messages"),
                                              ElementReference(i))
            iomap = _recurse(rec, msgs[i], child_ref)
            push!(ws, _wrap_widget(iomap.output))
        end
        ws
    end)

    composite = WidgetComposite(Cell(Point2D(0, 0)),
                                elements_cv,
                                Cell(true), Cell(inset_default), Cell(nothing),
                                Cell(inset_default), Cell(nothing),
                                Cell(_PAD5),         Cell(nothing),
                                Cell(nothing))
    # We no longer have per-message iomaps stored — `map_reference_forward`
    # is already a no-op in v1, and the reader chain re-runs the thunk every
    # frame, so this is acceptable.
    SimpleIoMap(nothing, c, composite)
end
```

Two consequences worth flagging:

- **Re-projection cost.** Every read of `composite.elements` rebuilds the full message list. For < 50 messages this is fine; for thousands it isn't. Out of scope for MVP, but a follow-up could memoise per-element by the message's identity cell.
- **IoMap children.** `ChildrenIoMap` previously held per-message `iomap`s for reference forwarding. Since v1 returns `nothing` from every `map_reference_*` on conversation projections anyway, dropping the stored iomaps loses nothing today; if/when we wire real forward mapping, this thunk needs to publish its iomaps through a separate `Cell{Vector}`.

### 5. Same thunk treatment for assistant message blocks

`ConversationAssistantMessageToWidgetComposite` ([ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl):133-152) has the same shape problem: the canned reply pushes a block into `assistant_msg.blocks`, but the `WidgetComposite` capturing `block_widgets` is static.

Apply the same thunk pattern:

```julia
elements_cv = CellVector(() -> begin
    ws = Any[_label("assistant")]
    for i in eachindex(m.blocks)
        iomap = _recurse(rec, m.blocks[i],
                         append_reference(ref, FieldReference("blocks"),
                                               ElementReference(i)))
        push!(ws, _wrap_widget(iomap.output))
    end
    ws
end)
```

For the MVP the only block type ever appended is `ConversationTextBlock`, so this exercise is mostly about getting the pattern right for streaming later.

`ConversationListBlockToWidgetComposite` has the same shape but its `items` are normally set once when markdown is parsed, so deferring its thunkification is fine.

### 6. Pre-seed selection so the input is focused on startup

In `make_workbench_document_example` ([example/src/document/Workbench.jl](../example/src/document/Workbench.jl)) the assistant is constructed bare:

```julia
WorkbenchAssistant(),
```

Replace with an explicit construction that places the cursor inside the input:

```julia
assistant = WorkbenchAssistant()
assistant.input.selection = ConcreteReferencePath(
    FieldReference("value"),
    ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
```

The mouse-click → selection chain in `TextToGraphics` already sets the selection deeper than this, so once any text is rendered, clicking on the input will keep focus there. We only need the *first* keypress to land — hence the explicit zero-width cursor.

(Once selection forwarding through `ConversationToWidget`/`WorkbenchAssistantToWidgetScrollPane` is wired, this pre-seed can be on the assistant or workbench root.)

### 7. Adjust `_text_to_string` and `build_messages` for the type change

`evaluate_operation(::SubmitJuliaOperation, _)` reads `_text_to_string(a.input)`. After step 1 `a.input` is a `PrimitiveString`, so the helper becomes a one-liner:

```julia
_text_to_string(s::PrimitiveString) = something(s.value, "")
```

(Keep the old `TextText` overload too — `ConversationToolResultMessage.content` etc. still use `TextText` and `_text_to_string` is used in `build_messages` for those.)

`_set_input!` simplifies in the same way:

```julia
function _set_input!(a::WorkbenchAssistant, s::AbstractString)
    a.input.value = String(s)
    a.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(length(s), length(s)),
                              EmptyReferencePath()))
end
```

## Verification

After implementing steps 1-7, the MVP is exercised by:

```julia
using Projectured, ProjecturedExample
editor = make_assistant_demo_editor()       # tiny helper that builds an
                                            # Editor over a workbench with
                                            # one assistant panel, focus
                                            # pre-seeded.
run!(editor)
# type "Hello" + Enter   → see "Hello" above, then "Yes, sir!" below
# type "What?" + Enter   → see "What?" above, then another "Yes, sir!"
```

### Headless test using the printer/reader (no SDL)

Most of this MVP can — and should — be tested without launching the SDL window. The same primitives the editor's read-eval-print loop uses (`projection_print`, `projection_read`, `evaluate_operation`) are public; driving them by hand reproduces the loop one frame at a time. This is the pattern documented in [guide/debugging.md](../guide/debugging.md#driving-the-printerreader-manually) and used by every `walk_repl_loop` test in [test/src/editor/ReplTest.jl](../test/src/editor/ReplTest.jl).

Below is a single self-contained Julia script that, when the MVP is finished, exercises the four scenes the user described and asserts every state transition. It uses **only** the printer/reader/operation API — no rendering, no SDL.

```julia
using Projectured
using Projectured: KeyPress, KeyDown, Modifiers
using Projectured: ConcreteReferencePath, FieldReference, RangeReference,
                   EmptyReferencePath

# 1. Build a minimal projection chain that covers the assistant's input
#    (PrimitiveString) and the conversation tree, but skips graphics —
#    we stop one step before TextToGraphics, since we only need the
#    reader chain to dispatch KeyPress/KeyDown into operations.
function make_assistant_test_setup()
    a = WorkbenchAssistant()
    # Pre-seed focus on the input so the first KeyPress lands there.
    a.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))

    # The actual workbench projection wraps WorkbenchToWidget + WidgetToGraphics
    # via a TypeDispatchingProjection. For headless testing we want exactly
    # the projections whose `projection_read` translates raw KeyPress/KeyDown
    # into domain operations. That happens in:
    #   PrimitiveStringToSyntaxLeaf  (text editing)
    #   TextToGraphics               (cursor movement keys)
    #   WorkbenchAssistantToWidgetScrollPane  (Enter -> SubmitProseOperation)
    #
    # The simplest stack that exercises all three is the real editor stack,
    # built with a dummy measurer so we don't need SDL fonts:
    measure = (text, font) -> (length(text) * 10, 20)
    projection = make_assistant_demo_projection(measure)   # tiny test helper

    (assistant = a, projection = projection)
end

# Helper that turns a string into a stream of KeyPress events
type_text(s::AbstractString) = [KeyPress(c) for c in s]

# One "frame" of the editor loop, driven by hand
function step!(assistant, projection, event)
    iomap = projection_print(projection, assistant)
    op = projection_read(projection, iomap, event)
    op === nothing && return nothing
    evaluate_operation(op, assistant)
    op
end

# ── Scene 1: user types "Hello"
setup = make_assistant_test_setup()
for ev in type_text("Hello")
    step!(setup.assistant, setup.projection, ev)
end
@assert setup.assistant.input.value == "Hello"
@assert length(setup.assistant.conversation) == 0     # no submit yet

# ── Scene 2: user hits Enter
step!(setup.assistant, setup.projection,
      KeyDown(:return, Modifiers()))
@assert length(setup.assistant.conversation) == 2
let user = setup.assistant.conversation.messages[1],
    reply = setup.assistant.conversation.messages[2]
    @assert user isa ConversationUserMessage
    @assert _text_to_string(user.text) == "Hello"   # _text_to_string overload
                                                    # over PrimitiveString is
                                                    # already added in step 7;
                                                    # for ConversationUserMessage
                                                    # the text is a TextText built
                                                    # from the prompt string, so the
                                                    # original TextText overload
                                                    # still applies.
    @assert reply isa ConversationAssistantMessage
    @assert length(reply.blocks) == 1
    @assert _text_to_string(reply.blocks[1].text) == "Yes, sir!"
end
@assert setup.assistant.input.value == ""           # input cleared

# ── Scene 3: user types "What?" + Enter
for ev in type_text("What?")
    step!(setup.assistant, setup.projection, ev)
end
@assert setup.assistant.input.value == "What?"
step!(setup.assistant, setup.projection,
      KeyDown(:return, Modifiers()))
@assert length(setup.assistant.conversation) == 4
@assert _text_to_string(setup.assistant.conversation.messages[3].text) == "What?"
@assert _text_to_string(setup.assistant.conversation.messages[4].blocks[1].text) == "Yes, sir!"

println("MVP scenes passed.")
```

The above passes if and only if:

1. **PrimitiveString input wiring (step 1)** works — `KeyPress` events translate into `StringReplaceRangeOperation`s that mutate `assistant.input.value`. Test by running just the `type_text("Hello")` loop and inspecting `assistant.input.value`.
2. **Enter dispatch (existing)** produces `SubmitProseOperation`. Already covered by the existing assertion in `WorkbenchAssistantModule.projection_read(::WorkbenchAssistantToWidgetScrollPane, …, ::KeyDown)`.
3. **The stubbed `SubmitProseOperation` (step 2)** appends both the user message and the canned reply, and clears the input.

The reactive-thunk work (steps 4-5) **is not exercised by this headless test** — it only matters for the renderer. To still get coverage for "the projection tree sees the new messages", add this check after Scene 2:

```julia
# Force re-projection and confirm the widget composite has grown to match
iomap2 = projection_print(setup.projection, setup.assistant)
# Walk down to the conversation composite. The assistant projects to a
# WidgetScrollPane wrapping a vertical WidgetComposite[conv, input]; conv
# is itself a WidgetComposite of message widgets.
scroll = iomap2.output                          # WidgetScrollPane
column = scroll.content                         # WidgetComposite[conv, input]
conv_widget = column.elements[1]                # WidgetComposite of messages
@assert length(conv_widget.elements) == 2       # user + assistant
```

If step 4's thunk reads `c.messages` correctly, you can additionally verify the **live** update path (no re-print) by:

```julia
iomap = projection_print(setup.projection, setup.assistant)
column = iomap.output.content
conv_widget = column.elements[1]
n_before = length(conv_widget.elements)

push!(setup.assistant.conversation, ConversationUserMessage("late addition"))

# No second projection_print! If the thunk is wired correctly, reading
# conv_widget.elements re-runs the thunk and picks up the new message.
@assert length(conv_widget.elements) == n_before + 1
```

This is the load-bearing assertion for step 4 — the rest of the scaffolding above will pass even if the renderer never refreshes, because the *document* mutation always happens correctly. **Add this assertion to the test before considering step 4 done.**

### Where to put the test

Two natural homes:

- **A REPL scratch script** (e.g. `test/scratch/assistant_mvp.jl`) — fastest feedback while implementing, no `Test` framework needed.
- **A proper `@testset` in [test/src/editor/](../test/src/editor/)** — once the MVP is stable, wrap the script above in `test_assistant_mvp()` following the [walk_repl_loop](../test/src/editor/ReplTest.jl#L14) pattern: use `@testset "Assistant MVP"`, replace `@assert` with `@test`, and call from `test_all()`.

### Hooks to write while implementing

The script above references two helpers that don't exist yet but are small enough to inline if you don't want to add them:

- `make_assistant_demo_projection(measure)` — the same `SequentialProjection(RecursiveProjection(WorkbenchToWidget()), combined_w2g)` chain used by the SDL editor, but with `combined_w2g` extended for `PrimitiveDocument` (step 3) and using the test `measure` instead of `sdl_measure_text`. Three lines in the example package.
- `_text_to_string(::PrimitiveString)` — already added in step 7.

If you skip these helpers, the test can drive the projection chain inline:

```julia
measure = (text, font) -> (length(text) * 10, 20)
projection = SequentialProjection(
    RecursiveProjection(WorkbenchToWidget()),
    RecursiveProjection(TypeDispatchingProjection(
        PrimitiveDocument => SequentialProjection(
            RecursiveProjection(PrimitiveToSyntax()),
            RecursiveProjection(SyntaxToText()),
            TextToGraphics(measure=measure)),
        # … other dispatch entries as needed for whatever child types appear
    ))
)
```

The minimal set of dispatch entries the MVP needs is `PrimitiveDocument` (for the input) and whatever message-body types the canned reply uses (`ConversationTextBlock`'s body is a `TextText`, so `TextDocument => TextToGraphics(measure=measure)`). Other domains can be left out — the conversation tree only contains those two leaf types in MVP scope.

### What this catches vs. what it doesn't

| Catches | Doesn't catch |
|---|---|
| Input typing → string mutation | Font-metric layout problems |
| Enter dispatch → operation produced | Pixel-level placement |
| Operation produces the right messages | Mouse click → selection (use `explore_selections` for that) |
| The conversation thunk reads its source cells | Color/styling issues |
| `_text_to_string` overload coverage | Visual jitter during streaming (no streaming in MVP) |

That's the right boundary for an MVP test — everything correctness-critical, nothing graphics-stack-dependent. The SDL run is then a single smoke check before declaring victory.

## What stays in for the real Claude wiring

- `_run_agent_loop!`, `_handle_sse_event!`, `parse_markdown_blocks`, `assistant_tool_schemas`, `dispatch_assistant_tool` — all still needed.
- The `@async` task design and the `status :streaming → :idle` cell flip — needed once streaming is on.
- Once swapping back, step 2's stub is replaced by a call to `_run_agent_loop!(a)` (kept `@async` to avoid blocking the editor loop) and step 5's thunk is what makes the streaming deltas show up.

## Out of scope (intentional follow-ups)

- Real bidirectional selection mapping through `ConversationToWidget` (today every `map_reference_*` returns `nothing`).
- Memoising the per-message reprojection inside the conversation thunk.
- Markdown rendering inside `Yes, sir!` (no markdown blocks for the canned reply; the real streaming path uses `parse_markdown_blocks`).
- Esc-to-cancel during streaming (only relevant once `_run_agent_loop!` is back).
