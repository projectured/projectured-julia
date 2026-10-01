# ═══════════════════════════════════════════════════════════════════════════
# test/projection/ReferenceInspectorTest.jl
#
# test_reference_inspector_text: ReferenceInspector → TextBlock renders both the
# compact and human-readable sections (and a "no target" line for a nothing
# reference).
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedPlatform.TextModule: TextBlock, TextString

_inspector_text(ref, target) =
    print_document(ReferenceInspectorToText(),
                     ReferenceInspector(reference = ref, target = target)).output

# Concatenate the plain content of every TextString span (skips newlines).
function _flatten_text(tt::TextBlock)
    io = IOBuffer()
    for i in 1:length(tt.elements)
        s = tt.elements[i]
        s isa TextString && print(io, s.content)
    end
    String(take!(io))
end

"""
    test_reference_inspector_text()

ReferenceInspector renders to a labelled two-section TextBlock.
"""
function test_reference_inspector_text()
    @testset "ReferenceInspectorToText" begin
        ex = json_example
        doc = ex.document
        ref = Reference(FieldReferenceStep("entries"), ElementReferenceStep(1))

        out = _inspector_text(ref, doc)
        @test out isa TextBlock
        flat = _flatten_text(out)
        @test occursin("Compact", flat)
        @test occursin("Human-readable", flat)
        # The compact form prints field/element tokens of the reference.
        @test occursin("entries", flat)
        # The reference is annotated, so the compact form shows ::Type
        # checkpoints and the human-readable form chains rows with "which is".
        @test occursin("::", flat)
        @test occursin("which is", flat)

        # A nothing reference degrades gracefully (no crash, still a TextBlock).
        none = _inspector_text(nothing, doc)
        @test none isa TextBlock
        @test occursin("Compact", _flatten_text(none))

        # The full follower-window content chain (the one the dispatcher runs
        # for a ReferenceInspector window) must bottom out in a GraphicsCanvas —
        # that is what the window reconciler requires.
        chain = ChainingProjection(ReferenceInspectorToText(),
                                     WordWrapping(measure = FontFileMeasure()),
                                     TextToGraphics(measure = FontFileMeasure()))
        canvas = print_document(chain, ReferenceInspector(reference = ref, target = doc)).output
        @test canvas isa GraphicsCanvas
    end
end
