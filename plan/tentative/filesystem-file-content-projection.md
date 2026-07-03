# FileSystemFile Content Projection with Live File Synchronization

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> **Status (2026-06-28): tentative — nothing implemented.** Searches for `content`
> on `FileSystemFile`, `FileSystemFileToText`, `FileSystemSynchronizer`, and
> `synchronize!` across `package/*/src/` find no definitions. Today `FileSystemFile`
> (`package/domain/src/document/FileSystem.jl`) carries only `pathname` +
> `selection`, and the only file-system projections — `FileSystemToSyntax` and
> `FileSystemToWidget` — render a node's *basename* for the directory-tree view;
> neither reads, watches, or writes file *contents*.
>
> **Central open question (why this is tentative):** how the external→document
> update is delivered. Two shapes are in play — (A) a loop-level synchronizer that
> **writes the `content` cell directly** (the minimal `EDITOR_TIME` precedent), or
> (B) the synchronizer **emits an `Operation`** that flows through `evaluate!`
> (undoable, logged, consistent). This plan now leans toward (B), keeps (A) as the
> fallback, and analyzes a fuller "file access as a `Device`" evolution under
> Alternatives. None of it is settled.

Add a projection that presents a `FileSystemFile`'s **contents** as an editable
text document, backed by a loop-level synchronizer that (a) detects external
on-disk changes and re-reads them into the document, and (b) writes the file back
to disk when the in-editor content is modified.

## Context

`FileSystemFile` is currently a pure-identity leaf: a `pathname` and a
`selection`, with no content. The existing projections are *navigation* views of
the tree (basename + icon/marker); opening a file to **edit its text** has no
representation yet.

Two hard constraints from the architecture shape the whole design:

1. **Reactive thunks must be pure** (see
   [documentation/reactive-cells.md](../../documentation/reactive-cells.md),
   "Invariants the engine relies on"): no disk I/O, no clock reads, no external
   mutable state inside a computed `Cell`. Disk contents and `mtime` are exactly
   the "external mutable state" the engine forbids in a thunk — so file reads and
   writes **cannot** live inside a printer thunk or any computed cell.

2. **Side effects belong to the editor loop.** The blessed pattern for getting
   external, time-varying input into the reactive graph is the one
   [plan/pending/animation-global-time.md](animation-global-time.md) establishes
   for the clock: *"a primitive cell holding the buffer, written by an external
   sampler in the loop, exactly like `EDITOR_TIME` itself."* The loop
   (`run!`/`play_live!` in
   [package/kernel/src/editor/Editor.jl](../../package/kernel/src/editor/Editor.jl))
   already ticks the clock and re-pulls cells every frame; file synchronization
   slots in next to it.

So the shape is: the file's contents live in a **primitive `Cell`** on the
document; an **external sampler driven by the loop** reads the cell and the disk
and reconciles them; the **projection** is an ordinary bidirectional
text projection over that cell (no I/O of its own).

This mirrors `PrimitiveStringToTextText`
([package/domain/src/projection/primitive/PrimitiveToText.jl](../../package/domain/src/projection/primitive/PrimitiveToText.jl))
almost exactly — a string value rendered as a single editable `TextText` span,
with editing reified once as `@gestures` on the document and reached through the
generic `document_read` fallback.

### Layering note (load-bearing)

`Editor` lives in the **kernel** layer
([package/kernel/src/editor/Editor.jl](../../package/kernel/src/editor/Editor.jl));
`FileSystemFile` lives in the **domain** layer
([package/domain/src/document/FileSystem.jl](../../package/domain/src/document/FileSystem.jl)).
Domain depends on kernel, never the reverse. Therefore the kernel cannot know
about `FileSystemFile`. The kernel must expose a **generic per-frame extension
point**; the file-specific synchronizer is implemented in the domain layer and
plugged in — the same way `Device`/`Backend` are abstract in the kernel
(`package/kernel/src/api/DeviceApi.jl`, `.../Backend.jl`) and made concrete higher up.

## Design overview

