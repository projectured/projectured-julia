"""
Tests for **embeds in the shared to-syntax fabric** — a marker that has
been forced renders as the document it evaluated to, in that
document's own domain, and the caret walks into it and back out.

The two directions are deliberately different projections and both are
asserted here: the fabric (`natural_to_syntax_dispatch`) renders an
embed inline, the domain projection alone (`document_to_text`, the save
path) renders only the marker.
"""

using Test
using ProjecturedDomain.CellModule: Cell
using ProjecturedDomain.FileProjectModule
using ProjecturedDomain.MarkdownFileModule
using ProjecturedDomain.MarkdownModule: MarkdownDocument, MarkdownRoot
using ProjecturedDomain.MarkdownToSyntaxModule: MarkdownToSyntax
using ProjecturedDomain.NaturalProjectionModule: natural_to_syntax_dispatch
using ProjecturedDomain.TypeDispatchingProjectionModule: TypeDispatchingProjection
using ProjecturedDomain.RecursiveProjectionModule: RecursiveProjection
using ProjecturedDomain.ChainingProjectionModule: ChainingProjection
using ProjecturedDomain.SyntaxToTextModule: SyntaxToText
using ProjecturedDomain.TextToStringModule: TextToString
using ProjecturedDomain.ProjectionApiModule: print_document, map_reference_backward
using ProjecturedDomain.ReferenceModule: ConcreteReference, FieldReferenceStep,
                                         RangeReferenceStep, EmptyReference
using ProjecturedDomain.SelectionModule: set_selection!, get_selection
using ProjecturedDomain.NaturalFormatModule: document_to_text

const _ME_STEPS = "function packet_queue_step(x)\n    return x + 1\nend\n"
const _ME_PAGE  = "# Step\n\nProse before.\n\n```pred-ref\n" *
                  "<<definition(file(\"steps.jl\"), \"packet_queue_step\")>>\n```\n\nProse after.\n"

_me_fabric() = RecursiveProjection(TypeDispatchingProjection(natural_to_syntax_dispatch()))

_me_rendered_text(document) =
    String(print_document(ChainingProjection(_me_fabric(),
                                             RecursiveProjection(SyntaxToText()),
                                             RecursiveProjection(TextToString())),
                          document).output)

# Write a page + the file it embeds into a fresh directory, load it, and
# hand the caller the loaded MarkdownFile.
function _me_project(f, page::AbstractString = _ME_PAGE)
    d = mktempdir()
    try
        write(joinpath(d, "steps.jl"), _ME_STEPS)
        write(joinpath(d, "page.md"), page)
        write(joinpath(d, "data.json"), "{\"a\": 1}")
        f(load_project(MarkdownFile, "page.md", d), d)
    finally
        rm(d; recursive=true, force=true)
    end
end

_me_stub_index(md) = findfirst(e -> (e isa Cell ? e[] : e) isa ReferenceStub,
                               collect(getfield(md, :elements)[]))

function test_markdown_embed()
@testset "Markdown embeds: render inline, save by marker, caret descends" begin

    @testset "an unforced embed renders as its marker" begin
        _me_project() do page, d
            text = _me_rendered_text(content(page))
            @test occursin("<<definition(file(\"steps.jl\"), \"packet_queue_step\")>>", text)
            @test occursin("Prose before.", text)
        end
    end

    @testset "a forced embed renders the embedded document, in its own domain" begin
        _me_project() do page, d
            resolve_stubs!(page)
            text = _me_rendered_text(content(page))
            @test occursin("function packet_queue_step(x)", text)
            @test !occursin("<<definition", text)
            # The prose around it is untouched.
            @test occursin("Prose before.", text)
            @test occursin("Prose after.", text)
        end
    end

    @testset "embedding a whole file shows the file's content" begin
        _me_project("Raw:\n\n```pred-ref\n<<file(\"data.json\")>>\n```\n") do page, d
            resolve_stubs!(page)
            text = _me_rendered_text(content(page))
            @test occursin("\"a\"", text)
            @test !occursin("<<file", text)
        end
    end

    @testset "the save path stays by-marker, forced or not" begin
        _me_project() do page, d
            before = document_to_text(content(page))
            resolve_stubs!(page)
            after = document_to_text(content(page))
            @test before == after
            @test occursin("```pred-ref", after)
            @test occursin("<<definition(file(\"steps.jl\"), \"packet_queue_step\")>>", after)
            @test !occursin("function packet_queue_step", after)
        end
    end

    @testset "the domain projection alone renders a stub in both styles" begin
        _me_project() do page, d
            resolve_stubs!(page)
            for style in (:source, :rendered)
                chain = ChainingProjection(RecursiveProjection(MarkdownToSyntax(style = style)),
                                           RecursiveProjection(SyntaxToText()),
                                           RecursiveProjection(TextToString()))
                text = String(print_document(chain, content(page)).output)
                @test occursin("<<definition(", text)
            end
        end
    end

    @testset "the caret descends into the embed and maps back out" begin
        _me_project() do page, d
            resolve_stubs!(page)
            md = content(page)
            i  = _me_stub_index(md)
            @test i !== nothing
            # `.resolved` is the structural step into the embed; the tail is a
            # path in the embedded document's own domain.
            path = ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(RangeReferenceStep(i - 1, i),
                     ConcreteReference(FieldReferenceStep("resolved"),
                      ConcreteReference(FieldReferenceStep("name"), EmptyReference()))))
            set_selection!(md, path)
            # The embedded document received its own suffix …
            stub = (e = collect(getfield(md, :elements)[])[i]; e isa Cell ? e[] : e)
            @test get_selection(stub.resolved) !== nothing
            # … the printed syntax carries the forward-projected selection …
            fabric = _me_fabric()
            iomap  = print_document(fabric, md)
            forward = iomap.output.selection
            @test forward !== nothing
            # … and it maps back to exactly the path we selected.
            @test map_reference_backward(iomap.projection, iomap, forward) == get_selection(md)
        end
    end

    @testset "an unforced embed has no interior to project into" begin
        _me_project() do page, d
            md = content(page)
            i  = _me_stub_index(md)
            path = ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(RangeReferenceStep(i - 1, i),
                     ConcreteReference(FieldReferenceStep("resolved"), EmptyReference())))
            # `.resolved` reads `nothing` on an unforced stub, so the path is
            # storable but projects to nothing — the marker is a leaf with no
            # interior, and the printer says so instead of inventing a position.
            set_selection!(md, path)
            iomap = print_document(_me_fabric(), md)
            @test iomap.output.selection === nothing
            @test occursin("<<definition(", _me_rendered_text(md))
        end
    end

end
end
