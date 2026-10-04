# Tutorial: Adding a New Domain

> **Kind:** procedure · **Status:** current · **Stands on:** [domain-inventory.md](../design/domain-inventory.md), [system-anatomy.md](../design/system-anatomy.md)

This tutorial walks through adding a complete new domain to ProjecturEd:
document types, projection to Syntax, reader, example, and test.

We will build a **Bookmark** domain: a list of bookmarks where each bookmark
has a title and a URL. By the end you will have a navigable bookmark editor
that renders like this:

```
- Julia programming language   https://julialang.org
- ProjecturEd on GitHub        https://github.com/projectured/projectured
```

Each step links to the relevant guide for deeper context.

A domain is a package. Every main package the tutorial creates —
`package/ProjecturedBookmark/`, `package/ProjecturedBookmarkExample/`,
`package/ProjecturedBookmarkTest/` — is a flat sibling folder with its own
`Project.toml`; there is no nested `main/`/`test/`/`example/` folder under one
`package/bookmark/` directory. The code goes in `source/bookmark/`, the
documents in `example/bookmark/`, and the suite in `test/bookmark/`.

---

## Step 1: Define the document types

Create `source/bookmark/Bookmark.jl`. It is the slice's module file: one
module holds the whole slice, and every other file of the slice is a fragment
of it.

```julia
"""
    BookmarkModule

A domain for bookmark lists. Each bookmark has a title and a URL.
A BookmarkList is an ordered collection of BookmarkEntry documents.
"""
module BookmarkModule

using ..CellModule
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule

export BookmarkDocument, BookmarkEntry, BookmarkList

# ── Abstract base ──────────────────────────────────────────────────────────

abstract type BookmarkDocument <: Document end

# NOTE: the abstract root above, a BookmarkInsertion type-in entry point, a
# BookmarkNothing placeholder, the Insert-key gesture, and the insertion traits
# can all be generated from one line — `@domain Bookmark` (see
# [macros.md](../package/kernel/macros.md), "`@domain`"). A real domain writes
# that line; this tutorial skips it (and the insertion type it would need) to
# keep the walkthrough to the two document types the projection step teaches.

# ── BookmarkEntry ──────────────────────────────────────────────────────────

"""
    BookmarkEntry(title, url)

A single bookmark: a title string and a URL string.
"""
@document struct BookmarkEntry <: BookmarkDocument
    title::String
    url::String
end

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

end # module BookmarkModule
```

**Key points:**
- `@document` injects a `selection::Union{Nothing, Reference}` field into every
  document automatically, appended as the struct's last field. You never
  declare it yourself; declaring one by hand is an error.
- `@document` also generates the constructor: `BookmarkEntry("Julia", "https://julialang.org")`
  already works with no code of your own — a raw value is wrapped in a
  reactive `Cell`, and `doc.title` reads it back transparently
  (`doc.title = v` writes it). Write an *outer* constructor only for a
  convenience the macro does not cover (see [macros.md](../package/kernel/macros.md)).
- **Field names are public API.** A selection path reaches `title` / `url` /
  `entries` by `getfield`, so these names *are* the domain's reference
  vocabulary. Choose them deliberately; renaming one later breaks stored
  references. See the `Document` contract in
  [document/DocumentInterface.jl](../../source/kernel/document/DocumentInterface.jl).