```
   disk file  ──(read on external change)──►  FileSystemFile.content : Cell
        ▲                                              │
        └──(write on local edit)──────────────────────┤  (projected)
                                                       ▼
   FileSystemSynchronizer  ◄── synchronize!(s) once/frame ──  FileSystemFileToText
   (domain/editor, side-effecting)                            (pure, bidirectional)
                                                              TextText ── … ── Graphics
```

- **Document**: `FileSystemFile` gains a `content::String` field (a reactive
  `Cell`), lazily populated (defaults to `nothing` = "not loaded"; the first
  synchronization loads it). `pathname`/`selection` unchanged.
- **Projection** (`FileSystemFileToText`): pure printer/reader over `content`,
  selection vocabulary `content{k}`. No disk access.
- **Synchronizer** (`FileSystemSynchronizer`): side-effecting, loop-driven.
  Holds per-file bookkeeping (`last_disk_mtime`, `last_known_content`) and
  reconciles disk ⇄ document each frame (throttled). On an external change it
  **emits an `Operation`** the loop applies via `evaluate!` (recommended shape B),
  or writes the `content` cell directly (fallback shape A); on a local edit it
  writes the file back.
- **Kernel hook**: `Editor` grows a `synchronizers` list and a generic
  `synchronize!(s, editor)` called once per frame in every loop variant, which may
  yield an operation for that frame.

Crucially, **all disk reads/writes happen in the loop, never in a thunk** — the
`content` cell is the primitive boundary through which external state enters the
graph, the exact `EDITOR_TIME` discipline. Whether the reload reaches `content`
via an operation (B) or a direct cell write (A) is the open question above; either
way the side effect is loop-bound.

## Phase 1 — Document: content + editing gestures

### File: `package/domain/src/document/FileSystem.jl`

Add a content field to `FileSystemFile`:

```julia
@document struct FileSystemFile <: FileSystemDocument
    pathname::String
    content::Any            # String when loaded, nothing when not yet read
    selection::Reference
end

# Lazy by default: content is nothing until the synchronizer loads it. This keeps
# make_filesystem_pathname over a whole directory tree free of eager disk reads.
FileSystemFile(pathname::AbstractString) =
    FileSystemFile(String(pathname), Cell(nothing), Cell(nothing))
```

`make_filesystem_pathname` is unchanged in behavior (it still constructs files
without reading them — the new constructor defaults `content` to `nothing`).

Add the geometry-free editing table, reified once on the document (mirrors
`@gestures PrimitiveString` in `PrimitiveToText.jl`). Selection vocabulary is
`content{range}` (a `FieldReference("content")` + `RangeReference`):

```julia
# Cursor range over the content, or nothing when the selection isn't a content edit.
function _file_content_range(f::FileSystemFile) ... end          # → RangeReference | nothing
_file_content_path(range::RangeReference) = @reference content.^(range)

@gestures FileSystemFile begin
    when(_file_content_range(doc) !== nothing)
    KeyPress(_, t)       => "Insert character" =>
        StringReplaceRangeOperation(_file_content_path(_file_content_range(doc)), t)
    KeyDown(:backspace;) => "Delete backward"  => _file_content_delete(doc, :backspace)
    KeyDown(:delete;)    => "Delete forward"   => _file_content_delete(doc, :delete)
end
```

`StringReplaceRangeOperation` already splices a string field via the standard
evaluate path, so editing `content` needs no new operation type. (`_file_content_delete`
mirrors `_string_delete`.)

**Selection clamping on reread.** When the synchronizer replaces `content` with
shorter text, a stale `content{k}` cursor may point past the end. Provide a small
helper `clamp_file_selection!(f)` the synchronizer calls after a reread, so the
cursor lands at `min(k, length(content))`. (The text layer should also tolerate an
out-of-range offset defensively, but clamping at the source is the clean fix.)

## Phase 2 — Projection: `FileSystemFileToText`

### File (new): `package/domain/src/projection/primitive/FileSystemFileToText.jl`

