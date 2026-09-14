# Regression for the `@projection_template` import-hygiene fix.
#
# `@projection_template` must register its `print_document` method on the
# *canonical* `ProjectionModule.print_document` generic — the one the
# type-dispatcher calls — regardless of whether the calling module imported
# `print_document` into its own scope. A projection module that imports the
# markers but forgets `print_document` used to silently define a dead local
# generic, and dispatch later failed with a confusing `MethodError`.
#
# This probe module deliberately does NOT import `print_document`.
module _ProjectionTemplateHygieneProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, ComputedCell
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionTemplateModule: var"@projection_template"
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf
    import ProjecturedText.TextModule: TextString
    # print_document intentionally NOT imported.

    @document struct ProbeDoc <: Document
        text::String
    end
    ProbeDoc(t::AbstractString) = ProbeDoc(Cell(String(t)), Cell(nothing))

    @projection struct ProbeToLeaf <: Projection end
    @projection_template ProbeToLeaf ProbeDoc (p, doc) -> SyntaxLeaf(TextString("ok"))
end

function test_projection_template_hygiene()
    @testset "ProjectionTemplate import hygiene" begin
        P = _ProjectionTemplateHygieneProbe
        # The macro must not have created a dead local generic in the probe module.
        @test !isdefined(P, :print_document)
        # The template method dispatches via the canonical generic, even though
        # the probe module never imported `print_document`.
        tdp = TypeDispatchingProjection(P.ProbeDoc => P.ProbeToLeaf())
        out = print_document(RecursiveProjection(tdp), P.ProbeDoc("hi")).output
        @test out isa SyntaxLeaf
    end
end

# A fixed-children blueprint, written both ways: with the long positional constructor
# (children stored as a raw Vector) and with the ordinary one (children coerced into a
# CellVector). The engine must walk both — recognising only the raw Vector is what used
# to force every fixed-children template node into the 7-arg positional form, and made
# `SyntaxNode([...])` / `SyntaxConcatenation([...])` reach the printer with their markers
# unresolved (it reads `.content` off a `Bound` and dies).
module _FixedChildrenBlueprintProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, ComputedCell
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection, print_document
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionTemplateModule: var"@projection_template", bound
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxConcatenation, SyntaxDocument
    import ProjecturedText.TextModule: TextString
    import ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
    import ProjecturedStyle.StyleModule: color_default

    @document struct Pair2 <: Document
        a::String
        b::String
    end

    _leaves(doc) = SyntaxDocument[
        SyntaxLeaf(bound(:a, String, TextString(() -> doc.a, font_ubuntu_monospace_regular_20, color_default))),
        SyntaxLeaf(bound(:b, String, TextString(() -> doc.b, font_ubuntu_monospace_regular_20, color_default)))]

    # The long positional form: children land in the field as a raw Vector.
    @projection struct PairToNode <: Projection end
    @projection_template PairToNode Pair2 (p, doc) ->
        SyntaxNode(nothing, nothing, nothing, _leaves(doc), 0, false, nothing)

    # The form a domain actually wants to write: children coerced into a CellVector.
    @projection struct PairToConcat <: Projection end
    @projection_template PairToConcat Pair2 (p, doc) -> SyntaxConcatenation(_leaves(doc))

    @projection struct PairToKwNode <: Projection end
    @projection_template PairToKwNode Pair2 (p, doc) -> SyntaxNode(_leaves(doc); sep="-")
end

function test_projection_template_fixed_children()
    @testset "ProjectionTemplate fixed children, however the node was built" begin
        P = _FixedChildrenBlueprintProbe
        render_with(proj) = begin
            tdp = TypeDispatchingProjection(P.Pair2 => proj)
            render(print_document(RecursiveProjection(tdp), P.Pair2("hello", "world")).output)
        end
        # All three are the same blueprint; only the constructor differs.
        @test render_with(P.PairToNode())   == "helloworld"   # raw Vector (worked before)
        @test render_with(P.PairToConcat()) == "helloworld"   # CellVector, no chrome
        @test render_with(P.PairToKwNode()) == "hello-world"  # CellVector, with a separator
    end
end
