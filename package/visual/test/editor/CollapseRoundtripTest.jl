# ═══════════════════════════════════════════════════════════════════════════
# test/editor/CollapseRoundtripTest.jl
#
# End-to-end collapse/expand for the syntax example. Drives the same pipeline
# the editor runs (Syntax → Text → Graphics) and exercises both fold gestures:
#
#   • Mouse — clicking the inline marker collapses the clicked node; clicking
#     the collapsed ellipsis expands it again. Both yield a
#     ToggleCollapseOperation carrying the clicked node as its target.
#   • Keyboard — Ctrl+. folds the innermost node containing the selection, and
#     folds back on a second press. Keyboard navigation (Ctrl+Home) landing on
#     the marker must NOT toggle.
#
# Reuses `_find_text_iomap` from ClickRoundtripTest.jl (same module). Names
# resolve through the ProjecturedVisualTest flat namespace + ProjecturedVisualExample.
# ═══════════════════════════════════════════════════════════════════════════

# Centre of a rendered segment whose text equals `glyph`, as an (x, y) click.
function _glyph_click(coords, glyph::AbstractString)
    i = findfirst(sc -> sc.text == glyph, coords)
    i === nothing && return nothing
    sc = coords[i]
    (sc.x + 2, sc.y + 3)
end

function test_collapse_roundtrip()
    @testset "CollapseRoundtrip (syntax)" begin
        doc  = make_syntax_document_example()
        proj = make_syntax_projection_example()

        # ── Mouse: click the marker to collapse the root ───────────────────
        clear_selection!(doc)
        iomap  = print_document(proj, doc)
        coords = _find_text_iomap(iomap).char_to_coord[]
        click  = _glyph_click(coords, "▾")               # root's expanded marker
        @test click !== nothing
        op = read_intent(proj, iomap, MousePress(:left, click[1], click[2], Modifiers()))
        @test op isa ToggleCollapseOperation
        @test op.target === doc
        evaluate_operation(nothing, op)
        @test doc.collapsed == true

        # Collapsed render shows the ellipsis and hides the inner content.
        iomap2  = print_document(proj, doc)
        coords2 = _find_text_iomap(iomap2).char_to_coord[]
        line2   = join(sc.text for sc in coords2)
        @test occursin("…", line2)
        @test !occursin("defun", line2)

        # ── Mouse: click the ellipsis to expand ────────────────────────────
        eclick = _glyph_click(coords2, "…")
        @test eclick !== nothing
        op2 = read_intent(proj, iomap2, MousePress(:left, eclick[1], eclick[2], Modifiers()))
        @test op2 isa ToggleCollapseOperation
        @test op2.target === doc
        evaluate_operation(nothing, op2)
        @test doc.collapsed == false

        # ── Keyboard: Ctrl+. folds the innermost node at the cursor ─────────
        inner = doc.children[4].children[2]   # the (<= n 1) sub-expression
        clear_selection!(doc)
        set_selection!(doc, @reference(doc, children[4].children[2].children[1].value{1}))
        op3 = read_intent(proj, print_document(proj, doc), KeyDown(:period, Modifiers(ctrl=true)))
        @test op3 isa ToggleCollapseOperation
        @test op3.target === inner
        evaluate_operation(nothing, op3)
        @test inner.collapsed == true
        @test doc.collapsed == false      # only the inner node folded

        # A second Ctrl+. expands the same node.
        op4 = read_intent(proj, print_document(proj, doc), KeyDown(:period, Modifiers(ctrl=true)))
        @test op4 isa ToggleCollapseOperation
        @test op4.target === inner
        evaluate_operation(nothing, op4)
        @test inner.collapsed == false

        # ── Keyboard navigation onto the marker must not toggle ─────────────
        op5 = read_intent(proj, print_document(proj, doc), KeyDown(:home, Modifiers(ctrl=true)))
        @test op5 isa ReplaceSelectionOperation
    end
end
