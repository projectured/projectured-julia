"""
Tests for **embeds in an RST page** — the `pred-ref` directive, the card
an embedded document wears, and the two invariants the markdown slice
holds as well: a page renders as what it embeds, and saves as its marker.

RST takes one step markdown does not need. A section owns its blocks, so
an embed below the first title only reaches the widget renderer because
`RstSectionToVerticalLayout` stacks a section too.
"""

using Test
using ProjecturedKernel.CellModule: Cell, AbstractCell
using ProjecturedSerialization.FileProjectModule
using ProjecturedRst.RstFileModule
using ProjecturedRst.RstModule: RstRoot, RstSection, RstDirective
using ProjecturedRst.RstParserModule: rstparse
using ProjecturedNatural.NaturalNotationModule: print_natural_text
using ProjecturedNatural.NaturalProjectionModule: NaturalToGraphics
using ProjecturedGraphics.GraphicsModule: GraphicsCanvas
using ProjecturedKernel.ProjectionApiModule: print_document, read_intent
using ProjecturedKernel.EventModule: MousePress, KeyPress, ModifierKeys
using ProjecturedKernel.OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation,
                                         evaluate_operation
using ProjecturedPrimitive.PrimitiveModule: ReplaceStringRangeOperation
using ProjecturedKernel.ReferenceModule: FieldReferenceStep
using ProjecturedKernel.SelectionModule: set_selection!, get_selection

const _RE_PAGE = """
Title
=====

Prose before.

.. pred-ref:: <<file("data.json")>>

Prose after.
"""

# The open-card chevron the embed card's header draws.
const _RE_CHEVRON = "▾"

# Write a page and the file it embeds into a fresh directory, load it, and hand
# the caller the loaded RstFile.
function _re_project(f, page::AbstractString = _RE_PAGE)
    d = mktempdir()
    try
        write(joinpath(d, "data.json"), "{\"a\": 1}")
        write(joinpath(d, "page.rst"), page)
        f(load_project(RstFile, "page.rst", d), d)
    finally
        rm(d; recursive=true, force=true)
    end
end

_re_renderer() = NaturalToGraphics(measure = (text, _font) -> (length(text) * 10, 20))

# Every drawn string with its absolute position.
function _re_drawn(root)
    found   = Tuple{String,Int,Int}[]
    pending = Any[(root, 0, 0)]
    seen    = Set{UInt64}()
    while !isempty(pending)
        (node, ox, oy) = pop!(pending)
        while node isa AbstractCell
            node = node[]
        end
        node === nothing && continue
        id = objectid(node)
        id in seen && continue
        push!(seen, id)
        if node isa GraphicsCanvas
            for element in node.elements
                push!(pending, (element, ox + Int(node.x[]), oy + Int(node.y[])))
            end
        elseif string(typeof(node).name.name) == "GraphicsText"
            push!(found, (string(node.text), ox + Int(node.x[]), oy + Int(node.y[])))
        end
    end
    found
end

_re_texts(root) = String[t for (t, _, _) in _re_drawn(root)]

# The middle of the drawn run that reads exactly `text`, or (-1, -1) when no run
# does. Exact, because the runs overlap as substrings: the JSON key `a` is inside
# the card header's `data.json`.
function _re_position(root, text::AbstractString)
    for (drawn, x, y) in _re_drawn(root)
        drawn == text && return (x + 5, y + 5)
    end
    (-1, -1)
end

# The first ReferenceStub anywhere in the page.
function _re_stub(node)
    node isa ReferenceStub && return node
    for field in (:elements,)
        hasproperty(node, field) || continue
        for child in getproperty(node, field)
            found = _re_stub(child)
            found === nothing || return found
        end
    end
    nothing
end