A pure, bidirectional projection from `FileSystemFile` to a single-span
`TextText`, modeled directly on `PrimitiveStringToTextText`. It does **no** I/O —
it only reads the reactive `content` cell, so when the synchronizer rewrites that
cell the rendered text recomputes for free.

```julia
@projection struct FileSystemFileToText
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_base0)
    placeholder::String = "(loading…)"        # shown while content === nothing
end

# Forward:  content{s:e}            → elements[1].content{s}
# Backward: elements[1].content{s:e} → content{s}
map_reference_forward(::FileSystemFileToText, iomap, ref)  = _forward_content(ref)
map_reference_backward(::FileSystemFileToText, iomap, ref) = _backward_content(ref)

function projection_print(p::FileSystemFileToText, recursion, f::FileSystemFile, ctx)
    span = TextString(() -> something(f.content, ""), p.style)        # reads the cell
    out  = TextText(CellVector(() -> TextDocument[span]),
                    Cell(() -> _content_selection_to_text(f)))
    SimpleIoMap(p, f, out)
end

# Selection re-targeting only; the default reader handles ReplaceSelectionOperation,
# and raw edit keystrokes fall through document_read → @gestures FileSystemFile.
function projection_read(p::FileSystemFileToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input = _backward_content(op.path); input === nothing && return nothing
    ReplaceSelectionOperation(input)
end
```

Wire it into the domain umbrella
([package/domain/src/ProjecturedDomain.jl](../../package/domain/src/ProjecturedDomain.jl),
next to the other `FileSystem*` includes around line 120). Export the projection.

> **Multi-line note.** A real file is multi-line; the single-span form above is the
> v1 minimum (it renders, navigates, and edits as one flat string, with
> `TextNewline`/line handling delegated downstream by `SyntaxToText`/word-wrap as
> usual). Splitting content into per-line spans, or going through a
> `Text`/`Syntax` parse, is a natural follow-up but out of scope here — keep v1 a
> faithful clone of the proven `PrimitiveString` text path.

## Phase 3 — Kernel: a generic per-frame synchronizer hook

### File: `package/kernel/src/api/Synchronizer.jl` (new) + `Editor.jl`

The kernel can't reference `FileSystemFile`, so add a generic extension point:

```julia
# api/Synchronizer.jl
abstract type Synchronizer end
# Called once per frame from the loop; concrete methods live in higher layers.
# Returns an Operation to apply this frame (shape B), or nothing.
synchronize!(::Synchronizer, editor) = nothing
```

Extend `Editor` with a `synchronizers::Vector{Synchronizer}` field (default
empty, so existing call sites are unaffected) and call them each frame in **all
three** loop bodies (`run!`, the timeline `play_live!`, and any future loop),
next to `tick!`. An operation a synchronizer returns is applied this frame —
slotted in only when live input produced none, so a real keystroke still wins:

```julia
while true
    perf_reset!()
    tick!(Base.time() - t_start)
    @perf_time :read_time read!(editor)
    if editor.operation === nothing                               # ← new: external sync
        for s in editor.synchronizers
            op = synchronize!(s, editor)
            if op !== nothing; editor.operation = op; break; end
        end
    end
    @perf_time :evaluate_time evaluate!(editor)
    @perf_time :print_time    print!(editor)
    ...
end
```

(The fallback shape A needs no operation slot — `synchronize!` just writes the
`content` cell and returns `nothing`; the call can then sit anywhere in the frame,
e.g. right after `tick!`.) Either way the change is visible the same frame: an
operation runs through `evaluate!` before `print!`, and a direct cell write
invalidates the text span's dependents so the existing per-frame re-pull renders
it — identical to how `EDITOR_TIME` animates.

> Lighter alternative: a `frame_hooks::Vector{Function}` of `editor -> nothing`
> closures instead of a typed `Synchronizer`. The typed form is preferred because
> it is directly unit-testable (construct one, call `synchronize!`) and
> self-documenting; see Alternatives.

## Phase 4 — Domain: `FileSystemSynchronizer`

### File (new): `package/domain/src/editor/FileSystemSynchronizer.jl`

