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

Create `program/src/document/Bookmark.jl`:

```julia
"""
    BookmarkModule

A domain for bookmark lists. Each bookmark has a title and a URL.
A BookmarkList is an ordered collection of BookmarkEntry documents.
"""
module BookmarkModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export BookmarkDocument, BookmarkInsertion,
       BookmarkEntry, BookmarkList

# ── Abstract base ──────────────────────────────────────────────────────────

abstract type BookmarkDocument <: Document end

# ── BookmarkInsertion ──────────────────────────────────────────────────────

@document struct BookmarkInsertion <: BookmarkDocument
    value::Any
    selection::Reference
end
BookmarkInsertion() = BookmarkInsertion(Cell(nothing), Cell(nothing))

# ── BookmarkEntry ──────────────────────────────────────────────────────────

"""
    BookmarkEntry(title, url)

A single bookmark: a title string and a URL string.
Both fields are reactive Cells.
"""
@document struct BookmarkEntry <: BookmarkDocument
    title::String
    url::String
    selection::Reference
end

BookmarkEntry(title::AbstractString, url::AbstractString) =
    BookmarkEntry(Cell(title), Cell(url), Cell(nothing))

# ── BookmarkList ───────────────────────────────────────────────────────────

"""
    BookmarkList(name, entries)

An ordered collection of BookmarkEntry documents.
`entries` is a CellVector of BookmarkEntry nodes.
"""
@document struct BookmarkList <: BookmarkDocument
    name::String
    entries::CellVector
    selection::Reference
end

function BookmarkList(name::AbstractString, entries::Vector)
    BookmarkList(Cell(name), Cell(CellVector(Cell[Cell(e) for e in entries])), Cell(nothing))
end

end # module
```

**Key points:**
- Every concrete `Document` subtype carries `selection::Reference`.
- `@document` makes `doc.title` read the cell value and `doc.title = v` write it.
- `CellVector` wraps a `Vector{Cell}` reactively — length changes invalidate
  downstream computed cells.
- See [reactive cells](reactive-cells.md) and [macros](macros.md)
  for the cell system and `@document` macro.

---

## Step 2: Register the domain in `Projectured.jl`

In `program/src/Projectured.jl`, add after the other document includes:

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

Create `program/src/projection/primitive/BookmarkToSyntax.jl`:

