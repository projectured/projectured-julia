# Workbench tab-strip routing (regression for "clicking the JSON editor tab page
# doesn't work").
#
# A WorkbenchPage renders as a WidgetTabbedPane whose *active* tab is a forward
# projection of the page selection: `WorkbenchPageToWidgetTabbedPane.print_document`
# wires the pane's `:selection` cell to `map_reference_forward(elements[i]) ->
# selector_element_pairs[i]`. The bug was that the cell truncated the page selection
# to `sel.head` alone — and because type checkpoints fold into the path nodes,
# `elements` and `[i]` are *separate* nodes, so `sel.head` is just `.elements` with
# the index dropped. The forward map then matched nothing, the active tab fell back
# to tab 1, and clicking any tab past the first never switched the visible editor.
#
# These tests pin both halves: the page selection drives the active tab index
# (print side, the regression), and the user gesture — a left click on a tab label —
# routes to a `ReplaceSelectionOperation` that selects that tab's element (read side).
#
# A third testset covers tab-strip overflow scrolling: when more tabs are open than
# fit the column, a mouse wheel over the strip scrolls it horizontally so the hidden
# tabs become reachable.


# The 1-based active tab index encoded in a tabbed pane's forward-projected
# `:selection` (shape `selector_element_pairs[i].<rest>`); 0 when no tab is selected
# (the printer then renders tab 1).
function _active_tab_index(tabbed)
    sel = getfield(tabbed, :selection)[]
    sel isa ConcreteReference || return 0
    h = sel.head
    (h isa FieldReferenceStep && h.name == "selector_element_pairs") || return 0
    t = sel.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep) || return 0
    t.head.start + 1
end

# Force a Cell; descend a graphics tree gathering (abs_x, abs_y, text) for every
# GraphicsText (the tab strip lives inside a clipping GraphicsViewport).
_force(x) = x isa Cell ? x[] : x
function _collect_texts!(acc, node, ox, oy)
    node = _force(node)
    node === nothing && return
    if node isa GraphicsText
        push!(acc, (ox + Int(_force(node.x)), oy + Int(_force(node.y)), String(_force(node.text))))
    elseif node isa GraphicsCanvas
        nx = ox + Int(_force(node.x)); ny = oy + Int(_force(node.y))
        for e in _force(getfield(node, :elements)); _collect_texts!(acc, e, nx, ny); end
    elseif node isa GraphicsViewport
        nx = ox + Int(_force(node.x)); ny = oy + Int(_force(node.y))
        _collect_texts!(acc, node.content, nx, ny)
    elseif node isa AbstractVector
        for e in node; _collect_texts!(acc, e, ox, oy); end
    end
end

function test_workbench_tab_click()
@testset "Workbench tab-strip routing" begin

# ── Print side: the active tab follows the page selection (the regression) ──
@testset "the active editing tab follows the page selection" begin
    doc  = make_workbench_document_example()
    # The extra RecursiveProjection wrapper threads `recursion` into the shell so the
    # pages recurse into real WidgetTabbedPane iomaps (a bare WorkbenchToWidget() leaves
    # them as page-identity SimpleIoMaps). The top iomap is the shell's, exposing
    # `editing_page_iomap`.
    proj = RecursiveProjection(WorkbenchToWidget())

    function active_after(sel_ref)
        sel_ref === nothing || evaluate_operation((; document = doc), ReplaceSelectionOperation(sel_ref))
        iomap = print_document(proj, doc)
        _active_tab_index(iomap.editing_page_iomap.output)
    end

    # No selection ⇒ no tab encoded (the printer falls back to rendering tab 1).
    @test active_after(nothing) == 0

    # Selecting an editor element makes *that* tab the active one — not tab 1.
    @test active_after(@reference(doc, editing_page.elements[1])) == 1
    @test active_after(@reference(doc, editing_page.elements[3])) == 3   # contact-list.json
    @test active_after(@reference(doc, editing_page.elements[5])) == 5

    # A caret deep inside the active tab's content still resolves to its tab: the
    # `elements[i]` prefix is preserved while the deep cursor suffix is dropped.
    @test active_after(@reference(doc, editing_page.elements[3].content)) == 3
end

# ── Read side: clicking the JSON tab label selects the JSON editor element ──
@testset "clicking the contact-list.json tab selects the JSON editor" begin
    doc  = make_workbench_document_example()
    proj = make_workbench_projection_example()
    iomap = print_document(proj, doc)

    acc = Tuple{Int,Int,String}[]
    _collect_texts!(acc, iomap.output, 0, 0)
    # The tab strip sits in the top row of the editing column.
    tab = filter(p -> p[3] == "contact-list.json" && p[2] < 40, acc)
    @test !isempty(tab)

    (tx, ty, _) = first(tab)
    ch = read_intent(proj, nothing,
                         Intent(MousePress(:left, tx + 5, ty + 8, ModifierKeys()), nothing), iomap)
    op = ch === nothing ? nothing : ch.operation
    @test op isa ReplaceSelectionOperation

    evaluate_operation((; document = doc), op)
    # The editing page's tabbed pane now reports the JSON tab (index 3) as active.
    iomap2 = print_document(RecursiveProjection(WorkbenchToWidget()), doc)
    @test _active_tab_index(iomap2.editing_page_iomap.output) == 3
