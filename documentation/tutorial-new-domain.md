# Tutorial: Adding a New Domain

This tutorial walks through adding a complete new domain to ProjecturEd —
document types, projection to Syntax, reader, example, and test.

We will build a **Bookmark** domain: a list of bookmarks where each bookmark
has a title and a URL. By the end you will have a navigable bookmark editor
that renders like this:

```
▶ Julia programming language   https://julialang.org
▶ ProjecturEd on GitHub        https://github.com/projectured/projectured
```

Each step links to the relevant guide for deeper context.

---

## Step 1: Define the document types

Create `package/domain/main/document/Bookmark.jl`:

```julia
"""
    BookmarkModule

A domain for bookmark lists. Each bookmark has a title and a URL.
A BookmarkList is an ordered collection of BookmarkEntry documents.
"""
module BookmarkModule

import ..CellModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export BookmarkDocument, BookmarkInsertion,
       BookmarkEntry, BookmarkList

# ── Abstract base ──────────────────────────────────────────────────────────

abstract type BookmarkDocument <: Document end

# ── BookmarkInsertion ──────────────────────────────────────────────────────
#
# Every domain defines its own `…Insertion` type: it is the domain's *type-in
# entry point* — the placeholder a user replaces by typing. Its reader (added
# later) interprets the typed text in the domain's own terms (a JuliaInsertion
# parses arbitrary Julia; a JsonInsertion builds JSON values). That is why the
# Insertion type is per-domain rather than shared, even though the struct looks
# generic here.
#
# NOTE: the abstract root, this insertion, a `BookmarkNothing` placeholder,
# the Insert-key gesture and the insertion traits can all be generated from
# one line — `@domain Bookmark` (see documentation/macros.md, "`@domain`").
# They are spelled out here so the tutorial shows what the macro expands to.

@document struct BookmarkInsertion <: BookmarkDocument
    value::Any
end
BookmarkInsertion() = BookmarkInsertion(Cell(nothing))

# ── BookmarkEntry ──────────────────────────────────────────────────────────

"""
    BookmarkEntry(title, url)

A single bookmark: a title string and a URL string.
Both fields are reactive Cells.
"""
@document struct BookmarkEntry <: BookmarkDocument
    title::String
    url::String
end

BookmarkEntry(title::AbstractString, url::AbstractString) =
    BookmarkEntry(Cell(title), Cell(url))

# ── BookmarkList ───────────────────────────────────────────────────────────

"""
    BookmarkList(name, entries)

An ordered collection of BookmarkEntry documents.
`entries` is a CellVector of BookmarkEntry nodes.
"""
@document struct BookmarkList <: BookmarkDocument
    name::String
    entries::CellVector
end

function BookmarkList(name::AbstractString, entries::Vector)
    BookmarkList(Cell(name), Cell(CellVector(Cell[Cell(e) for e in entries])))
end

end # module
```

**Key points:**
- `@document` injects a `selection::Reference` field into every document
  automatically, appended as the struct's last field — you never declare it
  yourself (declaring one by hand is an error).
- `@document` makes `doc.title` read the cell value and `doc.title = v` write it.
- **Field names are public API.** A selection path reaches `title` / `url` /
  `entries` by `getfield`, so these names *are* the domain's reference
  vocabulary — choose them deliberately; renaming one later breaks stored
  references. (See the `Document` contract in
  [document/DocumentInterface.jl](../package/kernel/main/document/DocumentInterface.jl).)
- `CellVector` wraps a `Vector{Cell}` reactively — length changes invalidate
  downstream computed cells.
- See [reactive cells](../package/kernel/doc/cell.md) and [macros](../package/kernel/doc/macros.md)
  for the cell system and `@document` macro.

---

## Step 2: Register the domain in `Projectured.jl`

In `package/domain/main/ProjecturedDomain.jl`, add after the other document includes:

```julia
include("document/Bookmark.jl")
```

Add a `using` line (near the `using .ImageModule:` block):

```julia
using .BookmarkModule: BookmarkDocument, BookmarkInsertion,
                       BookmarkEntry, BookmarkList
```

Add an `export` line:

