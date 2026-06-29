# Clipboard `run_example` Wrapper + OS-Clipboard Bridge

> **Status: DONE (implemented 2026-06-29, worktree `clipboard-os-bridge`).** Both features
> shipped. See **Implementation outcomes** below for what changed vs. the drafted plan.

## Implementation outcomes (2026-06-29)

What was actually built, including decisions that diverged from the draft:

1. **OS backend = direct shell-out, not `InteractiveUtils.clipboard`.** The draft recommended
   Julia's built-in `clipboard`, but adding `InteractiveUtils` to the domain package's `[deps]`
   would churn manifests across the multi-package workspace. Since `InteractiveUtils.clipboard`
   itself just shells out, [`OsClipboardModule`](../../package/domain/src/common/OsClipboard.jl)
   shells out directly to the first available of `xclip` / `xsel` / `wl-paste`/`wl-copy` /
   `pbpaste`/`pbcopy`, behind a `Ref`-based stub seam (`set_os_clipboard_backend!` /
   `reset_os_clipboard_backend!`). No new dependency.
2. **JSON `from_text` reuses the existing `jsonparse`.** `package/domain/src/parser/JsonParser.jl`
   already provides a full recursive `jsonparse(text) -> JsonDocument`, so **Open Question #1 is
   resolved in favor of full JSON paste** (not scalar-only): `_json_from_text` tries `jsonparse`
   and falls back to wrapping non-JSON text as a `JsonString`. `_json_to_text` is a small
   hand-written compact serializer (no serializer existed).
