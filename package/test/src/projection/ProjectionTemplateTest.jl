using Test
using Projectured

# Regression for the `@projection_template` import-hygiene fix.
#
# `@projection_template` must register its `projection_print` method on the
# *canonical* `ProjectionApiModule.projection_print` generic — the one the
# type-dispatcher calls — regardless of whether the calling module imported
# `projection_print` into its own scope. A projection module that imports the
# markers but forgets `projection_print` used to silently define a dead local
# generic, and dispatch later failed with a confusing `MethodError`.
#
# This probe module deliberately does NOT import `projection_print`.
module _ProjectionTemplateHygieneProbe
    import Projectured: Document, var"@document", Cell, Reference, Projection,
                        var"@projection", var"@projection_template",
                        SyntaxLeaf, TextString
    # projection_print intentionally NOT imported.

    @document struct ProbeDoc <: Document
        text::String
        selection::Reference
    end
    ProbeDoc(t::AbstractString) = ProbeDoc(Cell(String(t)), Cell(nothing))

    @projection struct ProbeToLeaf <: Projection end
    @projection_template ProbeToLeaf ProbeDoc (p, doc) -> SyntaxLeaf(TextString("ok"))
end

function test_projection_template_hygiene()
    @testset "ProjectionTemplate import hygiene" begin
        P = _ProjectionTemplateHygieneProbe
        # The macro must not have created a dead local generic in the probe module.
        @test !isdefined(P, :projection_print)
        # The template method dispatches via the canonical generic, even though
        # the probe module never imported `projection_print`.
        tdp = TypeDispatchingProjection(P.ProbeDoc => P.ProbeToLeaf())
        out = projection_print(RecursiveProjection(tdp), P.ProbeDoc("hi")).output
        @test out isa SyntaxLeaf
    end
end