```julia
export BookmarkDocument, BookmarkInsertion, BookmarkEntry, BookmarkList
```

---

## Step 3: Write the projection (printer)

Create `package/domain/main/projection/primitive/BookmarkToSyntax.jl`:

```julia
"""
    BookmarkToSyntaxModule

Bookmark → Syntax projection. Renders each BookmarkEntry as a SyntaxLeaf
pair (title and url), and a BookmarkList as a SyntaxNode whose children
are the entry leaves.
"""
module BookmarkToSyntaxModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, print_child,
                               map_reference_forward, map_reference_backward, Projection
import ..BookmarkModule: BookmarkDocument, BookmarkInsertion,
                          BookmarkEntry, BookmarkList
import ..TextModule: TextString
import ..FontModule: font_ubuntu_monospace_regular_18
import ..ColorModule: StyleColor, color_default, color_solarized_blue,
                      color_solarized_cyan
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..ChainingProjectionModule: ChainingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, FieldReference,
                           PositionReference, ReferencePath, EmptyReferencePath
import ..PrinterContextModule: PrinterContext, make_child_context
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"

export BookmarkEntryToSyntaxNode, BookmarkListToSyntaxNode, BookmarkToSyntax

const _font = font_ubuntu_monospace_regular_18

# ── BookmarkEntry → SyntaxNode ─────────────────────────────────────────────

struct BookmarkEntryToSyntaxNode <: Projection end

function print_document(p::BookmarkEntryToSyntaxNode,
                           recursion, entry::BookmarkEntry, ctx)
    # This projection introduces the two leaves itself (title / url are plain
    # string fields, not recursed sub-documents), so it owns the whole
    # selection mapping: `.title{k} ↔ [1].value{k}`, `.url{k} ↔ [2].value{k}`.
    # Defer the iomap so the node-selection thunk can call the mapper.
    iomap_cell = Cell(nothing)

    # Each leaf's own (output-domain) selection — a cursor in its value span.
    title_sel = Cell(() -> @reference_case entry.selection begin
        title{k} => @reference value{k}
        _        => nothing
    end)
    url_sel = Cell(() -> @reference_case entry.selection begin
        url{k} => @reference value{k}
        _      => nothing
    end)

    title_leaf = SyntaxLeaf(
        TextString("▶ ", _font, color_solarized_blue),
        TextString("", _font, color_default),
        TextString(() -> entry.title, _font, color_solarized_blue),
        title_sel,
    )
    url_leaf = SyntaxLeaf(
        TextString("   ", _font, color_default),
        TextString("", _font, color_default),
        TextString(() -> entry.url, _font, color_solarized_cyan),
        url_sel,
    )
    node = SyntaxNode(
        TextString("", _font, color_default),
        TextString("", _font, color_default),
        TextString("  ", _font, color_default),
        Cell(CellVector(Cell[Cell(title_leaf), Cell(url_leaf)])),
        Cell(0),       # indentation
        Cell(false),   # collapsed
        # node selection is the input selection mapped forward by our own mapper
        Cell(() -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, entry.selection)
        end),
    )
    iomap = SimpleIoMap(p, entry, node)
    iomap_cell[] = iomap
    iomap
end

# The mappers are the single source of truth for how a path crosses this
# projection. With them defined, the default reader translates both selection
# moves and value edits backward — so no `read_intent` method is needed.
function map_reference_forward(::BookmarkEntryToSyntaxNode, iomap, reference)
    @reference_case reference begin
        ∅        => @reference()
        title{k} => @reference [1].value{k}
        url{k}   => @reference [2].value{k}
        _        => nothing
    end
end

function map_reference_backward(::BookmarkEntryToSyntaxNode, iomap, reference)
    @reference_case reference begin
        ∅            => @reference()
        [1].value{k} => @reference title{k}
        [2].value{k} => @reference url{k}
        _            => nothing
    end
end

# ── BookmarkList → SyntaxNode ──────────────────────────────────────────────

struct BookmarkListToSyntaxNode <: Projection end

function print_document(p::BookmarkListToSyntaxNode,
                           recursion, list::BookmarkList, ctx)
    iomap_cell = Cell(nothing)
    # Project each entry recursively via `print_child`, which
    # re-enters the whole pipeline for the child; `make_child_context` extends the
    # reference path with the `entries` field step and the element step, so the
    # child knows it sits at `entries[i]` relative to this node.
    child_iomaps = Cell(() ->
        [print_child(recursion, getfield(list, :entries)[][i][],
                                    make_child_context(ctx, FieldReference("entries"),
                                                  ElementReference(i)))
         for i in 1:length(list.entries)])

    children = Cell(() -> CellVector(Cell[Cell(m.output) for m in child_iomaps[]]))

    node = SyntaxNode(
        TextString("", _font, color_default),
        TextString("", _font, color_default),
        TextString("\n", _font, color_default),
        children,
        Cell(0),
        Cell(false),
        # node selection: the input selection mapped forward by our own mapper
        Cell(() -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, list.selection)
        end),
    )
    iomap = ChildrenIoMap(p, list, node, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

# School A: peel the one step this projection owns (`entries[i]` ↔ `[i]`) and
# delegate the tail to the child projection's own mapper, reached through the
# stored child IO maps. No `read_intent` is needed — the default reader uses
# `map_reference_backward` for both selection moves and edits.
function map_reference_forward(::BookmarkListToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        entries[i].rest... => begin
            ims = iomap.child_iomaps[]
            (i < 1 || i > length(ims)) && return nothing
            child = ims[i]
            mapped = map_reference_forward(child.projection, child, rest)
            mapped === nothing ? nothing : (@reference [i].^(mapped))
        end
        _ => nothing
    end
end

function map_reference_backward(::BookmarkListToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        [i].rest... => begin
            ims = iomap.child_iomaps[]
            (i < 1 || i > length(ims)) && return nothing
            child = ims[i]
            mapped = map_reference_backward(child.projection, child, rest)
            mapped === nothing ? nothing : (@reference entries[i].^(mapped))
        end
        _ => nothing
    end
end

# ── BookmarkToSyntax convenience constructor ───────────────────────────────

function BookmarkToSyntax()
    RecursiveProjection(TypeDispatchingProjection(Dict(
        BookmarkEntry => BookmarkEntryToSyntaxNode(),
        BookmarkList  => BookmarkListToSyntaxNode(),
    )))
end

end # module
```