Side-effecting, loop-driven reconciliation. Sits in the domain editor layer
alongside `ConversationEditor.jl`/`WorkbenchAssistant.jl`. Holds one watch entry
per file:

```julia
mutable struct FileWatch
    file::FileSystemFile
    last_disk_mtime::Float64       # mtime we last reconciled (0.0 ⇒ never loaded)
    last_known_content::Union{String,Nothing}  # disk truth as of last reconcile
end

mutable struct FileSystemSynchronizer <: Synchronizer
    watches::Vector{FileWatch}
    poll_interval::Float64         # seconds between stats (throttle; default ~0.5)
    last_poll::Float64
end
```

Per-frame logic (`synchronize!`), throttled by `poll_interval` against
`editor_time()` (sample, not subscribe — the loop is not a thunk, but sampling is
the right idiom and stays consistent with the clock plan).

**Recommended shape (B) — emit an operation.** Rather than mutating the `content`
cell in place, the synchronizer detects the external change and **returns/enqueues
an `Operation`** rooted at the file's `content` reference, which the loop feeds to
`evaluate!` exactly like a reader-produced operation. The reload then goes through
`evaluate_operation` — so it is undoable, logged (`@info "[operation]"`), and
consistent with every other mutation. The synchronizer already holds the
file→document mapping, so rooting the path is trivial. This needs a small
extension to the kernel hook: `synchronize!` may **produce an operation** the loop
applies (e.g. return it, or push onto an `editor.pending_operations` queue drained
next to `read!`). Write-back stays a direct side effect (there is nothing to make
undoable about flushing bytes).

```julia
# Returns an Operation to apply this frame, or nothing.
function synchronize!(s::FileSystemSynchronizer, editor)
    now = editor_time()
    now - s.last_poll < s.poll_interval && return nothing
    s.last_poll = now
    for w in s.watches
        isfile(w.file.pathname) || continue          # deleted/renamed: see Open Questions
        m   = mtime(w.file.pathname)
        cur = w.file.content                          # current cell value (plain read)
        if m > w.last_disk_mtime
            if cur === nothing || cur == w.last_known_content
                disk = read(w.file.pathname, String)  # SIDE EFFECT — in the loop, OK
                w.last_known_content = disk
                w.last_disk_mtime    = m
                # (B) hand the reload to evaluate! as an operation rooted at this file.
                return reload_operation(w.file, disk) # e.g. StringReplaceRangeOperation(content[0:len], disk)
            else
                # Conflict: both disk and editor changed. v1 policy below.
            end
        elseif cur !== nothing && cur != w.last_known_content
            write(w.file.pathname, cur)               # SIDE EFFECT — write-back, in the loop, OK
            w.last_known_content = cur
            w.last_disk_mtime    = mtime(w.file.pathname)  # re-stat to absorb our own write
        end
    end
    return nothing
end
```

`reload_operation` produces a `StringReplaceRangeOperation` over the whole
`content` (or a dedicated `ReloadFileOperation`); the existing evaluate path
splices `content`, and `evaluate_operation` is the natural place to also
`clamp_file_selection!` after the swap.

**Fallback shape (A) — direct cell write.** If the operation plumbing isn't worth
it for v1, the synchronizer can instead set `w.file.content = disk` directly. This
is still legal because every disk read/write and every `content` cell write
happens **in the loop, never in a thunk** — the `content` cell is the primitive
boundary through which external state enters the graph, exactly the `EDITOR_TIME`
discipline. The cost is that a reload is a side-channel mutation: not undoable, not
logged, invisible to the operation history. That trade-off is the crux of the
central open question above.

**Registration.** Provide
`watch_file!(sync, f::FileSystemFile)` and a convenience that walks a document
(or subtree) collecting `FileSystemFile`s to watch. v1: the example wires a single
`FileSystemFile` as the document and registers it. (Watching every file in a large
tree is deferred — only *opened* files need watching; see Open Questions.)

**Initial load** falls out for free: a freshly constructed `FileWatch` has
`last_disk_mtime = 0.0`, so the first `synchronize!` sees `m > 0`, reads the file,
and populates `content`. No eager read at document-construction time.