- `CellVector` wraps a `Vector{Cell}` reactively; length changes invalidate
  downstream computed cells. `BookmarkList("My Bookmarks", [BookmarkEntry("t", "u"), …])`
  builds one from a plain `Vector`. This is [Rule C](../package/kernel/macros.md#the-layout-list),
  the constructor `@document` generates for a struct with one collection field.
- See [reactive cells](../package/kernel/cell.md) and [macros](../package/kernel/macros.md)
  for the cell system and the `@document` macro.

---

## Step 2: The package root

A domain package's root module does two things: it binds every submodule of
the packages this slice's `using ..XxxModule` lines reach into as a local
`const` (so `..CollectionModule` inside `BookmarkModule` resolves to something),
and it includes the slice's module file. Create
`package/ProjecturedBookmark/Project.toml` (a fresh UUID; `[deps]` on the
engine and platform packages named below) and
`package/ProjecturedBookmark/src/ProjecturedBookmark.jl`:

```julia
module ProjecturedBookmark

using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/bookmark/Bookmark.jl")

# The names of the domain at the level of the package.
using .BookmarkModule
for _n in names(BookmarkModule)
    _n === :BookmarkModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

end # module ProjecturedBookmark
```

The loop is what lets `BookmarkModule` write `using ..CollectionModule` and
have it resolve: it walks each dependency package (`ProjecturedPlatform`,
…), finds every submodule that package defines or re-exports, and binds it as
a `const` of the same name here — so `..CollectionModule` inside a submodule
of `ProjecturedBookmark` finds the `const CollectionModule = ProjecturedPlatform.CollectionModule`
the loop wrote. `parentmodule(_m) !== Main` is what keeps a package's own
re-exported aliases of a *lower* package from being bound twice. The second loop
exports the names of `BookmarkModule` from the package, so that
`using ProjecturedBookmark` gives `BookmarkList`. Every real
domain package's root module is these same two loops with a different dependency
tuple, a different `include` and a different module — compare
[package/ProjecturedJSON/src/ProjecturedJSON.jl](../../package/ProjecturedJSON/src/ProjecturedJSON.jl).

Because the aliases are written by a loop rather than `const` lines a reader
can grep, the static layering guard cannot read them off the file; it measures
the set from the loaded package instead (see [domain-inventory.md](../design/domain-inventory.md#the-root-module)).

---

## Step 3: Write the projection (printer)

Create `source/bookmark/BookmarkToSyntax.jl`. The projection is part of the
same slice, so the file is a fragment of `BookmarkModule`: it declares no
module of its own, and its `using` lines and exports belong to the module file
(Step 4 adds them).

Write it with [`@projection_template`](../package/kernel/macros.md#projection_template)
rather than a hand-written `print_document`/`map_reference_forward`/
`map_reference_backward` group. It is how most structural projections here are
written, and it generates the reference mapping and the reader for you.

A domain declares a theme for its fonts and its colors, and a projection never
holds one as a literal value: it reads the theme instead, through a small
helper that every projection of the domain shares. Each colour of the theme
names a role of the colour theme, such as `:definition` or `:link`
([style.md](../package/platform/style/style.md#colours)), and not a fixed
colour: the style guard that `test_style()` runs over `source/` fails on a
`@theme` declaration that names a fixed palette colour instead (see
[testing-guide.md](testing-guide.md#the-style-guard)). `BookmarkTheme` holds
the base font and the two text roles that color a title and an address:

```julia
# ──────────────────────────────────────────────────────────────────────────
# The theme of the domain. A real domain keeps it in its own fragment file,
# such as `JsonTheme.jl`; this tutorial keeps everything in one file.

"""
    BookmarkTheme

The colors and the fonts of a list of bookmarks: a title and an address.

`@theme` declares it, so `ScaledBookmarkTheme` holds each value times its scale.
"""
@theme struct BookmarkTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The title of a bookmark."
    title_text::TextRole = TextRole(:definition; weight = 700)
    "The address of a bookmark."
    url_text::TextRole = TextRole(:link)
end
```

`TextRole(:definition; weight = 700)` is `TextRole(ColorRole(:definition); weight = 700)`:
the bold weight of the title is its own, and its colour is the role
`definition` of the colour theme, the name of a declared thing. `url_text`
takes the role `link`, the role of a link, a URL and a cross-reference.
Naming a role, and not a fixed colour, is what lets the colour settings of the
appearance — the mode, the palette, the accent and the rest — recolour a
bookmark with every other domain.

The texts are roles over the base font `font`, so a person who changes the
family or the size of `font` changes both. A projection holds a `StyleText`:
the theme gives the text that each role gives. `@theme` also writes and exports
`get_bookmark_style(theme, name)`, which gives the style of the field `name`: a
cell that reads a `BookmarkTheme`, scaled or not, or the plain value of the
default theme for `nothing`.

The two projections below hold their styles and no theme, and the factory
`BookmarkToSyntax` gives them the styles of their roles, the same shape that
[`JsonTheme.jl`](../../source/domain/json/JsonTheme.jl) and
[`JsonToSyntax.jl`](../../source/domain/json/JsonToSyntax.jl) use for `JsonTheme`.
Nothing in a projection scales or asks whether a theme is scaled:

```julia
# ──────────────────────────────────────────────────────────────────────────
# Bookmark → Syntax projection. Renders each BookmarkEntry as a two-leaf
# SyntaxNode (title, url), and a BookmarkList as a SyntaxNode whose children
# are the entry nodes.

@projection UntrackedCell struct BookmarkEntryToSyntaxNode
    title_style::StyleText = get_bookmark_style(nothing, :title_text)
    url_style::StyleText   = get_bookmark_style(nothing, :url_text)
end

@projection_template BookmarkEntryToSyntaxNode BookmarkEntry (p, entry) ->
    SyntaxNode(TextString("", p.title_style), TextString("", p.url_style), TextString("   ", p.title_style),
        [ SyntaxLeaf(bound(:title, String, TextString(() -> entry.title, p.title_style)); open = TextString("- ", p.title_style)),
          SyntaxLeaf(bound(:url, String, TextString(() -> entry.url, p.url_style))) ],
        0, false, nothing)

@projection UntrackedCell struct BookmarkListToSyntaxNode
    sep_style::StyleText = get_bookmark_style(nothing, :title_text)
end

@projection_template BookmarkListToSyntaxNode BookmarkList (p, list) ->
    SyntaxNode(collection(:entries); sep = TextString("\n", p.sep_style))

function BookmarkToSyntax(; theme = nothing)
    get_style(name) = get_bookmark_style(theme, name)
    RecursiveProjection(TypeDispatchingProjection(
        BookmarkEntry => BookmarkEntryToSyntaxNode(; title_style = get_style(:title_text),
                                                   url_style = get_style(:url_text)),
        BookmarkList  => BookmarkListToSyntaxNode(; sep_style = get_style(:title_text)),
    ))
end
```

With no `theme`, each projection holds the plain values of the default
`BookmarkTheme`, so `BookmarkToSyntax()` works with no argument, and a
`BookmarkTheme()` draws at no scale. A caller that holds an `Appearance` passes
`theme = get_scaled_theme!(appearance, BookmarkTheme)` instead, and the view
then follows the scales and the edits of the appearance tab; see
[style.md](../package/platform/style/style.md#themes-and-the-appearance).

`bound(:title, String, render)` marks the first leaf as holding
`entry.title`'s value, drawn by `render`; a cursor there maps back to
`.title{k}` with no code of your own. `collection(:entries)` marks the list's
children as `list.entries`, each projected through the type dispatcher above.
This is what recurses into every `BookmarkEntry` and keeps its own selection
mapping working underneath the list's. Checked in a real session:

```julia
julia> list = BookmarkList("My Bookmarks",
           [BookmarkEntry("Julia", "https://julialang.org"),
            BookmarkEntry("ProjecturEd", "https://github.com/projectured/projectured")]);

julia> iomap = print_document(BookmarkToSyntax(), list);

julia> typeof(iomap.output)
SyntaxNode{…}

julia> length(iomap.output.children)
2

julia> set_selection!(list, @reference(list, entries[1].title{2})); iomap = print_document(BookmarkToSyntax(), list);

julia> iomap.output.selection   # forward-mapped with no mapper of your own
::SyntaxNode.children::CellVector[1]::SyntaxNode.children::CellVector[1]::SyntaxLeaf.value::TextString{2}::Position
```

**Key points:**
- `print_document` (which the macro generates for you) always returns an
  `IoMap`, not just the output document; `@projection_template` wires this
  internally through `TemplateIoMap`.
- Reference mapping in both directions, and the reader, come from the
  markers — you never write `map_reference_forward`, `map_reference_backward`,
  or `read_intent` for a projection the template can express.
- `RecursiveProjection(TypeDispatchingProjection(...))` is the standard
  pattern for domains with multiple document types.
- A font, a color or a fixed length written inside a projection, outside a
  `@theme` declaration, fails the style guard that `test_style()` runs over
  `source/`; see [testing-guide.md](testing-guide.md#the-style-guard). A value
  that a document's own author sets, such as a width that an example passes
  to one widget, is content and not a style, and the line that sets it carries
  the marker `# @style: content of the document`.
- See [macros.md](../package/kernel/macros.md#projection_template) for the
  full marker-word table (`bound`, `project`, `collection`, `tokens`,
  `sections`) and [the projection system guide](../package/kernel/projection-system.md).

### When the template is not enough

A projection writes a hand-rolled `print_document`/`map_reference_forward`/
`map_reference_backward` group instead when it must introduce output
structure the template's markers cannot express: a caret on a delimiter with
no field behind it, for instance. `XmlElementToSyntaxNode` does this for its
`<`/`>`/`</` chrome; see
[source/domain/xml/XmlToSyntax.jl](../../source/domain/xml/XmlToSyntax.jl). Reach for
`@projection_template` first, and drop to a hand-written pair only for the one
piece it cannot cover — most domains, Bookmark included, never need to.

---

## Step 4: Include the projection in the module file

The module file includes the fragment, after the document types it needs, and
exports what it defines:

```julia
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..ProjectionModule
using ..ProjectionAlgebraModule

export BookmarkTheme, ScaledBookmarkTheme
export BookmarkEntryToSyntaxNode, BookmarkListToSyntaxNode, BookmarkToSyntax

include("BookmarkToSyntax.jl")
```

Add the five `using` lines and the two `export` lines to `BookmarkModule`'s
header (alongside the four Step 1 already added), and
`include("BookmarkToSyntax.jl")` after `include`-ing nothing else — Bookmark
has only the one fragment.

---

## Step 5: Add an example

Create `example/bookmark/BookmarkDocumentExample.jl`:

```julia
function make_bookmark_document_example()
    list = BookmarkList("My Bookmarks", [
        BookmarkEntry("Julia programming language", "https://julialang.org"),
        BookmarkEntry("ProjecturEd on GitHub",
                      "https://github.com/projectured/projectured"),
        BookmarkEntry("JuliaHub",                  "https://juliahub.com"),
    ])
    set_selection!(list, @reference(list, entries[1]))
    list
end
```

Create `example/bookmark/BookmarkProjectionExample.jl`:

```julia
function make_bookmark_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(BookmarkToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
```

Both files belong to the example package,
`package/ProjecturedBookmarkExample/` — its own `Project.toml`, depending on
`ProjecturedBookmark` plus whatever the two functions above name directly
(`ProjecturedPlatform` for `FontFileMeasure`). Its root module needs the
same alias loop as Step 2, over its own dependency tuple, before the two
`include`s:

```julia
module ProjecturedBookmarkExample

using ProjecturedBookmark
using ProjecturedKernelExample
using ProjecturedPlatform

for _src in (ProjecturedBookmark, ProjecturedKernelExample)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../example/bookmark/BookmarkDocumentExample.jl")
include("../../../example/bookmark/BookmarkProjectionExample.jl")
export make_bookmark_document_example, make_bookmark_projection_example

end # module ProjecturedBookmarkExample
```

In `example/projectured/DomainExamples.jl`, add:

```julia
const bookmark_example = Example("bookmark",
    make_bookmark_document_example, make_bookmark_projection_example)
```

And add `bookmark_example` to the `domain_examples` vector in that same file,
and to the `examples` vector in `example/projectured/ProjecturedExamples.jl`.
Both lists are hand-written.

---

## Step 6: Write a test

Create `test/bookmark/projection/BookmarkToSyntaxTest.jl`:

```julia
function test_bookmark_to_syntax()

@testset "BookmarkEntry → SyntaxNode" begin
    entry = BookmarkEntry("Julia", "https://julialang.org")
    iomap = print_document(BookmarkEntryToSyntaxNode(), entry)
    node = iomap.output
    @test node isa SyntaxNode
    # two children: title leaf and url leaf. SyntaxNode's children field is
    # `children`, and a SyntaxLeaf's `value` is a TextString — read `.content`
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

In `package/ProjecturedBookmarkTest/src/ProjecturedBookmarkTest.jl`, the same
alias-loop shape again — over `ProjecturedBookmark`,
`ProjecturedBookmarkExample`, `ProjecturedKernelTest` and
`ProjecturedPlatformTest` (for `@testset`, `ChildrenIoMap`, and the shared
drivers) — then:

```julia
include("../../../test/bookmark/projection/BookmarkToSyntaxTest.jl")
include("../../../test/bookmark/BookmarkSuite.jl")
```

Create `test/bookmark/BookmarkSuite.jl` with the aggregator of the package. It
calls the layering guard first, then every test of the domain:

```julia
function test_bookmark()
    @testset "ProjecturedBookmark" begin
        test_bookmark_layering()
        test_bookmark_to_syntax()
    end
end
```

Define `test_bookmark_layering()` in that same file. Copy the shape from
[test/domain/json/JsonSuite.jl](../../test/domain/json/JsonSuite.jl): it calls
`check_layering` on the source root of the package, and the call fails when a
file names a module that its layer may not reach.

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

- **Character editing:** already works. A `ReplaceStringRangeOperation` on a
  leaf's value flows back through the default reader `@projection_template`
  generated, which re-targets its reference through the `bound(:title, …)` /
  `bound(:url, …)` markers. No extra `read_intent` needed.
- **Structural editing:** `make_insert_elements_operation` (a `ReplaceReferencedValueOperation` splice) to
  append bookmarks. This *does* need a `read_intent` method, since it is more than a
  reference re-target.
- **A custom operation:** e.g. `BookmarkOpenOperation` that opens the URL
  in a browser when Enter is pressed.
- **The theme in the appearance tab:** `BookmarkTheme` of Step 3 already
  makes the view follow the scales of the appearance and lets a person change
  its colors and its fonts there, once a builder passes
  `theme = get_scaled_theme!(appearance, BookmarkTheme)` to `BookmarkToSyntax`.
  A card for `BookmarkTheme` then shows in the appearance tab, with the
  docstring of each field under its name; the first paragraph of the
  docstring of the type is the summary at the top of the card.

For the next level of complexity, such as a domain with cross-references, a
custom reader that handles structural events, or a projection whose output
document draws itself directly rather than going through Syntax, read
[the projection system guide](../package/kernel/projection-system.md)
and look at `MathToSyntax.jl` as a real-world reference; its arithmetic
precedence/parenthesization is exactly the kind of structural rewrite
`@projection_template` alone cannot express.