**Key points:**
- `print_document` must return an `IoMap` (here `SimpleIoMap` or
  `ChildrenIoMap`), not just the output document.
- The output selection is wired as a *computed cell* (`Cell(() -> ...)`) that
  maps the input selection forward through this projection's **own**
  `map_reference_forward` — the deferred-iomap trick (`iomap_cell = Cell(nothing)`,
  assigned after the IoMap is built) lets the thunk reach the not-yet-built iomap.
- **Define `map_reference_forward` / `map_reference_backward`, not a
  `read_intent`.** The two mappers are the single source of truth for how a
  path crosses the projection; the default reader uses `map_reference_backward`
  to translate *both* selection moves and value edits backward. You only add a
  `read_intent` method when a projection must do more than re-target a
  reference.
- When the printer recurses into children (`print_child`), the
  mappers recurse **in lockstep** — peel the one step this projection owns and
  delegate the tail through the stored child IO maps (School A). A projection
  that introduces structure itself (like `BookmarkEntryToSyntaxNode`'s two
  leaves) writes that structural rewrite directly instead.
- `ChildrenIoMap` is used when the projection recurses into children, so the
  mappers can locate the child IO map for a given child.
- `RecursiveProjection(TypeDispatchingProjection(...))` is the standard
  pattern for domains with multiple types.
- See [the projection system guide](../package/kernel/doc/projection-system.md) and
  [the selection deep dive](../package/kernel/doc/selection.md).

---

## Step 4: Register the projection in `Projectured.jl`

Include the projection file (after the other primitive projections):

```julia
include("projection/primitive/BookmarkToSyntax.jl")
```

Add `using` and `export`:

```julia
using .BookmarkToSyntaxModule: BookmarkEntryToSyntaxNode, BookmarkListToSyntaxNode, BookmarkToSyntax
export BookmarkEntryToSyntaxNode, BookmarkListToSyntaxNode, BookmarkToSyntax
```