function test_rst_embed()
@testset "RST embeds: a pred-ref directive, a card, and a marker on save" begin

    @testset "a pred-ref directive loads as a marker" begin
        _re_project() do page, d
            stub = _re_stub(get_file_content(page))
            @test stub isa ReferenceStub
            @test format_marker_text(stub) == "<<file(\"data.json\")>>"
            # It sits inside the section, where it was written.
            section = collect(get_file_content(page).elements)[1]
            @test section isa RstSection
            @test any(e -> e isa ReferenceStub, collect(section.elements))
        end
    end

    @testset "a directive that is not a marker stays a directive" begin
        _re_project("Title\n=====\n\n.. pred-ref:: not a marker\n") do page, d
            @test _re_stub(get_file_content(page)) === nothing
            section = collect(get_file_content(page).elements)[1]
            @test any(e -> e isa RstDirective, collect(section.elements))
        end
    end

    @testset "the page saves as its marker, forced or not" begin
        _re_project() do page, d
            before = print_natural_text(get_file_content(page))
            resolve_stubs!(page)
            after = print_natural_text(get_file_content(page))
            @test before == after
            @test occursin(".. pred-ref:: <<file(\"data.json\")>>", after)
            @test !occursin("\"a\"", after)
            # And what it wrote parses back to the same shape.
            @test rstparse(after) isa RstRoot
        end
    end

    @testset "a resolved embed is framed by a card titled after its file" begin
        _re_project() do page, d
            resolve_stubs!(page)
            drawn = _re_texts(print_document(_re_renderer(), get_file_content(page)).output)
            @test _RE_CHEVRON * " data.json" in drawn   # the card's own header
            @test "a" in drawn                          # with the JSON key inside it
            # The prose around it is untouched, and the title still reads.
            @test "Prose before." in drawn
            @test "Prose after." in drawn
            @test "Title" in drawn
        end
    end

    @testset "an unforced embed draws its marker, with no card" begin
        _re_project() do page, d
            drawn = _re_texts(print_document(_re_renderer(), get_file_content(page)).output)
            @test any(t -> occursin("<<file(\"data.json\")>>", t), drawn)
            @test !any(t -> occursin(_RE_CHEVRON, t), drawn)
        end
    end

    @testset "a click through the card reaches the embedded document" begin
        _re_project() do page, d
            resolve_stubs!(page)
            root = get_file_content(page)
            iomap = print_document(_re_renderer(), root)
            x, y = _re_position(iomap.output, "a")     # the JSON key
            @test x >= 0
            op = read_intent(iomap.projection, iomap, MousePress(:left, x, y, ModifierKeys()))
            # The path is rooted in the PAGE, through the section and the embed.
            @test op isa ReplaceSelectionOperation
            @test op.path.head == FieldReferenceStep("elements")
            set_selection!(root, op.path)
            @test get_selection(_re_stub(root).resolved) !== nothing

            # And a key typed after that click edits the embedded document.
            key = read_intent(iomap.projection, iomap, KeyPress('x', ModifierKeys()))
            @test key isa ReplaceStringRangeOperation
            @test key.reference.head == FieldReferenceStep("elements")
        end
    end

    @testset "a click on the card header folds the embed away" begin
        _re_project() do page, d
            resolve_stubs!(page)
            iomap = print_document(_re_renderer(), get_file_content(page))
            x, y = _re_position(iomap.output, _RE_CHEVRON * " data.json")
            op = read_intent(iomap.projection, iomap, MousePress(:left, x, y, ModifierKeys()))
            @test op isa ToggleCollapseOperation
            evaluate_operation(nothing, op)
            drawn = _re_texts(iomap.output)
            @test !("a" in drawn)                          # the body is gone
            @test any(t -> occursin("data.json", t), drawn)  # the header stays
        end
    end

    @testset "the section verb names an RST section" begin
        _re_project() do page, d
            ctx = LoaderContext(d)
            section = evaluate_marker("section(file(\"page.rst\"), \"Title\")", ctx)
            @test section isa RstSection
            @test rst_title_text(section) == "Title"
            @test_throws ErrorException evaluate_marker("section(file(\"page.rst\"), \"Nope\")", ctx)
        end
    end

end
end
