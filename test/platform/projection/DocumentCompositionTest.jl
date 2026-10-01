# The seams by which a package that owns a type of document joins the natural
# renderer and the editor with no dependency on them: `make_graphics_projection`
# of Widget, and the default projection that Natural gives to `build_editor`.

import ProjecturedKernel.DocumentModule: Document
import ProjecturedKernel.ProjectionModule: Projection
import ProjecturedKernel.IoMapModule: SimpleIoMap
import ProjecturedKernel.EditorModule: make_document_projection
import ProjecturedPlatform.WidgetModule: make_graphics_projection,
                                       collect_graphics_projection_types
import ProjecturedPlatform.NaturalModule: NaturalToGraphics
import ProjecturedPlatform.StyleModule: FontFileMeasure

# A kind of document with a projection of its own, and one member of the kind
# with a projection of its own too.
abstract type CompositionProbeKind <: Document end
struct CompositionLeafProbe <: CompositionProbeKind end
struct CompositionOtherProbe <: CompositionProbeKind end

# A projection that draws a text that names it, in place of graphics.
struct CompositionProbeProjection <: Projection
    name::String
end
ProjecturedKernel.ProjectionModule.print_document(p::CompositionProbeProjection, recursion,
                                                 input, ctx) =
    SimpleIoMap(p, input, p.name)

make_graphics_projection(::Type{<:CompositionProbeKind}; measure, appearance) =
    CompositionProbeProjection("the kind")
make_graphics_projection(::Type{CompositionLeafProbe}; measure, appearance) =
    CompositionProbeProjection("the leaf")

function test_document_composition()
@testset "the seams of a type of document" begin
    @testset "a type comes before its supertype" begin
        types = collect_graphics_projection_types()
        leaf = findfirst(==(CompositionLeafProbe), types)
        kind = findfirst(==(CompositionProbeKind), types)
        @test leaf !== nothing && kind !== nothing && leaf < kind
    end

    @testset "the natural renderer draws a type with the projection of its seam" begin
        renderer = NaturalToGraphics(measure = FontFileMeasure())
        @test print_document(renderer, CompositionLeafProbe()).output == "the leaf"
        @test print_document(renderer, CompositionOtherProbe()).output == "the kind"
    end

    @testset "with Natural loaded, a document has a default projection" begin
        @test make_document_projection(CompositionLeafProbe()) isa Projection
    end
end
end