---

## Step 5: Add an example

Create `example/document/Bookmark.jl`:

```julia
function make_bookmark_document_example()
    list = BookmarkList("My Bookmarks", [
        BookmarkEntry("Julia programming language", "https://julialang.org"),
        BookmarkEntry("ProjecturEd on GitHub",
                      "https://github.com/projectured/projectured"),
        BookmarkEntry("JuliaHub",                  "https://juliahub.com"),
    ])
    set_selection!(list, @reference entries[1])
    list
end
```

Create `example/projection/Bookmark.jl`:

```julia
function make_bookmark_projection_example(; measure=sdl_measure_text)
    ChainingProjection(
        RecursiveProjection(BookmarkToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
```

In `example/ProjecturedExample.jl`, add:

```julia
include(joinpath(_EXAMPLE_DIR, "document", "Bookmark.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Bookmark.jl"))
export make_bookmark_document_example, make_bookmark_projection_example
```

In `example/Examples.jl`, add:

```julia
const bookmark_example = Example("bookmark",
    make_bookmark_document_example, make_bookmark_projection_example)
```

And add `bookmark_example` to the `examples` vector.

---

## Step 6: Write a test

Create `test/projection/BookmarkToSyntaxTest.jl`:

```julia
function test_bookmark_to_syntax()

@testset "BookmarkEntry → SyntaxNode" begin
    entry = BookmarkEntry("Julia", "https://julialang.org")
    # print_document(projection, recursion, input, ctx)
    iomap = print_document(BookmarkEntryToSyntaxNode(),
                             IdentityProjection(), entry,
                             Projectured.PrinterContextModule.PrinterContext())
    node = iomap.output
    @test node isa SyntaxNode
    # two children: title leaf and url leaf. SyntaxNode's children field is
    # `children`, and a SyntaxLeaf's `value` is a TextString — read `.value.content`
    # for the rendered string.
    @test length(node.children) == 2
    @test node.children[1].value.content == "Julia"
    @test node.children[2].value.content == "https://julialang.org"
end

@testset "BookmarkList → SyntaxNode" begin
    list = BookmarkList("Test", [
        BookmarkEntry("A", "http://a.example"),
        BookmarkEntry("B", "http://b.example"),
    ])
    proj = ChainingProjection(
        RecursiveProjection(BookmarkToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=(t,f) -> (length(t)*10, 20)),
    )
    iomap = print_document(proj, list)
    @test iomap.output isa GraphicsCanvas
end

end # test_bookmark_to_syntax
```

In `test/ProjecturedTest.jl`:

```julia
include("projection/BookmarkToSyntaxTest.jl")
```

And add `test_bookmark_to_syntax()` to `test_projections()`.

---

## What you now have

After all six steps, `run_example("bookmark")` opens a navigable bookmark
list in the SDL window. The cursor starts at the first entry title. You can
navigate with `←` / `→` through the title characters. The projection chain is:

```
BookmarkList
  ──[BookmarkToSyntax]──▶ SyntaxNode
  ──[SyntaxToText]──▶ TextBlock
  ──[TextToGraphics]──▶ GraphicsCanvas ──▶ SDL window
```

## What to add next

- **Character editing:** already works — a `ReplaceStringRangeOperation` on a
  leaf's value flows back through the default reader, which re-targets its
  reference via the `map_reference_backward` you defined (`[1].value{k}` →
  `title{k}`, `[2].value{k}` → `url{k}`). No extra `read_intent` needed.
- **Structural editing:** `insert_elements` (a `ReplaceReferencedValueOperation` splice) to
  append bookmarks — this *does* need a `read_intent` method, since it is more than a
  reference re-target.
- **A custom operation:** e.g. `BookmarkOpenOperation` that opens the URL
  in a browser when Enter is pressed.

For the next level of complexity — a domain with cross-references, a custom
reader that handles structural events, or a `TableToGraphics`-style direct
renderer — read [the projection system guide](../package/kernel/doc/projection-system.md) §"Writing a
custom projection" and look at `MathToSyntax.jl` as a real-world reference.