```julia
"""
    BookmarkToSyntaxModule

Bookmark → Syntax projection. Renders each BookmarkEntry as a SyntaxLeaf
pair (title and url), and a BookmarkList as a SyntaxNode whose children
are the entry leaves.
"""
module BookmarkToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..BookmarkModule: BookmarkDocument, BookmarkInsertion,
                          BookmarkEntry, BookmarkList
import ..TextModule: TextString
import ..FontModule: font_ubuntu_monospace_regular_18
import ..ColorModule: StyleColor, color_default, color_solarized_blue,
                      color_solarized_cyan
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..SequentialProjectionModule: SequentialProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, FieldReference,
                           PositionReference, ReferencePath, EmptyReferencePath
import ..PrinterContextModule: PrinterContext, child_context
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation

export BookmarkEntryToSyntaxNode, BookmarkListToSyntaxNode, BookmarkToSyntax

const _font = font_ubuntu_monospace_regular_18

# ── BookmarkEntry → SyntaxNode ─────────────────────────────────────────────

struct BookmarkEntryToSyntaxNode <: Projection end

function projection_print(p::BookmarkEntryToSyntaxNode,
                           recursion, entry::BookmarkEntry, ctx)
    title_leaf = SyntaxLeaf(
        TextString("▶ ", _font, color_solarized_blue),
        TextString("", _font, color_default),
        TextString(() -> entry.title, _font, color_solarized_blue),
        getfield(entry, :selection),   # shared selection cell
    )
    url_leaf = SyntaxLeaf(
        TextString("   ", _font, color_default),
        TextString("", _font, color_default),
        TextString(() -> entry.url, _font, color_solarized_cyan),
        Cell(nothing),
    )
    node = SyntaxNode(
        TextString("", _font, color_default),
        TextString("", _font, color_default),
        TextString("  ", _font, color_default),
        Cell(CellVector(Cell[Cell(title_leaf), Cell(url_leaf)])),
        Cell(0),       # indentation
        Cell(false),   # collapsed
        getfield(entry, :selection),
    )
    SimpleIoMap(p, entry, node)
end

function projection_read(p::BookmarkEntryToSyntaxNode,
                          iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    # Selection passes through unchanged (shared cell handles it)
    op
end

# ── BookmarkList → SyntaxNode ──────────────────────────────────────────────

struct BookmarkListToSyntaxNode <: Projection end

function projection_print(p::BookmarkListToSyntaxNode,
                           recursion, list::BookmarkList, ctx)
    # Project each entry recursively. `recursion` is threaded twice (projection
    # to call + that call's own recursion arg); `child_context` extends the
    # reference path to entry i.
    child_iomaps = Cell(() ->
        [projection_print(recursion, recursion, getfield(list, :entries)[][i][],
                          child_context(ctx, ElementReference(i)))
         for i in 1:length(list.entries)])

    children = Cell(() -> CellVector(Cell[Cell(m.output) for m in child_iomaps[]]))

    header_leaf = SyntaxLeaf(
        TextString("", _font, color_default),
        TextString("", _font, color_default),
        TextString(() -> list.name, _font, color_solarized_blue),
        Cell(nothing),
    )

    # Selection: find which child the input selection points to
    sel = Cell(() -> begin
        path = list.selection
        @reference_case path begin
            entries[i].rest... => begin
                iomaps = child_iomaps[]
                i > length(iomaps) && return nothing
                child_sel = iomaps[i].output.selection
                child_sel === nothing && return nothing
                # prepend [i] to place it within the child list
                ConcreteReferencePath(ElementReference(i), child_sel)
            end
            _ => nothing
        end
    end)

    node = SyntaxNode(
        TextString("", _font, color_default),
        TextString("", _font, color_default),
        TextString("\n", _font, color_default),
        children,
        Cell(0),
        Cell(false),
        sel,
    )
    ChildrenIoMap(p, list, node, child_iomaps)
end

function projection_read(p::BookmarkListToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    op   # pass navigation operations through unchanged
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
- `projection_print` must return an `IoMap` (here `SimpleIoMap` or
  `ChildrenIoMap`), not just the output document.
- The selection is wired as a *computed cell* (`Cell(() -> ...)`) that reads
  the input document's selection reactively.
- `ChildrenIoMap` is used when the projection recurses into children, because
  the reader may need to know which child IO map corresponds to a given child.
- `RecursiveProjection(TypeDispatchingProjection(...))` is the standard
  pattern for domains with multiple types.
- See [the projection system guide](projection-system.md) and
  [the selection deep dive](selection-deep-dive.md).

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

Create `example/src/document/Bookmark.jl`:

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

Create `example/src/projection/Bookmark.jl`:

```julia
function make_bookmark_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(BookmarkToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
```

In `example/src/ProjecturedExample.jl`, add:

```julia
include(joinpath(_EXAMPLE_DIR, "document", "Bookmark.jl"))
include(joinpath(_EXAMPLE_DIR, "projection", "Bookmark.jl"))
export make_bookmark_document_example, make_bookmark_projection_example
```

In `example/src/Examples.jl`, add:

```julia
const bookmark_example = Example("bookmark",
    make_bookmark_document_example, make_bookmark_projection_example)
```

And add `bookmark_example` to the `examples` vector.

---

## Step 6: Write a test

Create `test/src/projection/BookmarkToSyntaxTest.jl`:

```julia
function test_bookmark_to_syntax()

@testset "BookmarkEntry → SyntaxNode" begin
    entry = BookmarkEntry("Julia", "https://julialang.org")
    iomap = projection_print(BookmarkEntryToSyntaxNode(), entry,
                             PreservingProjection(),
                             Projectured.PrinterContextModule.PrinterContext())
    node = iomap.output
    @test node isa SyntaxNode
    # two children: title leaf and url leaf
    @test length(node.elements) == 2
    @test node.elements[1].value == "Julia"
    @test node.elements[2].value == "https://julialang.org"
end

@testset "BookmarkList → SyntaxNode" begin
    list = BookmarkList("Test", [
        BookmarkEntry("A", "http://a.example"),
        BookmarkEntry("B", "http://b.example"),
    ])
    proj = SequentialProjection(
        RecursiveProjection(BookmarkToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=(t,f) -> (length(t)*10, 20)),
    )
    iomap = projection_print(proj, list)
    @test iomap.output isa GraphicsCanvas
end

end # test_bookmark_to_syntax
```

In `test/src/ProjecturedTest.jl`:

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
  ──[SyntaxToText]──▶ TextText
  ──[TextToGraphics]──▶ GraphicsCanvas ──▶ SDL window
```

## What to add next

- **Character editing:** implement `projection_read` methods that produce
  `StringReplaceRangeOperation` for the `title` and `url` fields.
- **Structural editing:** `CollectionInsertOperation` to append bookmarks.
- **A custom operation:** e.g. `BookmarkOpenOperation` that opens the URL
  in a browser when Enter is pressed.

For the next level of complexity — a domain with cross-references, a custom
reader that handles structural events, or a `TableToGraphics`-style direct
renderer — read [the projection system guide](projection-system.md) §"Writing a
custom projection" and look at `MathToSyntax.jl` as a real-world reference.
