# Regression for the `@projection_template` import-hygiene fix.
#
# `@projection_template` must register its `print_document` method on the
# *canonical* `ProjectionApiModule.print_document` generic — the one the
# type-dispatcher calls — regardless of whether the calling module imported
# `print_document` into its own scope. A projection module that imports the
# markers but forgets `print_document` used to silently define a dead local
# generic, and dispatch later failed with a confusing `MethodError`.
#
# This probe module deliberately does NOT import `print_document`.
module _ProjectionTemplateHygieneProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionApiModule: Projection
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionTemplateModule: var"@projection_template"
    import ProjecturedVisual.SyntaxModule: SyntaxLeaf
    import ProjecturedVisual.TextModule: TextString
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
