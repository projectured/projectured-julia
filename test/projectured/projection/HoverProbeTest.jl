# ═══════════════════════════════════════════════════════════════════════════
# test/projection/HoverProbeTest.jl
#
# Hover click-reference inspector:
#   - test_reference_inspector_text: ReferenceInspector → TextBlock renders both
#     the compact and human-readable sections (and a "no target" line for a
#     nothing reference).
#   - test_hover_probe: a MouseMove fed to HoverProbeProjection produces an
#     OpenWindowOperation whose content is a ReferenceInspector carrying the
#     *same* reference a real left-click at that pixel would select, positioned
#     at pointer()+offset; a real MousePress still passes through to selection.
#
# Reuses the SegmentCoordinate/measure helpers defined in ClickRoundtripTest.jl (same
# ProjecturedTest module scope; included after it).
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedText.TextModule: TextBlock, TextString

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
                                     WordWrapping(measure = measure_truetype_text),
                                     TextToGraphics(measure = measure_truetype_text))
        canvas = print_document(chain, ReferenceInspector(reference = ref, target = doc)).output
        @test canvas isa GraphicsCanvas
    end
end

# Centre pixel of the first content character cell, as in ClickRoundtripTest.
function _first_content_pixel(t2g, measure)
    coords = t2g.char_to_coord
    isempty(coords) && return nothing
    sc = first(coords)
    k = sc.char_start
    cx = _segment_x_at(sc, k, measure) + 1
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
        ex = json_example
        doc = ex.document
        proj = ex.projection

        plain = print_document(proj, doc)
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
        inner = NestingProjection(proj; recursion = IdentityProjection())
        hp = HoverProbeProjection(inner = inner, id = :inspector,
                                  pointer = () -> (7, 9))
        hpio = print_document(hp, doc)

        # Hover → OpenWindowOperation carrying a ReferenceInspector.
        mv = read_intent(hp, hpio, MouseMove(cx, cy, MouseButtons(), ModifierKeys()))
        @test mv isa OpenWindowOperation
        if mv isa OpenWindowOperation
            @test mv.id === :inspector
            @test mv.style === :tooltip
            @test mv.content isa ReferenceInspector
            # Follower window is placed at pointer() + default offset (16, 20).
            @test mv.x == 7 + 16
            @test mv.y == 9 + 20
            # The displayed reference equals what a real click here selects.
            press = read_intent(proj, plain, MousePress(:left, cx, cy, ModifierKeys()))
            if press isa ReplaceSelectionOperation
                @test is_reference_equal(mv.content.reference, press.path)
            end
        end

        # A real click is not intercepted — it still selects through the probe.
        click = read_intent(hp, hpio, MousePress(:left, cx, cy, ModifierKeys()))
        @test click isa ReplaceSelectionOperation
    end
end

"""
    test_hover_probe_pipeline()

End-to-end through the real `_multi_window_projection_inspector` pipeline: an
`WindowInput`-wrapped hover routed into the default window's content makes the
`WindowManagingProjection` add an `:inspector` follower window to the screen.
"""
function test_hover_probe_pipeline()
    @testset "HoverProbe pipeline" begin
        ex = json_example
        doc = ex.document
        proj = ex.projection

        # A valid content pixel (content layout is the same standalone or inside
        # the window, which ScreenToScreen sizes but does not offset).
        plain = print_document(proj, doc)
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
        iomap = print_document(composed, screen)

        nbefore = length(screen.windows)
        window_input = WindowInput(:json, MouseMove(cx, cy, MouseButtons(), ModifierKeys()))
        read_intent(composed, nothing, Intent(window_input, nothing), iomap)

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
