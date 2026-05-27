# Logging Support

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> In-document logging for editor projections: projections emit structured log
> entries into the editor's document, and a dedicated log projection picks them
> up for display within the editor itself.

---

## Motivation

Currently, diagnostics go to stdout (`println` in `evaluate!` and `perf!`).
This is invisible to the user inside the graphical editor and unavailable to
projections. An in-document log allows:

- Projections to report what they are doing (e.g. which reader handled an
  event, which printer branch was taken, how a reference was mapped).
- The editor to display these entries inline or in a dedicated panel, filtered
  by severity or source.
- Debugging of the projection pipeline without switching to the terminal.

---

## Design Principles

1. **Log entries are documents** — a log entry is a structured document
   (`LogEntry`) with timestamp, severity, source projection name, and a
   message (which can be any domain — string, syntax tree, reference path,
   etc.). Because entries are documents, they are projectable.
2. **The log lives on the Editor** — the `Editor` struct holds a
   `log::CellVector{LogEntry}` (bounded ring buffer). Projections receive a
   reference to this log and append to it during `projection_print` or
   `projection_read`.
3. **Logging is opt-in and zero-cost when off** — a global or per-projection
   flag (`log_enabled::Cell{Bool}`) guards emission. When disabled, no cells
   are allocated and no entries are pushed.
4. **Display is a projection** — a `LogProjection` projects the log document
   into the syntax/text/graphics domain like any other document, reusing the
   existing pipeline. It can be composed into the editor's projection via
   `SequentialProjection` or rendered in a split pane.

---

## Domain: Log Documents

```
LogSeverity  = :debug | :info | :warn | :error

@document struct LogEntry <: DocumentBase
    timestamp::Float64          # time()
    severity::LogSeverity
    source::String              # projection or module name
    message::String             # human-readable summary
    context::Any                # optional structured payload (document fragment, reference, etc.)
    selection::Reference
end

@document struct LogDocument <: DocumentBase
    entries::CellVector{LogEntry}   # bounded ring buffer
    max_entries::Int                 # capacity (e.g. 1000)
    filter_severity::LogSeverity    # minimum severity to display
    selection::Reference
end
```

---

## Steps

### 1. `LogEntry` and `LogDocument` domain types

Define `LogEntry` and `LogDocument` in a new `program/src/document/Log.jl`.
Include constructor helpers:

```julia
log_entry(source, message; severity=:info, context=nothing)
```

Register in `Projectured.jl` module includes.

### 2. Attach log to Editor

Add a `log::LogDocument` field to the `Editor` struct. Initialize with a
configurable capacity (default 1000 entries, ring buffer semantics — oldest
entries are dropped when full).

### 3. Logging API accessible to projections

Projections currently receive `(projection, input, recursion, reference)` in
the printer and `(projection, iomap, event)` in the reader. Extend the
calling convention (or pass via `recursion` context) so projections can call:

```julia
log!(recursion, :info, "JsonToSyntax", "printing object with $(n) entries")
```

`log!` pushes a `LogEntry` into the editor's `LogDocument` if logging is
enabled; otherwise it is a no-op.

Alternatively, store the log reference in a task-local or module-global that
the `run!` loop sets before each frame, keeping the projection API unchanged.

### 4. `LogToSyntax` projection (printer)

A printer that takes a `LogDocument` and produces a `SyntaxNode` tree:

- Each entry becomes a line: `[timestamp] [severity] [source] message`
- Severity drives color coding (debug=gray, info=white, warn=yellow, error=red)
- Entries are listed newest-first (or configurable)
- The filter_severity cell gates which entries appear

The reader is minimal: arrow keys scroll, severity filter toggle, maybe
clear-log keybinding.

### 5. Display integration

Two modes for showing the log in the editor:

- **Split pane** — the editor renders two documents side-by-side: the
  primary document and the log. This requires the viewport/layout work from
  section 10 of further-development.md, or a simpler ad-hoc split using
  `GraphicsCanvas` composition.
- **Overlay / toggle** — a keybinding (e.g. F12) swaps the editor's active
  document to the `LogDocument`, projected through `LogToSyntax →
  SyntaxToText → TextToGraphics`. Press F12 again to return. This is
  simpler and works today without layout changes.

Start with the overlay/toggle approach.

### 6. Per-projection log filtering

Each projection can declare a `log_tag::Symbol` (e.g. `:json_to_syntax`,
`:text_to_graphics`). The `LogDocument` gains a `filter_tags::Set{Symbol}`
cell. The display projection only shows entries whose tag is in the filter
set (or shows all if the set is empty). This lets the user focus on a
specific projection's output.

### 7. Structured context in log entries

The `context` field of `LogEntry` can hold arbitrary documents — a
`ReferencePath` that was being mapped, a `JsonValue` subtree that caused an
issue, an `IoMap` snapshot. The `LogToSyntax` printer can optionally expand
context inline (truncated) or allow the user to select a log entry and
"drill in" to its context as a sub-document.

---

## Open Questions

- **Performance impact** — even with the enabled flag, `log!` calls add
  branches in hot paths (printer runs every frame). Benchmark with logging
  disabled to verify zero overhead. Consider `@inline` and branch-prediction
  hints.
- **Ring buffer vs. unbounded** — ring buffer keeps memory bounded but loses
  history. Alternative: flush old entries to a file-backed log that can be
  loaded on demand. For now, ring buffer is sufficient.
- **Thread safety** — if projections run concurrently (future: parallel
  printing), the `CellVector` append must be safe. Currently single-threaded,
  so not an immediate concern, but the API should not preclude concurrency.
- **Passing log to projections** — changing the printer/reader signature is
  invasive. Using `recursion` as a carrier is natural (it already threads
  context through the pipeline). Need to verify all projection call sites
  pass `recursion` correctly.
- **Interaction with existing stdout logging** — the current `println` in
  `evaluate!` and `perf!` should migrate to `log!` calls once the system is
  in place, unifying all diagnostics into the in-document log.
- **Log as first-class document** — since the log is a document, it can
  itself be edited (entries deleted, annotated). Is this useful or confusing?
  Probably read-only by default, with a "clear" operation as the only
  mutation the user performs directly.

---

## Dependencies

- Requires `CellVector` from the reactive module (already exists).
- Display via overlay requires a keybinding mechanism (already exists in the
  device/keyboard layer).
- Split-pane display depends on graphical layout work (section 10 of
  further-development.md) — defer until that lands.
- Color coding of severity levels reuses `StyledString` attributes (already
  supported by `SyntaxToText` and `TextToGraphics`).
