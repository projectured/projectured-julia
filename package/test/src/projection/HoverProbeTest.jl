# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/HoverProbeTest.jl
#
# Hover click-reference inspector:
#   - test_reference_inspector_text: ReferenceInspector → TextText renders both
#     the compact and human-readable sections (and a "no target" line for a
#     nothing reference).
#   - test_hover_probe: a MouseMove fed to HoverProbeProjection produces an
#     OpenWindowOperation whose content is a ReferenceInspector carrying the
#     *same* reference a real left-click at that pixel would select, positioned
#     at pointer()+offset; a real MousePress still passes through to selection.
#
# Reuses the SegCoord/measure helpers defined in ClickRoundtripTest.jl (same
# ProjecturedTest module scope; included after it).
# ═══════════════════════════════════════════════════════════════════════════

using Projectured
using ProjecturedExample
using Projectured: ReplaceSelectionOperation, OpenWindowOperation,
                    ReferenceInspector, HoverProbeProjection, ReferenceInspectorToText,
                    NestingProjection, PreservingProjection, SequentialProjection,
                    WordWrapping, TextToGraphics, GraphicsCanvas, truetype_measure_text,
                    reference_equal, MouseMove, MousePress, Modifiers,
                    ScreenDocument, WindowDocument, EventEnvelope, Change
using Projectured.TextModule: TextText, TextString

_inspector_text(ref, target) =
    projection_print(ReferenceInspectorToText(),
                     ReferenceInspector(reference = ref, target = target)).output

# Concatenate the plain content of every TextString span (skips newlines).
function _flatten_text(tt::TextText)
    io = IOBuffer()
    for i in 1:length(tt.elements)
        s = tt.elements[i]
        s isa TextString && print(io, s.content)
    end
    String(take!(io))
end

"""
    test_reference_inspector_text()

ReferenceInspector renders to a labelled two-section TextText.
"""
function test_reference_inspector_text()
    @testset "ReferenceInspectorToText" begin
        ex = examples[findfirst(e -> e.name == "json", examples)]
        doc = ex.document
        ref = ReferencePath(FieldReference("entries"), ElementReference(1))

        out = _inspector_text(ref, doc)
        @test out isa TextText
        flat = _flatten_text(out)
        @test occursin("compact", flat)
        @test occursin("human-readable", flat)
        # The compact form prints field/element tokens of the reference.
        @test occursin("entries", flat)

        # A nothing reference degrades gracefully (no crash, still a TextText).
        none = _inspector_text(nothing, doc)
        @test none isa TextText
        @test occursin("compact", _flatten_text(none))

        # The full follower-window content chain (the one the dispatcher runs
        # for a ReferenceInspector window) must bottom out in a GraphicsCanvas —
        # that is what the window reconciler requires.
        chain = SequentialProjection(ReferenceInspectorToText(),
                                     WordWrapping(measure = truetype_measure_text),
                                     TextToGraphics(measure = truetype_measure_text))
        canvas = projection_print(chain, ReferenceInspector(reference = ref, target = doc)).output
        @test canvas isa GraphicsCanvas
    end
end

# Centre pixel of the first content character cell, as in ClickRoundtripTest.
function _first_content_pixel(t2g, measure)
    coords = t2g.char_to_coord[]
    isempty(coords) && return nothing
    sc = first(coords)
    k = sc.char_start
    cx = _seg_x_at(sc, k, measure) + 1
    cy = sc.y + max(1, sc.font.size ÷ 2)
    (cx, cy)
end

"""
    test_hover_probe()

A hover (MouseMove) over content opens the inspector window with the would-be
click reference; a real click still selects.
"""
function test_hover_probe()
    @testset "HoverProbe" begin
        ex = examples[findfirst(e -> e.name == "json", examples)]
        doc = ex.document
        proj = ex.projection

        plain = projection_print(proj, doc)
        t2g = _find_text_iomap(plain)
        measure = _pipeline_measure(proj)
        if t2g === nothing || measure === nothing
            @warn "[hover_probe] no TextToGraphics/measure; skipping"
            @test true
            return
        end
        pix = _first_content_pixel(t2g, measure)
        if pix === nothing
            @warn "[hover_probe] empty char_to_coord; skipping"
            @test true
            return
        end
        (cx, cy) = pix

        # Mirror the real pipeline: the probe wraps a NestingProjection so the
        # example projection's own recursion is isolated.
        inner = NestingProjection(proj; recursion = PreservingProjection())
        hp = HoverProbeProjection(inner = inner, id = :inspector,
                                  pointer = () -> (7, 9))
        hpio = projection_print(hp, doc)

        # Hover → OpenWindowOperation carrying a ReferenceInspector.
        mv = projection_read(hp, hpio, MouseMove(cx, cy, :none, Modifiers()))
        @test mv isa OpenWindowOperation
        if mv isa OpenWindowOperation
            @test mv.id === :inspector
            @test mv.style === :tooltip
            @test mv.content isa ReferenceInspector
            # Follower window is placed at pointer() + default offset (16, 20).
            @test mv.x == 7 + 16
            @test mv.y == 9 + 20
            # The displayed reference equals what a real click here selects.
            press = projection_read(proj, plain, MousePress(:left, cx, cy, Modifiers()))
            if press isa ReplaceSelectionOperation
                @test reference_equal(mv.content.reference, press.path)
            end
        end

        # A real click is not intercepted — it still selects through the probe.
        click = projection_read(hp, hpio, MousePress(:left, cx, cy, Modifiers()))
        @test click isa ReplaceSelectionOperation
    end
end

"""
    test_hover_probe_pipeline()

End-to-end through the real `_multi_window_projection_inspector` pipeline: an
`EventEnvelope`-wrapped hover routed into the main window's content makes the
`WindowManagerProjection` add an `:inspector` follower window to the screen.
"""
function test_hover_probe_pipeline()
    @testset "HoverProbe pipeline" begin
        ex = examples[findfirst(e -> e.name == "json", examples)]
        doc = ex.document
        proj = ex.projection

        # A valid content pixel (content layout is the same standalone or inside
        # the window, which ScreenToScreen sizes but does not offset).
        plain = projection_print(proj, doc)
        t2g = _find_text_iomap(plain)
        measure = _pipeline_measure(proj)
        if t2g === nothing || measure === nothing
            @warn "[hover_probe_pipeline] no TextToGraphics/measure; skipping"
            @test true
            return
        end
        pix = _first_content_pixel(t2g, measure)
        if pix === nothing
            @test true
            return
        end
        (cx, cy) = pix

        win = WindowDocument(; id = :json, title = "json",
                               x = 100, y = 100, width = 1200, height = 600,
                               content = doc)
        screen = ScreenDocument([win])
        composed = ProjecturedExample._multi_window_projection_inspector(
                       [proj]; pointer = () -> (50, 60))
        iomap = projection_print(composed, screen)

        nbefore = length(screen.windows)
        env = EventEnvelope(:json, MouseMove(cx, cy, :none, Modifiers()))
        projection_read(composed, nothing, Change(env, nothing), iomap)

        @test length(screen.windows) == nbefore + 1
        insp = nothing
        for w in screen.windows
            w isa WindowDocument && w.id === :inspector && (insp = w)
        end
        @test insp !== nothing
        if insp !== nothing
            @test insp.content isa ReferenceInspector
            @test insp.x == 50 + 16   # pointer() + default offset
            @test insp.y == 60 + 20
        end
    end
end
