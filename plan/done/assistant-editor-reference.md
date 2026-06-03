# Thread the live `Editor` to the WorkbenchAssistant's tool dispatch

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> **Status: done — option 2 chosen and shipped.** `evaluate_operation`'s
> signature was flipped to `(editor, operation)` with the first arg untyped, so
> tests can pass a `(document=doc,)` NamedTuple where production passes the live
> `EditorModule.Editor`. `EditorModule.evaluate!` now calls
> `evaluate_operation(editor, editor.operation)`; the two `nothing` call sites
> in `WorkbenchAssistant.jl` (`SubmitJuliaOperation`'s `call_tool` and
> `_run_agent_loop!`'s `dispatch_assistant_tool`) now forward the editor through
> to `execute_julia_code`'s `let editor = …`. `_run_agent_loop!` gained an
> `editor` first arg. Regression test `test_workbench_editor_reference` in
> [test/src/editor/McpTest.jl](../../test/src/editor/McpTest.jl) drives the full
> `SubmitJuliaOperation` path with a stand-in editor and asserts both
> `editor !== nothing` and `editor.document isa WorkbenchAssistant` execute as
> true inside the assistant's `let editor = …`. Full suite: 616 / 616 pass.

## The problem

When the WorkbenchAssistant invokes `execute_julia_code` — whether triggered by
the user via `SubmitJuliaOperation` or by Claude via a tool-use turn inside
`_run_agent_loop!` — the running `Editor` instance is **not** passed through.
Both call sites currently hard-code `nothing`:

- [program/src/editor/WorkbenchAssistant.jl:152](../../program/src/editor/WorkbenchAssistant.jl#L152)
  `call_tool("execute_julia_code", Dict("code" => code), nothing)`
- [program/src/editor/WorkbenchAssistant.jl:470](../../program/src/editor/WorkbenchAssistant.jl#L470)
  `dispatch_assistant_tool(tu.name, tu.input, nothing)`

So when the assistant writes `editor.selection`, the executed code sees
`editor === nothing` and raises `FieldError: type Nothing has no field 'selection'`.
A regression test added in [test/src/editor/McpTest.jl](../../test/src/editor/McpTest.jl)
documents the current behaviour.

The desired behaviour: inside `execute_julia_code`, `editor` is bound to the
live `EditorModule.Editor` so the assistant can read and mutate runtime state
(`editor.document`, `editor.projection`, `editor.iomap`, …).

## Why the editor isn't reachable today

- `Editor` lives only in `EditorModule.run!`'s local scope.
- `evaluate_operation(op, document)` only carries the document.
- `_run_agent_loop!(a)` only has the assistant; it's spawned on an `@async`
  task by `SubmitProseOperation`, so even closing over a value at the call site
  would require the call site to have it.
- The `WorkbenchAssistant` document is loaded *before* `Editor.jl`
  (see [program/src/Projectured.jl:126-129](../../program/src/Projectured.jl#L126-L129)),
  so it cannot reference the `Editor` type at compile time.

Bridges available:

| Mechanism | Sketch |
|-----------|--------|
| Module-level Ref | Mutable global in some module loaded first |
| Task-local storage | `task_local_storage(:projectured_editor, editor)` |
| Method dispatch | New `evaluate_operation(op, ::Editor)` or `::Context` arg |
| Document field | `WorkbenchAssistant.editor::Any`, populated on attach |
| Tool-handler closure | Re-register `execute_julia_code` with editor closed in |
| Restructure | Editor frame loop owns assistant dispatch; pass as arg |

## Option 1 — Ambient `Ref` in `ToolRegistryModule`

`ToolRegistryModule` already mediates tool dispatch and loads first, so it can
host a process-global `Ref{Any}(nothing)` plus accessors.

```julia
const _CURRENT_EDITOR = Ref{Any}(nothing)
current_editor() = _CURRENT_EDITOR[]
function with_current_editor!(f, editor)
    prev = _CURRENT_EDITOR[]
    _CURRENT_EDITOR[] = editor
    try; f() finally _CURRENT_EDITOR[] = prev end
end
```

- `EditorModule.run!(editor)` wraps the read-eval-print loop with `with_current_editor!(editor) do … end`.
- `WorkbenchAssistant.jl` replaces both `nothing`s with `current_editor()`.

**Pros**
- Smallest patch (~15 lines).
- Zero changes to operation/document interfaces.
- No changes to existing call sites outside the two `nothing`s.

**Cons**
- Hidden global state. Looking at `WorkbenchAssistant.jl` you can't tell where
  `editor` comes from.
- Single-editor process model baked in (fine today; awkward if multi-editor or
  multi-window with independent editors ever happens).
- Tests that exercise the agent loop without an `Editor` (e.g. `AssistantMvpTest`
  calls `_run_agent_loop!(a)` directly) still see `nothing` unless they manually
  set up `with_current_editor!`.

## Option 2 — Thread `Editor` through `evaluate_operation`

Define a default fallback so existing methods keep working:

```julia
evaluate_operation(op, editor::Editor) = evaluate_operation(op, editor.document)
```

Change `EditorModule.evaluate!` to pass `editor` instead of `editor.document`.
Add specific overrides for the two assistant ops that pull the editor out and
forward it to the tool dispatch. `_run_agent_loop!(a, editor)` grows an extra
arg.

**Pros**
- Dispatch is honest: "operation needs editor → method on `::Editor`".
- No globals.
- The fallback shields every other operation method from change.

**Cons**
- `AssistantMvpTest.jl` calls `evaluate_operation(op, a)` directly with the
  bare `WorkbenchAssistant`. That hits the document fallback, not the new
  `::Editor` method, so the test path doesn't exercise the editor wiring.
  Either:
  (a) the test wraps `a` in a stub editor before evaluating, or
  (b) `_run_agent_loop!` accepts a `Union{Editor,Nothing}` editor and
       degrades gracefully when `nothing` (preserves current test behaviour
       but loses some type safety).
- Tiny invasive — touches `EditorModule.evaluate!` and the operation method
  table.

## Option 3 — `editor::Any` field on `WorkbenchAssistant` *(rejected)*

Add the field to the `@document struct WorkbenchAssistant`; attach the editor
at `run!` time via a walker.

Rejected because:
- `@document` wraps every field in a `Cell`. The editor would be reactive,
  which is a footgun — touching `assistant.editor` inside a printer would
  register a reactive dependency on an "constant" runtime ref.
- Cycle: `assistant.editor → editor.document → … → assistant`. `Base.show`,
  the auto-generated `IWorkbenchAssistant` snapshot, equality, and hashing all
  need to be cycle-aware.
- Construction-order pivot: the assistant is built *before* the editor. Need a
  separate `attach_editor!(doc, editor)` walker that finds every nested
  WorkbenchAssistant and fills the field.
- Type can only be `Any` (forward-ref).
- Inverts the document/editor layering described in
  [guide/architecture.md](../../guide/architecture.md): pure-data document
  holds a back-pointer to its runtime host.

## Option 4 — Late-bind the tool handler at editor startup

`register_default_tools_and_resources!()` registers `execute_julia_code` with
handler `(editor, args) -> execute_julia_code(editor, args["code"])`. At
`EditorModule.run!` startup, **replace** that registration with a closure that
has the live editor baked in:

```julia
register_tool!(Tool("execute_julia_code", ...,
    (_, args) -> execute_julia_code(this_editor, args["code"])))
```

`call_tool("execute_julia_code", args, nothing)` then ignores the second arg.
This mirrors what `mcp_tools(editor, ...)` already does for the MCP transport
(see [ToolRegistry.jl:195-221](../../program/src/editor/ToolRegistry.jl#L195-L221)).

**Pros**
- Local to the editor's startup path.
- No globals exposed to callers; ambient state hides inside the registry.
- Symmetric with the MCP server's existing editor-binding mechanism.
- The assistant's tool-dispatch sites need no change at all.

**Cons**
- Still ambient: `register_tool!` mutates a shared registry as a side effect of
  `run!`.
- Two simultaneous editors (or nested editor runs) clobber each other's
  registration.
- Restoring the original (`editor`-parameter) registration on shutdown is
  required to keep tests reproducible.
- Tests that call `register_default_tools_and_resources!` after a `run!` cycle
  will overwrite the bound handler — sequence matters.

## Option 5 — Task-local storage

Same shape as option 1 but stored in `task_local_storage(:projectured_editor, …)`,
scoped through `task_local_storage()`'s `do…end` form. `@async` tasks spawned
inside the scope inherit the parent's storage, so the agent loop sees the
editor.

**Pros**
- No module-level mutable state.
- Scoped to the running task — nested editors don't conflict.
- Mostly invisible to other code.

**Cons**
- Still ambient — `editor` reaches the dispatch via a hidden channel.
- `task_local_storage` inheritance across `@async` is correct Julia semantics
  but a quirk people forget about; a future contributor refactoring the agent
  loop to use a thread pool would lose the editor silently.

## Option 6 — Pass a `Context` wrapper to `evaluate_operation`

Define `EditorContext{editor, document}`. `EditorModule.evaluate!` calls
`evaluate_operation(op, EditorContext(editor, editor.document))`. Generic
fallback: `evaluate_operation(op, ctx::EditorContext) = evaluate_operation(op, ctx.document)`
so existing methods continue to work. Assistant ops override the
`::EditorContext` method.

**Pros**
- Editor flows through the call graph explicitly. No globals.
- New type makes "this operation needs runtime context" visible at the type
  level.
- Extensible: clipboard, selection root, perf counters etc. could live in the
  same context later.

**Cons**
- Introduces a new public-ish type.
- `AssistantMvpTest` calls `evaluate_operation(op, a)` with the bare assistant
  — same hole as option 2. Tests need to construct an `EditorContext` to
  exercise the editor path.
- "Extensible" cuts both ways: `EditorContext` is the kind of type that grows
  fields whenever a new op needs runtime state, and turns into a god-object.

## Option 7 — Editor frame loop owns assistant dispatch

Demote `SubmitProseOperation` / `SubmitJuliaOperation` to *requests*: they
enqueue an entry on `assistant.pending_submits` and return. `EditorModule.run!`
checks the queue each frame; when it sees a request, it spawns the
`@async` agent task **from inside the editor scope**, closing the editor into
`_run_agent_loop!(a, editor)`.

**Pros**
- No ambient state, no new type, no document field.
- `editor` is just a normal function argument — flows through naturally.
- Architecturally honest: agent loops are a runtime concern of the editor, not
  a domain operation.

**Cons**
- Largest patch. Touches `EditorModule.run!`, both submit operations,
  `_run_agent_loop!`'s signature, and `AssistantMvpTest` (which calls
  `_run_agent_loop!` directly outside any frame loop).
- Adds a queue/poll discipline on `WorkbenchAssistant`.
- Loses the "operation as the unit of state mutation" symmetry —
  assistant turns become a different kind of thing.

## Recommendation matrix

| Criterion | Opt 1 (ref) | Opt 2 (dispatch) | Opt 4 (rebind) | Opt 5 (TLS) | Opt 6 (ctx) | Opt 7 (loop owns) |
|-----------|:-----------:|:----------------:|:--------------:|:-----------:|:-----------:|:-----------------:|
| Lines changed | XS | S | XS | XS | S | L |
| Hidden state | yes | no | yes | yes (task) | no | no |
| Survives multi-editor | no | yes | no | yes | yes | yes |
| Tests pass unchanged | yes-ish | requires stub | yes | yes-ish | requires stub | requires refactor |
| Layering clean | meh | yes | meh | meh | yes | yes |

## Test contract (independent of option)

Regardless of which option lands, the regression test should encode:

1. A non-`nothing` Editor (or stand-in) is in scope at the moment
   `execute_julia_code` runs from the workbench path.
2. The `editor` binding inside the executed code is *that* editor — not
   `nothing`, not a stale Dict.
3. The assistant example end-to-end: type "What's the editor's selection?",
   submit, no `FieldError` on `editor.selection` (the agent will need a
   document field that actually exists for the LLM to read, but the binding
   step is the regression test).

## Open questions

- Do we want one editor per process, or do we plan for multi-editor (multi-
  window with independent editors) one day? This is the main axis that
  separates options 1/4 from 2/5/6/7.
- Should the `editor` exposed to LLM-written code be the live `Editor` (with
  `editor.document` mutable through reactive cells) or a snapshot? Live is
  more useful but a buggy tool-call can corrupt state mid-frame.
- Is there a use case for the MCP server's external clients reaching `editor`
  through this same path? The MCP path already closes `editor` into the
  handler via `mcp_tools(editor, …)` — option 4 unifies the two paths.
