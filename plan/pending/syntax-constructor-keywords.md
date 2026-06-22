# Flexible keyword constructors for the Syntax domain

## Context

The Syntax domain's two workhorse types, `SyntaxLeaf` and `SyntaxNode`
([domain/src/document/Syntax.jl](../../domain/src/document/Syntax.jl)), are
constructed by every `*ToSyntax` projection. Their canonical
`@document`-generated inner constructors are fully positional:

```julia
SyntaxLeaf(open, close, value, indentation, collapsed, selection)              # 6 args
SyntaxNode(open, close, sep, children, indentation, collapsed, selection)      # 7 args
```

The projection builders call these directly, which makes call sites noisy. The
recurring patterns are:

- **Trailing boilerplate** — almost every call ends in `…, 0, false, nothing)`
  or `…, 0, Cell(false), Cell(nothing))` just to fill `indentation`,
  `collapsed`, `selection` with their defaults. Examples:
  [FormulaToSyntax.jl:165](../../domain/src/projection/primitive/FormulaToSyntax.jl#L165),
  [ConversationToSyntax.jl:89](../../domain/src/projection/primitive/ConversationToSyntax.jl#L89),
  [XmlToSyntax.jl:283-290](../../domain/src/projection/primitive/XmlToSyntax.jl#L283-L290).
- **Spelled-out empty delimiters** — a leaf/node with no open/close/sep still
  must pass `TextString("", p.style.font, color_default)` in each empty slot,
  e.g. [JsonToSyntax.jl:54-58](../../domain/src/projection/primitive/JsonToSyntax.jl#L54-L58),
  [XmlToSyntax.jl:347-351](../../domain/src/projection/primitive/XmlToSyntax.jl#L347-L351).
- **Positional open/close/sep ahead of the real content**, so the thing the
  reader cares about (the value, or the children) is buried after three
  delimiter arguments.

[XmlToSyntax.jl:36-45](../../domain/src/projection/primitive/XmlToSyntax.jl#L36-L45)
already documents the *desired* shape in a comment — `SyntaxLeaf(open="<",
close=" ", value=tag)`, `SyntaxNode(open="", close=">", sep=" ", […])` — but the
code can't express it yet.

There are **~260 call sites** across 14 projection files plus tests. This plan
adds flexible **keyword** constructors so the content is the positional
argument and every delimiter / layout / selection field is an optional keyword
with a sensible default, then migrates the callers.

### Goal

Let callers write the minimum that carries meaning:

```julia
# leaf with just a value (open/close default to empty, layout/selection defaulted)
SyntaxLeaf(TextString("null", p.style))

# leaf with delimiters
SyntaxLeaf(bound(:value, String, …); open=TextString("\"", p.key), close=TextString("\"", p.key))

# node — children positional, delimiters + separator + indentation as keywords
SyntaxNode(collection(:elements); open=TextString("[", p.delim), close=TextString("]", p.delim),
           sep=TextString(", ", p.sep), indentation=1)
```

## Design

### Field defaults

| field         | default        | notes |
|---------------|----------------|-------|
| `open`        | `TextString("")` | empty delimiter |
| `close`       | `TextString("")` | empty delimiter |
| `sep` (node)  | `TextString("")` | empty separator |
| `indentation` | `0`            | |
| `collapsed`   | `false`        | auto-wrapped to `Cell(false)` by the inner ctor |
| `selection`   | `nothing`      | auto-wrapped to `Cell(nothing)` |

### The constructors

Add one **untyped-content** keyword constructor per type, forwarding to the
existing `@document` inner constructor (which already wraps each value in a
`Cell`, so any value type is accepted in the content slot):

```julia
# SyntaxLeaf — `value` is the sole positional; untyped so it also accepts a
# `bound(...)`/marker object from @projection_template builders.
SyntaxLeaf(value; open=TextString(""), close=TextString(""),
           indentation::Int=0, collapsed=false, selection=nothing) =
    SyntaxLeaf(_text(open), _text(close), value, indentation, collapsed, selection)

# SyntaxNode — `children` is the sole positional; accepts a Vector, CellVector,
# Function builder, or a `collection(...)` marker.
SyntaxNode(children; open=TextString(""), close=TextString(""), sep=TextString(""),
           indentation::Int=0, collapsed=false, selection=nothing) =
    SyntaxNode(_text(open), _text(close), _text(sep), _children(children),
               indentation, collapsed, selection)
```

Two small helpers keep ergonomics and accept the shapes already in use:

```julia
# auto-wrap a bare string delimiter so callers can write open="<"
_text(t::TextString) = t
_text(s::AbstractString) = TextString(s)

# normalize the children argument to what the inner ctor stores
_children(c::CellVector) = c
_children(c::Vector) = CellVector(Cell[Cell(x) for x in c])   # Vector{<:SyntaxDocument} and Any[]
_children(f::Function) = CellVector(f)
_children(c) = c                                              # marker (Collection) — inner ctor wraps in Cell
```

String/function content ergonomics route through the keyword form so they pick
up keyword defaults too:

```julia
SyntaxLeaf(s::AbstractString; kwargs...) = SyntaxLeaf(TextString(s); kwargs...)
SyntaxLeaf(f::Function; kwargs...) =
    SyntaxLeaf(TextString(f, font_ubuntu_monospace_regular_24, color_default); kwargs...)
```

### Dispatch / ambiguity analysis (the Julia keyword gotcha)

Julia dispatches on **positional** arguments only; keyword arguments are matched
*after* the method is chosen. So a call `SyntaxLeaf(ts; open=…)` would dispatch
to a more-specific positional-only method `SyntaxLeaf(value::TextString)` if one
exists — and then error, because that method declares no keywords. To avoid
this:

- **Replace** the existing 1-argument positional-only leaf methods
  (`SyntaxLeaf(::TextString)`, `SyntaxLeaf(::AbstractString)`,
  `SyntaxLeaf(::Function)`,
  [Syntax.jl:249-253](../../domain/src/document/Syntax.jl#L249-L253)) with the
  keyword-bearing versions above. With no 1-arg positional-only method left, the
  generic `SyntaxLeaf(value; kwargs...)` is the unique 1-arg method (the
  `::AbstractString`/`::Function` ones are strictly more specific and also carry
  keywords), so there is no shadowing.
- For `SyntaxNode`, no 1-arg `SyntaxNode(children)` method exists today, so the
  new `SyntaxNode(children; kwargs...)` is added cleanly. The existing
  multi-positional forms (3-arg `open,close,sep`; 4-arg `…,children`;
  `…,f::Function`) keep working and are left in place for the migration window.

### Backward compatibility

This is **purely additive except** for replacing the three 1-arg `SyntaxLeaf`
convenience methods (whose no-keyword behaviour is preserved). All existing
multi-positional constructors — including the `@document` inner ctors that
`@projection_template` walks rely on, and the 7-arg form JsonToSyntax uses for
markers — remain valid. Migration of callers can therefore proceed file by
file without a flag day.

### Behavioural nuance to verify: empty-delimiter font

Today the scalar leaves pass `TextString("", p.style.font, color_default)` for
their empty open/close, i.e. the empty delimiter inherits the value's font. The
new default `TextString("")` uses `font_ubuntu_monospace_regular_24`. For an
**empty** delimiter the content renders nothing, so this can only matter to
cursor metrics at that boundary — and these scalar leaves never place a cursor
on their empty open/close (the cursor lives on `.value`). The expectation is
that printer/reader/navigation output is unchanged, but this must be
**confirmed by tests** during migration (see Verification). Where a specific
font on an empty delimiter turns out to matter, the caller keeps passing
`open=TextString("", font, color)` explicitly — the keyword still allows it.

> **Finding (JsonToSyntax migration).** Where the omitted empty delimiter's font
> *equals* the default regular monospace font (the four JSON scalar leaves —
> null/insertion/bool/number — all use `font_ubuntu_monospace_regular_24`),
> dropping it is byte-identical and `test_json_to_syntax` / `_reader` /
> `test_syntax_to_text` stayed exactly at baseline (11/0/0, 47/1/0, clean). Where
> the empty delimiter's font *differs* from the default (the JsonObject pair
> node's `p.delim.font` is **bold**), the explicit `open=`/`close=` keyword is
> kept rather than defaulted, so behaviour is preserved with zero risk. Rule of
> thumb for the remaining files: default an omitted empty delimiter only when its
> font matches the regular monospace default; otherwise keep it explicit.

### Discovered constraint: fixed-children template nodes keep raw-Vector children

A `@projection_template` node built by a `collection(:f) do x … end` element
builder (e.g. the JsonObject per-entry pair node) is walked by the engine's
`_fixed_print`, which **locates the children field by `getfield(out, f)[] isa
Vector`** ([ProjectionTemplate.jl:266-271](../../domain/src/projection/ProjectionTemplate.jl#L266-L271))
and iterates the raw vector to classify each child (`project(:value)` marker →
delegated slot, a `bound` leaf → key slot). The new `SyntaxNode(children; …)`
keyword path runs `_children`, which normalizes an `AbstractVector` to a
`CellVector` (`<: Document`, **not** `Vector`) — so the walk would fail with
"fixed-children node has no children vector". Therefore such a node must keep the
**positional** form so its children stay a raw `Cell(Vector)` carrying the
markers. Its inner leaves can still use keyword form. This affects only the
fixed-children template nodes; ordinary nodes (homogeneous `collection(:f)`
markers, or plain document-vector children) migrate freely.

### Scope

In scope: `SyntaxLeaf` and `SyntaxNode` (the noisy 6/7-arg positional types).

Out of scope but noted: the wrapper/container types (`SyntaxDelimitation`,
`SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`,
`SyntaxConcatenation`, `SyntaxSeparation`) already expose keyword/short
constructors and are not a source of caller noise; leave them unless migration
surfaces a concrete gap.

## Implementation steps

Do the work in a dedicated git worktree; commit after each step.

### 1. Add the keyword constructors — ✅ Done (commit 27dd65b)

In [domain/src/document/Syntax.jl](../../domain/src/document/Syntax.jl):

- Add the `_text` and `_children` helpers (module-private).
- Add `SyntaxLeaf(value; open, close, indentation, collapsed, selection)` and the
  `AbstractString`/`Function` content wrappers; **remove** the three superseded
  1-arg positional methods.
- Add `SyntaxNode(children; open, close, sep, indentation, collapsed, selection)`.
- Update the docstrings ([Syntax.jl:216-227](../../domain/src/document/Syntax.jl#L216-L227),
  [Syntax.jl:257-269](../../domain/src/document/Syntax.jl#L257-L269)) to show the
  keyword form as primary.

Verify nothing broke before touching callers: `test_syntax()`, `test_cell()`.

### 2. Migrate callers, highest-noise first

Migrate one file per commit, running that domain's targeted test after each.
Ordered by call count:

| file | calls | targeted test | status |
|------|------:|---------------|--------|
| [JsonToSyntax.jl](../../domain/src/projection/primitive/JsonToSyntax.jl) (the open file) | 9 | `test_json_to_syntax()` | ✅ c3c49fc — 11/0/0, reader 47/1/0 baseline |
| [JuliaToSyntax.jl](../../domain/src/projection/primitive/JuliaToSyntax.jl) | 66 | `test_printer`/`test_reader` on the julia examples | |
| [SqlToSyntax.jl](../../domain/src/projection/primitive/SqlToSyntax.jl) | 41 | sql examples | |
| [ObjectToSyntax.jl](../../domain/src/projection/primitive/ObjectToSyntax.jl) | 18 | object examples | |
| [XmlToSyntax.jl](../../domain/src/projection/primitive/XmlToSyntax.jl) | 17 | `test_xml_to_syntax()` | |
| [BookToSyntax.jl](../../domain/src/projection/primitive/BookToSyntax.jl) | 14 | book examples | |
| [FormulaToSyntax.jl](../../domain/src/projection/primitive/FormulaToSyntax.jl) | 8 | formula examples | |
| [ConversationToSyntax.jl](../../domain/src/projection/primitive/ConversationToSyntax.jl) | 8 | conversation examples | |
| [MathToSyntax.jl](../../domain/src/projection/primitive/MathToSyntax.jl) | 7 | math examples | |
| [FileSystemToSyntax.jl](../../domain/src/projection/primitive/FileSystemToSyntax.jl) | 7 | filesystem examples | |
| [PrimitiveToSyntax.jl](../../domain/src/projection/primitive/PrimitiveToSyntax.jl) | 3 | primitive examples | |
| [DbCatalogToSyntax.jl](../../domain/src/projection/primitive/DbCatalogToSyntax.jl) | 3 | dbcatalog examples | |
| DocumentInsertionToSyntax.jl / CollectionToSyntax.jl | 1 each | respective examples | |

Start with **JsonToSyntax.jl** as the reference migration (it is the file the
user has open and exercises every content shape: opaque leaf, `bound(...)` leaf,
`collection(...)` node, and a templated `collection(:entries) do … end`). The
existing positional builders there become, e.g.:

```julia
# JsonNullToSyntaxLeaf
SyntaxLeaf(TextString("null", p.style))

# JsonArrayToSyntaxNode
SyntaxNode(collection(:elements);
           open=TextString("[", p.delim), close=TextString("]", p.delim),
           sep=TextString(", ", p.sep), indentation=1)
```

### 3. Migrate tests

The test files
([SyntaxTest.jl](../../test/src/document/SyntaxTest.jl),
[SyntaxToTextTest.jl](../../test/src/projection/SyntaxToTextTest.jl),
[SyntaxToWidgetTest.jl](../../test/src/projection/SyntaxToWidgetTest.jl),
[SyntaxTreeSelectionTest.jl](../../test/src/projection/SyntaxTreeSelectionTest.jl),
[example/src/document/Syntax.jl](../../example/src/document/Syntax.jl)) also call
the positional forms. Migrate them to keyword form for consistency.

### 4. (Optional follow-up) Retire redundant positional overloads

Once all callers use keyword form, the multi-positional `SyntaxLeaf`/`SyntaxNode`
convenience overloads (other than the `@document` inner ctors the template walk
needs) can be removed to keep one obvious way to construct each type. Track as a
separate cleanup; not required for the noise-reduction win.

## Verification

After each migration commit, run the **narrowest** test that covers the changed
file (per the repo's testing guidance — never default to `test_all`):

- Per domain: `test_json_to_syntax()`, `test_xml_to_syntax()`, or
  `test_printer(<example>)` / `test_reader(<example>)` /
  `test_text_navigation(<example>)` for the specific examples a file feeds.
- Syntax core after step 1: `test_syntax()`.
- **Empty-delimiter font check**: for the scalar-leaf domains (JSON null/bool/
  number, XML text/insertion) confirm `test_printer` and `test_reader` outputs
  are byte-identical before/after; if a navigation test regresses on a
  delimiter boundary, restore the explicit font keyword on that leaf.

Run a broad `test_printers()` / `test_readers()` sweep only once, at the end,
after every targeted test already passes.

## Open questions

1. Should `open`/`close`/`sep` keyword defaults be a single shared
   `const EMPTY_TEXT = TextString("")` to avoid allocating a fresh empty
   `TextString` per call? (Cells are mutable, but an empty delimiter is never
   mutated in place — worth confirming before sharing one instance.)
2. Do we want the `AbstractString` content ergonomics (`SyntaxLeaf("null")`) at
   all, given almost every real leaf needs a styled `TextString`? It may invite
   unstyled leaves by accident. Default: keep it (it already exists), but flag in
   review.
