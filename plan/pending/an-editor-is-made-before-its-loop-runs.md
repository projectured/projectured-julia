# An editor is made before its loop runs

**Status (2026-09-23): DESIGN.** Nothing is implemented, and no step is approved
to start. The owner asked for this plan, and named the new function
`make_editor`. The rest is the lead's proposal, to confirm.

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

## 5. Open questions

1. **`make_editor` at which level?** The kernel's form takes a backend, a
   projection and a document. `run_window_editor` also builds the scene and its
   projection from a document and a title. One name with two methods (the
   kernel's and the screen's), or the screen's callers compose
   `make_window_scene`, `make_window_scene_projection` and the kernel's
   `make_editor`?
2. **Does the first frame reuse the iomap that `make_editor` printed?** To check
   in `print!`: a loop that prints again at once throws the work away, which is
   harmless but slow.
3. **The fault policy.** `run_editor!(editor)` sets it now, and prints again when
   it differs. `make_editor` must take it and set it before the one print.
4. **Editors that tests build** with `Editor(…)` and run with `run_editor!(editor)`:
   check that quitting the backend at the end of the loop suits them.

## 6. Steps

No step is approved to start.

### Step 0 — facts
- [ ] The answers to questions 2 and 4, read-only.

### Step 1 — `make_editor`, and `run_editor!(editor)` quits the backend
- [ ] `make_editor`, at the level question 1 decides.
- [ ] `run_editor!(editor)` quits the backend in a `finally`.
- [ ] The one-call forms are `make_editor` and `run_editor!(editor)`.
- [ ] Tests: an editor that `make_editor` answers has an iomap; a verb that
      reads through the readers works on it before the loop; the backend quits
      when the loop ends, also when it throws.

### Step 2 — the callers of `on_start` in projectured-julia
- [ ] The fault overlay, `run_with_window_tools`, the application, the gallery
      and the examples of §2 do their set-up between `make_editor` and
      `run_editor!`.
- [ ] `on_start` goes from `run_editor!` and `run_window_editor`.

### Step 3 — omnet-julia
- [ ] Qtenv starts its driver between `make_editor` and `run_editor!`.
- [ ] The campaign window and the IDE do their start-up work there: the focus,
      the file navigator and the study, with the verbs that read through the
      readers.

### Step 4 — the guides
- [ ] `editor.md` and the guides that describe `on_start` or the one-call forms.