### Conflict policy (v1)

When disk and editor both changed since the last reconcile, v1 keeps it simple and
**does not silently clobber**: leave the editor buffer as-is, do not overwrite the
disk, and surface the conflict (log + a `conflicted::Bool` flag on the watch the UI
can later show). External-wins and a real merge are explicitly deferred. Document
this clearly — silent data loss in either direction is the thing to avoid.

## Phase 5 — Example + tests

### Example

- `package/example/src/document/FileSystem.jl`: add
  `make_filesystem_file_example()` returning a `FileSystemFile` over a small
  fixture file (e.g. a temp file written under the scratch/test area, or a checked-in
  asset) so printer/reader tests have a stable target.
- `package/example/src/projection/FileSystem.jl`: add
  `make_filesystem_file_projection_example()`:
  `SequentialProjection(RecursiveProjection(FileSystemFileToText()), RecursiveProjection(SyntaxToText()), TextToGraphics(...))`
  (or `… FileSystemFileToText → SyntaxToText → …` matching the existing file
  projection example's tail).

### Tests (narrow scope — follow CLAUDE.md "smallest test that covers the change")

1. **Synchronizer reread** (`package/test/src/editor/FileSystemSyncTest.jl`, new):
   write a temp file, construct `FileSystemFile` + `FileSystemSynchronizer`,
   register, `synchronize!` → assert `content` cell now equals disk text and
   `last_disk_mtime` advanced. Then rewrite the file on disk, bump mtime,
   `synchronize!` again → assert content cell updated (external change wins when
   buffer is clean).
2. **Synchronizer write-back**: load a file, apply a `StringReplaceRangeOperation`
   to `content` (or set the cell), `synchronize!` → assert the on-disk bytes now
   match the edited content and `last_known_content` updated.
3. **Conflict**: edit the buffer *and* the disk between reconciles → assert disk is
   **not** clobbered, buffer preserved, `conflicted` set.
4. **Selection clamp**: cursor near end, reread shorter content → assert selection
   clamped in range.
5. **Projection** (`package/test/src/projection/FileSystemFileToTextTest.jl`, new,
   registered in `ProjecturedTest.jl`): `test_printer`/`test_reader` over
   `make_filesystem_file_example()` — print yields a `TextText` whose span content
   equals the file text; typing a character reads back a
   `StringReplaceRangeOperation` on `content{…}`; selection round-trips via the two
   reference mappers. Reuse the `walk_printer_output` / reader walkers per
   [documentation/testing.md](../../documentation/testing.md).

The synchronizer tests drive `synchronize!` **directly** (no live loop), so they
are deterministic and fast. Tests must use the session scratch dir for temp files
(never `/tmp`), per the repo guidance, and clean up.

## Files touched (summary)

| File | Change |
|---|---|
| `package/domain/src/document/FileSystem.jl` | `content` field on `FileSystemFile`; `@gestures FileSystemFile`; `_file_content_*`, `clamp_file_selection!` helpers |
| `package/domain/src/projection/primitive/FileSystemFileToText.jl` | **new** — bidirectional content↔TextText projection |
| `package/domain/src/editor/FileSystemSynchronizer.jl` | **new** — loop-driven disk⇄cell reconciler |
| `package/domain/src/ProjecturedDomain.jl` | include the two new domain files |
| `package/kernel/src/api/Synchronizer.jl` | **new** — abstract `Synchronizer` + generic `synchronize!` |
| `package/kernel/src/editor/Editor.jl` | `synchronizers` field; call `synchronize!` each frame in every loop variant |
| `package/example/src/document/FileSystem.jl`, `.../projection/FileSystem.jl` | example document + projection |
| `package/test/src/editor/FileSystemSyncTest.jl`, `.../projection/FileSystemFileToTextTest.jl` | **new** tests (+ register in `ProjecturedTest.jl`) |

## Alternatives considered

- **File access as a `Device` that emits change events.** The most "native"
  framing — a `FileSystemDevice` in `editor.devices` that surfaces external
  changes as input *events* (flowing through `projection_read` → operation →
  `evaluate!`) and flushes dirty content on write. Conceptually clean and
  backend-swappable, but it **does not fit the current `Device` interface**
  (`package/kernel/src/api/DeviceApi.jl`) without non-trivial changes, for two
  concrete reasons:

  1. **Polling is backend-mediated, not device-driven.** `read_from_devices(::Backend, devices)`
     is dispatched on the **Backend**; SDL/web/console each override it to poll
     *their own* event queue and classify — the device list is advisory. The loop
     only ever calls that one batch
     (`read_from_devices(editor.backend, editor.devices)`), so a `FileSystemDevice`
     never gets polled unless either every backend learns to also stat the
     filesystem (filesystem leaking into the SDL/web/console packages — wrong
     layer) or the loop is changed to also drain a generic per-device
     `read_from_device` path (declared in the interface but unused today). That is
     a change to the core input path of every editor.
  2. **A file event has no window or geometry, so the reader pipeline can't route
     it.** Device events become `EventEnvelope(window_id, event)`; readers map them
     via the current `iomap`, with `ScreenToScreen` routing by `window_id` and the
     geometry readers hit-testing pixel coordinates. A "file changed" event has
     neither. To become a `StringReplaceRangeOperation` on the right
     `FileSystemFile.content`, the event must **carry a document reference** to the
     target file and a reader must root the operation there — a route-by-reference
     mechanism that does not exist yet (everything routes by
     window/coordinate/selection). Trivial in a single-file editor; real new work
     in the tree/master-detail case.

  Write-back is a poor fit for the device path too: `write_to_devices` is handed
  the *pipeline output* (a `ScreenDocument`), not the input document, so a file
  device on that path can't reach the dirty `content` cell to flush it.

  **Verdict:** capture the value (reload-as-operation) via shape (B) above — a
  loop-level synchronizer that *emits* an operation — which needs none of the
  device/backend surgery. Promote to a real `Device` later, when file I/O should
  be a first-class backend-swappable channel (e.g. a remote-filesystem backend, or
  unifying with OS inotify notifications). Prerequisites for that step are now
  explicit: (i) generalize the loop to drain per-device inputs, (ii) add a
  `FileChangedEvent` carrying a target reference, (iii) add a reader that roots it.
- **`frame_hooks::Vector{Function}` instead of typed `Synchronizer`.** Lighter,
  but less testable and less discoverable. Chosen against for the reasons in
  Phase 3.
- **Eager content load in `make_filesystem_pathname`.** Rejected: reads every file
  in a tree up front (slow, and pointless for unopened files). Lazy load via the
  first `synchronize!` is strictly better.
- **`FileWatcher`/inotify OS notifications instead of mtime polling.** More
  efficient and lower-latency, but platform-specific and a larger dependency
  surface. mtime polling (throttled) is portable and adequate for v1; OS
  notifications are a clean later optimization behind the same `Synchronizer` seam.

## Open questions

- **Which files are watched?** v1 watches an explicitly registered set (the opened
  file). Auto-watching every `FileSystemFile` reachable from the document doesn't
  scale and re-reads files nobody is viewing. The right trigger is "watch on open"
  — but "open" needs a master-detail composition (tree view → selected file's
  content), which is its own effort (cf. the obsolete `master-detail-document.md`).
- **Deleted / renamed / moved files.** v1 skips a watch whose path no longer
  `isfile`. Whether to clear the buffer, mark deleted, or offer "save as" is a
  policy question deferred with the conflict UI.
- **Encoding / binary files.** v1 assumes UTF-8 text (`read(path, String)`).
  Non-text files need detection and a non-text presentation; out of scope.
- **Large files / atomic writes.** Whole-file read/write each reconcile is fine for
  source files; very large files want incremental or chunked handling, and writes
  may want write-to-temp-then-rename for atomicity. Deferred.
- **Throttle vs. latency.** `poll_interval ≈ 0.5s` trades responsiveness for stat
  load; tune, or move to OS notifications (above).