3. **Generic wrapper OS bridge defaults OFF** (Open Question #2 recommendation adopted) — pasting
   OS text into an arbitrary domain isn't type-safe. JSON converters are wired only into the
   dedicated `clipboard_example`.
4. **Slice-only OS bridge** (Open Question #3): `to_text`/`from_text` live on
   `ClipboardSliceToAnyProjection`; `ClipboardCollectionToAnyProjection` is unchanged.
5. **Test environment = repo ROOT project (`julia --project=.`)**, not `package/test`. The root
   `Project.toml` carries `[sources]` for every sub-package (including `ProjecturedTulip`);
   `package/test` on its own can't resolve them.

Tests: `test_clipboard_to_any()` green incl. the new 14-assertion `slice OS clipboard bridge`
testset; `test_printer/reader/repl(clipboard_example)` = 699/225/225; generic-wrapper smoke
(`walk_printer_output` + `walk_repl_loop` over the JSON example wrapped via
`make_clipboard_*`) = 0 errors, 33 selections; no regression in `test_gesture_help`,
`test_printer(json_example)` (3143), `test_printer(widget_example)` (6913).

---

> **Original draft status (PENDING, 2026-06-29).** Two related features for the internal-clipboard
> projection. Verified against `main` at drafting time:
> `ClipboardSliceToAnyProjection` / `ClipboardCollectionToAnyProjection` live in
> `package/domain/src/projection/primitive/ClipboardToAny.jl`; the OS-clipboard branch is the
> unported `#+nil` case. `run_example` had wrapper flags
> `workbench` / `scrolling` / `introspection` / `tooltip` / `inspector` / `text_*` but **no**
> `clipboard` flag. The generic doc/projection wrappers live in
> `package/example/src/document/Wrapper.jl` and `package/example/src/projection/Wrapper.jl`.

## Goals

1. **Clipboard wrapper in `run_example`.** A `clipboard=true` keyword that wraps *any* example's
   document in a `ClipboardSlice` (or `ClipboardCollection`) and stacks the clipboard projection on
   top of that example's own pipeline — mirroring how `workbench` / `introspection` / `scrolling`
   wrap an arbitrary example today. Lets you do `run_example(json_example; clipboard=true)`.

2. **OS-clipboard bridge, both directions.** Extend the clipboard projection so that:
   - **Paste fallback (OS → ProjecturEd):** when nothing is on the internal ProjecturEd clipboard
     (`slice` is empty), `Ctrl+V` pastes from the **OS** clipboard instead.
   - **Copy/cut mirror (ProjecturEd → OS):** when `Ctrl+C` / `Ctrl+X` / `Ctrl+N` store into the
     internal slice, *also* push a text rendering of the copied sub-document to the OS clipboard.

   This is the port of the Lisp `clipboard/slice->t` `#+nil` branch that shells out to `xclip`.

## Background: how the pieces fit today

### The clipboard projection ([ClipboardToAny.jl](../../package/domain/src/projection/primitive/ClipboardToAny.jl))

- `ClipboardSlice(content; slice, selection)` wraps one `content` document plus an optional stored
  `slice`. `ClipboardSliceToAnyProjection` exposes either `content` or `slice` (toggled by `Ctrl+/`)
  and its `output` is the **active child's output directly** — it is domain-generic, it does not wrap
  the child in any clipboard-shaped node.
- Gestures are reified in `projection_gestures(p, iomap)` as a `GestureBinding[]` table; the readers
  `_clipboard_copy` / `_clipboard_cut` / `_clipboard_note` / `_clipboard_paste` /
  `_clipboard_paste_copy` build declarative `CompoundOperation`s and return `nothing` to decline
  (falling through to the wrapped content's reader).
- `_clipboard_paste(input)` today: `slice = input.slice; slice isa Document || return nothing`. The
  empty-slice case is exactly the hook point for the OS paste fallback.

### How `run_example` wraps an arbitrary example ([Examples.jl](../../package/example/src/Examples.jl))

Each wrapper is a `(document, projection)` transform applied in the per-example loop
(`Examples.jl:268-300`), built from a pair of helpers:

| flag            | document helper                                | projection helper                              |
|-----------------|------------------------------------------------|------------------------------------------------|
| `workbench`     | `make_workbench_document`                      | `make_workbench_projection`                    |
| `scrolling`     | `make_scrolling_document`                      | `make_scrolling_projection(projection)`        |
| `introspection` | `make_introspection_document(doc, projection)` | `make_introspection_projection(projection)`    |

The **introspection** wrapper is the model to copy: it composes an *arbitrary inner projection* by
routing `Any => NestingProjection(projection; recursion=PreservingProjection())` inside a
`RecursiveProjection(TypeDispatchingProjection(...))`. `NestingProjection` isolates the inner
projection's recursion so it renders the wrapped sub-tree to graphics independently
([projection/Wrapper.jl:28-34](../../package/example/src/projection/Wrapper.jl)).

## Design

### Part A — generic clipboard wrapper (mirrors introspection)

Add two helpers next to the existing wrapper helpers.

**`package/example/src/document/Wrapper.jl`:**
```julia
# Wrap any example document in a clipboard slice so the clipboard copy/cut/paste
# flow can operate over it. `collection=true` uses a ClipboardCollection instead.
make_clipboard_document(document; collection=false) =
    collection ? ClipboardCollection(document) : ClipboardSlice(document)
```

**`package/example/src/projection/Wrapper.jl`:**
```julia
# Stack the clipboard projection on top of an arbitrary example projection. The
# clipboard projection exposes the active child (content or stored slice) directly;
# the wrapped `projection` renders that child all the way to graphics (the
# introspection NestingProjection pattern). `to_text`/`from_text` are the optional
# OS-clipboard converters (Part B); nothing ⇒ no OS interaction.
function make_clipboard_projection(projection; collection=false,
                                   to_text=nothing, from_text=nothing)
    clip = collection ?
        ClipboardCollectionToAnyProjection() :
        ClipboardSliceToAnyProjection(; to_text=to_text, from_text=from_text)
    RecursiveProjection(TypeDispatchingProjection(Pair{DataType,Any}[
        (collection ? ClipboardCollection : ClipboardSlice) => clip,
        Any => NestingProjection(projection; recursion=PreservingProjection()),
    ]))
end
```

Why this composition works: `ClipboardSliceToAnyProjection.output` is `content_iomap.output`, where
`content_iomap = projection_printer_recurse(recursion, content, …)`. The recursion is the outer
dispatcher, which routes the content (e.g. a `JsonArray`) to `Any => NestingProjection(projection)`,
producing graphics. So the clipboard projection emits the inner example's graphics directly — no
extra downstream stages needed (unlike the hand-written `make_clipboard_projection_example`, which
keeps the JSON-specific `SyntaxToText`/`TextToGraphics` stages in its own `SequentialProjection`).
Reference mapping composes through `NestingProjection` exactly as it does for introspection's first
tab (which is interactive), so selection/click round-tripping keeps working.

**`run_example`:**
- Add `clipboard=false` (and optionally `clipboard_collection=false`) to the keyword list.
- In the per-example loop add an `elseif clipboard` branch after `introspection`:
  ```julia
  elseif clipboard
      document   = make_clipboard_document(document; collection=clipboard_collection)
      projection = make_clipboard_projection(projection; collection=clipboard_collection,
                                             to_text=..., from_text=...)  # see Part B defaults
  ```
- Add mutual-exclusivity guards next to the existing ones (`clipboard` with `tooltip` / `inspector`
  is incompatible because those wrap/compose `win.content` separately).

**Selection seeding subtlety (must handle, like `tooltip`):** the caller-supplied `selection` is
applied to the *bare* document before wrapping (`Examples.jl:274`). After wrapping, that document
becomes `ClipboardSlice.content`, so the seeded selection lives one level deeper. The
selection-lifting loop (`Examples.jl:342-353`) currently special-cases only `tooltip`
(`win.content.child`); extend it so for `clipboard` it reads `win.content.content`'s selection and
lifts via `@reference windows[i].content.content.^(inner_sel)`. The `ClipboardSlice`'s own
`selection` must end up as the `content`-prefixed path, because the clipboard readers drive
copy/cut/paste off `input.selection`.

### Part B — OS-clipboard bridge (both directions)

#### B0. OS-clipboard access, stubbable for headless tests

The test/CI environment is headless with **no `xclip`/`xsel`/`wl-clipboard`** (verified
2026-06-29), so the real OS clipboard must sit behind an indirection that tests can stub, and that
degrades gracefully at runtime.

New tiny module `package/domain/src/common/OsClipboard.jl` (or a section in an existing common
file), exporting:
```julia
os_clipboard_read()::Union{String,Nothing}   # nothing on failure / unavailable
os_clipboard_write(text::AbstractString)::Bool # false on failure
```
Implementation: default to Julia's `InteractiveUtils.clipboard()` / `clipboard(text)` (cross-platform;
on Linux it shells to xclip/xsel/wl-clipboard), each wrapped in `try/catch` returning
`nothing`/`false`. Keep the read/write behind module-level function `Ref`s (e.g.
`const _READER = Ref{Function}(...)`) so a test can install a fake in-memory clipboard. **Decision:**
prefer Julia's built-in `clipboard` over shelling out directly — it already handles backend
selection and is one dependency-free call (verified `InteractiveUtils.clipboard` is available).

#### B1. Converter hooks on the clipboard projection (backward-compatible)

Add two optional fields to `ClipboardSliceToAnyProjection` (and, if collection support is wanted,
`ClipboardCollectionToAnyProjection`):
```julia
mutable struct ClipboardSliceToAnyProjection <: Projection
    display_slice::Cell
    to_text::Any     # Document -> String, or nothing   (copy/cut/note mirror to OS)
    from_text::Any   # String -> Document, or nothing    (paste fallback from OS)
end
ClipboardSliceToAnyProjection(; display_slice=false, to_text=nothing, from_text=nothing) = …
```
**Both default to `nothing`**, so the existing constructor call sites, the `clipboard_example`, and
every test in `ClipboardToAnyTest.jl` keep today's behavior (no OS interaction) unchanged — including
the existing assertion that paste with an empty slice produces no `CompoundOperation`
([ClipboardToAnyTest.jl:142-149](../../package/test/src/projection/ClipboardToAnyTest.jl)). That test
must be updated/duplicated to cover the new `from_text != nothing` path separately.

#### B2. Paste fallback (OS → ProjecturEd) — happens in the reader

The reader is the right place to read the OS clipboard, because the produced operation must carry a
concrete `Document` to write (every other clipboard op does). Extend `_clipboard_paste`:
```julia
function _clipboard_paste(input, p)
    sel = input.selection
    (sel === nothing || sel isa EmptyReferencePath) && return nothing
    slice = input.slice
    if !(slice isa Document)
        # Internal clipboard empty — fall back to the OS clipboard.
        p.from_text === nothing && return nothing
        text = os_clipboard_read()
        text === nothing && return nothing
        doc = p.from_text(text)
        doc isa Document || return nothing
        return CompoundOperation(Any[replace_document(sel, doc),
                                      ReplaceSelectionOperation(sel)])
    end
    CompoundOperation(Any[replace_document(sel, slice),
                          ReplaceSelectionOperation(sel)])
end
```
(`_clipboard_paste_copy` gets the same fallback, deep-copying the converted doc.) The gesture closures
in `projection_gestures` already capture `p`, so threading `p` into the readers is a local change.

#### B3. Copy/cut/note mirror (ProjecturEd → OS) — needs a side-effecting operation

Writing the OS clipboard is a side effect, so it must run at `evaluate_operation` time, not in the
reader. Add:
```julia
struct WriteOsClipboardOperation <: Operation
    text::String
end
evaluate_operation(editor, op::WriteOsClipboardOperation) = (os_clipboard_write(op.text); nothing)
```
Then, when `p.to_text !== nothing`, append it to the compound built by copy/cut/note. E.g. in
`_clipboard_copy`:
```julia
ops = Any[replace_document(_field_path("slice"), copy_document(obj)),
          ReplaceSelectionOperation(sel)]
if p.to_text !== nothing
    txt = p.to_text(obj)
    txt isa AbstractString && push!(ops, WriteOsClipboardOperation(String(txt)))
end
CompoundOperation(ops)
```
(`evaluate_operation` for `CompoundOperation` already evaluates members in order, so the OS write
piggybacks on the existing copy compound.)

#### B4. Concrete converters

The converters are **domain-specific**, so they are supplied by the caller, not baked into the
projection. Two sets:

- **Text/primitive domains (the safe generic default for the `run_example` wrapper):**
  - `to_text(doc)`: `doc isa PrimitiveString ? something(doc.value,"") : doc isa TextText ? <join> : nothing`.
  - `from_text(text)`: `PrimitiveString(text)`.
  This round-trips cleanly for primitive-string / text examples. It is **not** safe to paste a
  `PrimitiveString` into a JSON document (the JSON dispatcher can't render it), so the generic
  default is appropriate only when the wrapped example's domain accepts a `PrimitiveString` node.

- **JSON (for the existing `clipboard_example`, which wraps JSON):**
  - `to_text(doc)`: small recursive `json_to_text(JsonString/JsonNumber/JsonBool/JsonNull/JsonArray/JsonObject)`
    → JSON source string. (No serializer exists today; this is a ~30-line helper. The projection
    pipeline also produces text, but a direct serializer is simpler and side-effect-free.)
  - `from_text(text)`: a minimal JSON-value reader (quoted ⇒ `JsonString`, numeric ⇒ `JsonNumber`,
    `true`/`false` ⇒ `JsonBool`, `null` ⇒ `JsonNull`, else `JsonString`). No JSON parser exists in
    the domain today — **decision needed on how far to take this** (see Open questions).

**Wiring:** the `clipboard_example`'s `make_clipboard_projection_example` passes the JSON converters
into `ClipboardSliceToAnyProjection(; to_text=json_to_text, from_text=json_from_text)`. The
`run_example(; clipboard=true)` wrapper passes the generic text converters by default (overridable).

## Testing

- **Unit (no display, stubbed OS clipboard):** extend
  [ClipboardToAnyTest.jl](../../package/test/src/projection/ClipboardToAnyTest.jl):
  - With `to_text` set, `Ctrl+C`/`Ctrl+X`/`Ctrl+N` append a `WriteOsClipboardOperation` whose `text`
    matches the converter output; `evaluate_operation` calls the stubbed writer.
  - With `from_text` set and an **empty** slice, `Ctrl+V` reads the stubbed OS clipboard and produces
    a `replace_document(sel, doc)` compound with the converted document.
  - With converters `nothing` (default), behavior is byte-for-byte today's — including empty-slice
    paste producing no compound. Run `test_clipboard_to_any()`.
- **Wrapper round-trip:** `test_printer(clipboard_example)` / `test_reader(clipboard_example)` /
  `test_repl(clipboard_example)` on a *fresh* document (per the registry-exclusion note at
  `Examples.jl:119-130`). Add a smoke check that `make_clipboard_projection(json_example.projection)`
  prints and that a click maps a selection back through the `NestingProjection`.
- **Manual:** `run_example(json_example; clipboard=true)` and `run_example(clipboard_example)` — but
  note the OS bridge is inert in this headless box (no xclip); exercise the OS path through the stub
  in tests, and on a desktop with a clipboard tool for the live check.

## Open questions / decisions for the user

1. **How far should the JSON `from_text` parser go?** Options: (a) scalar-only reader
   (string/number/bool/null) — small, covers the common copy-a-leaf case; (b) full recursive JSON
   parser (arrays/objects) — more work, no existing parser to reuse; (c) skip JSON `from_text` and
   only support copy-out for JSON, leaving paste-from-OS to text/primitive examples. **Recommend (a).**
2. **Generic wrapper default converters:** ship the text/`PrimitiveString` converters as the
   `run_example(; clipboard=true)` default (works for text examples, unsafe to *paste* into JSON), or
   default the wrapper's OS bridge **off** and only enable converters for the dedicated
   `clipboard_example`? **Recommend: default off in the generic wrapper, JSON converters wired into
   `clipboard_example`** — avoids the cross-domain paste hazard while still demonstrating both
   directions.
3. **Collection support:** mirror the OS bridge onto `ClipboardCollectionToAnyProjection` too, or
   slice-only for v1? **Recommend slice-only for v1.**

## Step-by-step checklist

- [x] **B0** `OsClipboard` helper module (`common/OsClipboard.jl`): `os_clipboard_read` /
      `os_clipboard_write` via **direct shell-out** (xclip/xsel/wl-*/pb*) — *not* InteractiveUtils,
      see outcome #1 — behind stubbable `Ref`s, try/catch degradation. Included in
      `ProjecturedDomain.jl`; symbols re-export via the `Projectured` umbrella.
- [x] **B1** Added `to_text` / `from_text` fields (default `nothing`) to `ClipboardSliceToAnyProjection`
      + keyword constructor; threaded `p` into the paste/copy/cut/note reader helpers.
- [x] **B2** Paste fallback in `_clipboard_paste` / `_clipboard_paste_copy` (empty slice + `from_text`
      ⇒ read OS, convert, replace) via `_os_paste_document`.
- [x] **B3** `WriteOsClipboardOperation` + `evaluate_operation`; appended to copy/cut/note compounds
      when `to_text` set (`_maybe_os_mirror!`). Exported.
- [x] **B4** JSON `_json_to_text` (hand-written serializer) / `_json_from_text` (reuses existing
      `jsonparse`, JsonString fallback) in `example/.../projection/Clipboard.jl`; wired into
      `make_clipboard_projection_example`. (Generic-text converter pair dropped — generic wrapper
      keeps the OS bridge off, outcome #3.)
- [x] **A1** `make_clipboard_document` (document/Wrapper.jl) + `make_clipboard_projection`
      (projection/Wrapper.jl).
- [x] **A2** `run_example`: `clipboard` (+ `clipboard_collection`) kwarg, per-example wrap branch,
      mutual-exclusivity guards (vs tooltip/inspector), selection-lifting through `.content`.
- [x] **Tests** extended `ClipboardToAnyTest.jl` (`slice OS clipboard bridge`, stubbed backend, both
      directions, default-off regression); `test_printer/reader/repl(clipboard_example)` on fresh
      docs; generic-wrapper smoke via `walk_printer_output`/`walk_repl_loop`.
- [x] **Docs** updated the `ClipboardToAny.jl` module docstring (OS bridge no longer `#+nil`),
      documented the `clipboard` flag in `run_example`'s docstring, and added
      `WriteOsClipboardOperation` to `documentation/operations.md`.
- [x] Moved to `plan/done/`.
```