end

# ── Overflow scrolling: a wheel over the strip reveals tabs that don't fit ──
@testset "scrolling the tab strip reveals overflow tabs" begin
    doc  = make_workbench_document_example()
    proj = make_workbench_projection_example()
    # A narrow window so the six editor tabs overflow the centre column — the last
    # ones are clipped off and unreachable until scrolled in. One persistent iomap,
    # re-forced after each write, mirrors the editor (the WidgetTabbedPane carrying
    # `tab_scroll` is transient output, rebuilt by a fresh print).
    ctx = PrinterContext(EmptyReference(),
                         Cell(1280), Cell(1000), Dict{Symbol,Any}())
    iomap = print_document(proj, nothing, doc, ctx)

    # Click a tab label on the current (re-forced) iomap; true iff it selects an editor.
    function click_selects_editor(title)
        acc = Tuple{Int,Int,String}[]; _collect_texts!(acc, iomap.output, 0, 0)
        m = filter(p -> p[3] == title && p[2] < 40, acc)
        isempty(m) && return false
        (tx, ty, _) = first(m)
        ch = read_intent(proj, nothing,
                             Intent(MousePress(:left, tx + 5, ty + 8, ModifierKeys()), nothing), iomap)
        op = ch === nothing ? nothing : ch.operation
        op isa ReplaceSelectionOperation && occursin("editing_page", string(op))
    end

    # The leading tabs fit and are reachable; the last one overflows and is not.
    @test click_selects_editor("contact-list.json")
    @test !click_selects_editor("table.pred")

    # A wheel over the strip (top row of the editing column) produces a horizontal
    # scroll write on the tabbed pane.
    sch = read_intent(proj, nothing,
                          Intent(MouseScroll(0, -3, 430, 17, ModifierKeys()), nothing), iomap)
    sop = sch === nothing ? nothing : sch.operation
    @test sop isa ReplaceReferencedValueOperation
    @test sop.value isa Integer && sop.value > 0    # scrolled the strip rightwards

    # Scroll the strip to its end (the printer clamps the offset) and the overflow tab
    # becomes reachable; a leading tab scrolls off and is no longer reachable.
    evaluate_operation((; document = doc), ReplaceReferencedValueOperation(sop.document, "tab_scroll", 100000))
    @test click_selects_editor("table.pred")
    @test !click_selects_editor("book")
end

# ── Keyboard focus follows the selection (regression) ───────────────────────
#
# The shell's raw-key reader used to broadcast every KeyPress/KeyDown to *all*
# panels, and the assistant composer (whose `insert` binding matches any
# printable key) always claimed it — so after clicking the JSON editor, typing
# still landed in the draft message. The reader now offers a raw key only to the
# panel the workbench selection points at, falling back to the composer's default
# focus only when nothing is selected.
@testset "typing routes to the selected panel, not the assistant draft" begin
    doc  = make_workbench_document_example()
    proj = make_workbench_projection_example()

    function type_op(ref)
        ref === nothing || evaluate_operation((; document = doc),
                                              ReplaceSelectionOperation(ref))
        iomap = print_document(proj, doc)
        ch = read_intent(proj, nothing, Intent(KeyPress('X'), nothing), iomap)
        ch === nothing ? nothing : ch.operation
    end

    # Nothing selected: the composer keeps the default focus.
    @test type_op(nothing) isa ComposerInputOperation

    # Selecting the JSON editor takes focus away from the draft — a printable key
    # no longer becomes a composer edit (no caret in the tab content yet, so it
    # routes nowhere rather than into the draft).
    @test !(type_op(@reference(doc, editing_page.elements[3])) isa ComposerInputOperation)

    # Selecting the assistant panel routes keys back to the draft composer.
    @test type_op(@reference(doc, control_page.elements[1])) isa ComposerInputOperation
end

# ── Reactive reflow (AR-STABLE-IOMAP-IDENTITY): a page-element add/remove reflows
# the tab strip through the SAME held iomap — no re-print. The page elements are
# reconciled (reconcile_child_iomaps) and the tabbed pane's selector_element_pairs
# is a set_cell_function! thunk reading them, so a structural edit re-derives it. ──
@testset "a page-element add/remove reflows the tab strip" begin
    doc  = make_workbench_document_example()
    proj = RecursiveProjection(WorkbenchToWidget())
    iomap = print_document(proj, doc)
    tabbed = iomap.editing_page_iomap.output
    n = length(tabbed.selector_element_pairs)
    @test n >= 2
    popped = pop!(doc.editing_page.elements)
    @test length(tabbed.selector_element_pairs) == n - 1   # remove reflows reactively
    push!(doc.editing_page.elements, popped)
    @test length(tabbed.selector_element_pairs) == n       # add reflows back
end

end # @testset
end # function
