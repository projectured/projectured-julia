# An editor is made before its loop runs

**Status (2026-09-23): IMPLEMENTED** on the `selection-root` branches of
projectured-julia and omnet-julia. The owner approved the whole plan
("implement it"). Landing on `main` waits for the owner's approval.

**Goal:** a caller that must do work before the loop starts holds the editor,
does that work, and then runs the loop. The `on_start` hook goes. Start-up work
on the document then runs with an editor that has printed once, so the verbs
that read through the readers (`read_rooted_operation`) work there.

**Repositories:** projectured-julia, then omnet-julia.

## 1. The problem

`run_editor!(backend, projection, document; …)` and `run_window_editor(document,
projection, title; …)` do everything in one call: they start the backend, open
the windows, build the `Editor`, run the loop, and quit the backend at the end.
A caller gets the editor only inside `on_start(editor)`, which the loop calls
once, before its first frame.

Before the first frame, `editor.iomap` is `nothing`. A verb that reads its edit
through the readers needs it, so start-up work on the document fails in
`on_start`. Found on 2026-09-23, in omnet-julia: the campaign window focuses
the runner's group there, and its `on_open` opens the file navigator and the
study there (plan `an-operation-enters-at-any-reference`, the omnet-julia step).

## 2. Who uses `on_start` now

Found on 2026-09-23 by a read-only search.

| Where | What it does in `on_start` | Kind |
| --- | --- | --- |
| `fault/FaultLogOverlay.jl:211` | attaches the fault log to the editor's fault store | hands the editor on |
| `shell/WindowChrome.jl:151` (`run_with_window_tools`) | starts the message log capture and the feeds | hands the editor on |
| `example/projectured/Application.jl:389` | the above, and declares the assistant's API and tools | hands the editor on |
| `example/projectured/Gallery.jl:338` | wraps a caller's hook | passes it on |
| `example/projectured/FeedExamples.jl:42` | starts a driver | hands the editor on |
| `example/fault/FaultExamples.jl:171, 189` | starts a timer that breaks the backend | hands the editor on |
| omnet `qtenv/QtenvWindowScene.jl:64`, `qtenv/QtenvWindowRun.jl:30, 105` | starts the simulation driver | hands the editor on |
| omnet `campaign/CampaignWindow.jl:180` | declares the API, focuses the runner's group, runs `on_open` (the IDE opens its panes) | hands the editor on, and **works on the document** |

Only the last one works on the document, and only it breaks.

## 3. The one call is a sequence that exists

```julia
initialize_backend!(backend)
open_native_windows!(backend, document)
editor = Editor(backend, document, projection, devices; feeds)
run_editor!(editor; mcp, fault_policy)      # sets the policy, calls on_start, runs the loop
quit_backend!(backend)                      # in a finally
```

(`source/kernel/editor/EditorLoop.jl`, `run_editor!(backend, projection,
document; …)`.) A caller that holds the editor can do its set-up between the
build and the run.

## 4. The proposal

- **`make_editor(…)` builds the editor and prints it once.** It starts the
  backend, opens the windows, builds the `Editor`, sets the fault policy, and
  prints once, so `editor.iomap` exists. It runs no frame: a frame also reads
  the backend's input, and nothing may read input before the loop.
- **`run_editor!(editor)` runs the loop, and quits the backend when the loop
  ends,** so the backend's start and quit stay inside two functions and the
  guarantee of the `finally` stays.
- **A caller with set-up** writes `editor = make_editor(…)`, does its set-up —
  attach, declare, start a driver, open panes with the verbs — and calls
  `run_editor!(editor)`. The MCP server starts inside `run_editor!`, after the
  set-up, as it starts after `on_start` now, so a tool the set-up declares
  reaches a client.
- **The one-call forms stay for a caller with no set-up,** with no hook:
  `run_editor!(backend, projection, document)` and `run_window_editor(…)`.
- **`on_start` goes,** from `run_editor!`, `run_window_editor`, the gallery and
  every caller.

## 5. Decisions (2026-09-23, the lead's answers, taken by the owner)

