# FileSystemFile Content Projection with Live File Synchronization

> **Status (2026-06-28): ⏳ ALL OPEN.** Nothing in this plan is implemented yet.
> Searches for `content` on `FileSystemFile`, `FileSystemFileToText`,
> `FileSystemSynchronizer`, and `synchronize!` across `package/*/src/` find no
> definitions. Today `FileSystemFile` (`package/domain/src/document/FileSystem.jl`)
> carries only `pathname` + `selection`, and the only file-system projections —
> `FileSystemToSyntax` and `FileSystemToWidget` — render a node's *basename* for
> the directory-tree view; neither reads, watches, or writes file *contents*.

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
(`package/kernel/src/api/Device.jl`, `.../Backend.jl`) and made concrete higher up.

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
  reconciles disk ⇄ cell each frame (throttled).
- **Kernel hook**: `Editor` grows a `synchronizers` list and a generic
  `synchronize!(s, editor)` called once per frame in every loop variant.

Crucially, the synchronizer **writes the `content` cell directly** and **reads
the disk directly** — both from the loop, never from a thunk. This is the exact
`EDITOR_TIME` pattern: external state enters the graph through a primitive cell
the loop writes.

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
synchronize!(::Synchronizer, editor) = nothing
```

Extend `Editor` with a `synchronizers::Vector{Synchronizer}` field (default
empty, so existing call sites are unaffected) and call them each frame in **all
three** loop bodies (`run!`, the timeline `play_live!`, and any future loop),
next to `tick!`:

```julia
while true
    perf_reset!()
    tick!(Base.time() - t_start)
    foreach(s -> synchronize!(s, editor), editor.synchronizers)   # ← new
    @perf_time :read_time     read!(editor)
    @perf_time :evaluate_time evaluate!(editor)
    @perf_time :print_time    print!(editor)
    ...
end
```

Placing it before `read!`/`print!` means an external reread is visible the same
frame. A directly-written `content` cell invalidates its dependents (the text
span) exactly like any other write, so the existing per-frame re-pull renders it
with no further plumbing — identical to how `EDITOR_TIME` animates.

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
the right idiom and stays consistent with the clock plan):

```julia
function synchronize!(s::FileSystemSynchronizer, editor)
    now = editor_time()
    now - s.last_poll < s.poll_interval && return
    s.last_poll = now
    for w in s.watches
        isfile(w.file.pathname) || continue          # deleted/renamed: see Open Questions
        m = mtime(w.file.pathname)
        cur = w.file.content                          # current cell value (peek/read)
        if m > w.last_disk_mtime
            # External change on disk.
            if cur === nothing || cur == w.last_known_content
                disk = read(w.file.pathname, String)  # SIDE EFFECT — in the loop, OK
                w.file.content = disk                 # primitive-cell write (EDITOR_TIME pattern)
                clamp_file_selection!(w.file)
                w.last_known_content = disk
                w.last_disk_mtime    = m
            else
                # Conflict: both disk and editor changed. v1 policy below.
            end
        elseif cur !== nothing && cur != w.last_known_content
            # Local edit, disk unchanged → write back.
            write(w.file.pathname, cur)               # SIDE EFFECT — in the loop, OK
            w.last_known_content = cur
            w.last_disk_mtime    = mtime(w.file.pathname)  # re-stat to absorb our own write
        end
    end
end
```

Why this is legal: every disk read/write and every `content` cell write happens
**in the loop**, never in a thunk. The `content` cell is the primitive boundary
through which external state enters the graph — exactly the `EDITOR_TIME`
discipline. The synchronizer reads `content` as a plain value (no dependency is
registered because the loop isn't a computed cell).

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

- **File access as a `Device`.** A `FileSyncDevice` could surface external changes
  as *operations* on `read_from_devices` and flush dirty content on
  `write_to_devices`, reusing the editor's existing device iteration. This routes
  external reloads through the operation/evaluate path (arguably cleaner than a
  side-channel cell write) but couples the device to specific document types and
  operations, and needs a dedicated "replace whole content" operation. Heavier than
  v1 warrants; revisit if reloads should be undoable.
- **Reload via an operation instead of a direct cell write.** Same trade-off:
  routing the reread through `evaluate_operation` makes it undoable/loggable but
  needs a new operation type and a way for a loop-level sampler to enqueue an
  operation. The animation plan explicitly blesses the direct primitive-cell write
  for external samplers; v1 follows that precedent.
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