1. **Two methods of one name, which mirror the two one-call forms.** The kernel's
   `make_editor(backend::Backend, projection, document::Document; devices,
   feeds, fault_policy)`, and the screen's `make_editor(document, projection,
   title::AbstractString; backend, width, height, opened_window_projections,
   screen_wrap, feeds, fault_policy)`. The kernel's form is needed too, because
   the fault overlay and the gallery use the kernel's one-call form. With
   `document::Document` in the kernel's method, the two can not overlap: no
   document is a string. The one-call forms become
   `run_editor!(make_editor(…); mcp, …)`.
2. **`make_editor` calls `print!(editor)`.** Fact: `print!`
   (`kernel/editor/FaultBarriers.jl`) prints only when `editor.iomap` is
   `nothing`, and it prints in the context that carries the clock, the root, the
   fault store and the fault policy; a bare `print_document` would lose that
   context. So the loop's first frame reuses the print, and the window shows its
   content once before the loop.
3. **`make_editor` passes the fault policy to `Editor(…)`,** which takes it now
   (`fault_policy = make_strict_fault_policy()` by default). The keyword of
   `run_editor!(editor)` defaults to the editor's own policy, so an editor from
   `make_editor` is not printed a second time. The three tests that build a
   strict `Editor` and run its loop (`McpTest.jl:716`, `WaitTest.jl:110`,
   `InboxTest.jl:120`) then run strict.
4. **The loop quits the backend it ran on, always.** Fact: `quit_backend!` has no
   default in the kernel (`kernel/backend/BackendInterface.jl`), and the console
   backend's quit is harmless for a stream that is not a terminal. A custom test
   backend gets a method, such as the one in `WaitTest.jl`. A flag in `Editor`
   that remembers who started the backend was considered and not taken: it adds
   state.

Not taken: a do-block form, `make_editor(…) do editor … end`. It would be
`on_start` under another name.

## 6. Steps

The owner approved every step on 2026-09-23.

### Step 0 — facts
- [x] Found on 2026-09-23 and folded into §5 (decisions 2, 3 and 4).

### Step 1 — `make_editor`, and `run_editor!(editor)` quits the backend
- [x] The two methods of `make_editor` (§5, decision 1): the kernel's in
      `kernel/editor/EditorLoop.jl`, the screen's in `screen/WindowScene.jl`,
      which extends the kernel's generic and exports the name too.
- [x] `run_editor!(editor)` quits the backend in a `finally`; its whole body,
      the setting of the fault policy too, is inside the `try`. Its
      `fault_policy` defaults to the editor's own.
- [x] The one-call forms are `make_editor` and `run_editor!(editor)`. Until
      Step 2 they still pass `on_start`, which now runs after the one print.
- [x] Tests: `WaitTest.jl` — an editor that `make_editor` answers has an iomap
      and was drawn once; the loop quits the backend, also when it throws (a
      probe backend that counts its starts, draws and quits; the probe wait
      backend got a `quit_backend!` method). `ApplicationTest.jl` — an editor
      from the screen's `make_editor` takes `focus_pane!` before any loop, and
      every level holds its part of one path. `make_editor` prints inside the
      print barrier, as a frame does, and quits the backend when the build or
      the print throws.

  Suites: `test_editor_wait` 20/20, `test_editor_inbox` 28/28,
  `test_application` 235/235, `test_kernel` with the six known failures; the
  naming, argument and tree guards pass.

### Step 2 — the callers of `on_start` in projectured-julia
- [x] The fault overlay, `run_with_window_tools`, the application, the gallery
      and the examples of §2 do their set-up between `make_editor` and
      `run_editor!`.
- [x] `on_start` goes from `run_editor!` and `run_window_editor`.

  Decisions and facts found on 2026-09-23:
  - **The gallery gets `make_example_editor`, not a third method of
    `make_editor`.** It mirrors `run_example`, as the two `make_editor`
    methods mirror the two one-call forms. It takes the keywords of
    `run_example` except `profile`, and it attaches the fault log that every
    window shows. `run_example` is `make_example_editor` and then the loop,
    under the profiler when `profile` is set. `ProjecturedExample` exports it,
    and `ProjecturedFaultExample` imports it.
  - `run_with_window_tools` keeps its protocol `run(feeds, start)`. The caller
    calls `start(editor)` between `make_editor` and `run_editor!`.
  - The fault overlay has no caller of its own: only its docstring used
    `on_start`.
  - Two tests used the hook. `McpTest.jl` declares its tool before
    `run_editor!`, and the server still lists it, because the server starts
    when the loop starts. `InboxTest.jl` needs a call that is posted while the
    loop runs. It posts a `RunFunctionOperation` before the loop, and the loop
    applies it on its own task as its first work.

### Step 3 — omnet-julia
- [x] Qtenv starts its driver between `make_editor` and `run_editor!`.
- [x] The campaign window and the IDE do their start-up work there: the focus,
      the file navigator and the study, with the verbs that read through the
      readers.

  Done on 2026-09-23 (omnet-julia commit `798145dc`). Facts and decisions:
  - **§2 missed four callers**, found in this step: `run_mm1k_project` and
    `run_demo` of the presentation examples, `run_watch_example`, and
    `run_session_example`. All of them now make the editor, do their work, and
    run the loop.
  - **The gallery also got `make_example_editor(document, projection; name)`**
    (projectured-julia commit `5b35fe6b`), which mirrors the one-document
    `run_example`, because Qtenv and the demos open one window.
  - **The watch demo keeps its own field `on_start`**, `(document, editor) ->
    nothing`. It is data of a demo, the work that starts with the editor, and it
    is now called between `make_example_editor` and `run_editor!`. Its name is
    the owner's to change.
  - **The campaign window** declares its API, binds the meaning model, and runs
    `on_open` between `make_editor` and `run_editor!`; the MCP keywords go to
    `run_editor!`, the others to `make_editor`. The runner's group takes the
    first focus on the tree before the wrap (plan
    `an-operation-enters-at-any-reference`, §3, the first focus), because that
    write is at the root.
  - omnet-julia is tested in a scratch environment whose `[sources]` point at
    both worktrees; the suites are listed in the omnet-julia step of plan
    `an-operation-enters-at-any-reference`.

### Step 4 — the guides
- [x] `editor.md` and the guides that describe `on_start` or the one-call forms:
      `kernel/editor.md` (the two halves, an example with work before the
      loop, and when the MCP server starts), `fault/fault.md`, `mcp/mcp.md`,
      `shell/shell.md`, `screen/screen.md` and
      `kernel/devices-and-backends.md`. The one-call forms with no work before
      the loop stay as they are in the other guides.
