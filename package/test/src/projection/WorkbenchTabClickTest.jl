# Workbench tab-strip routing (regression for "clicking the JSON editor tab page
# doesn't work").
#
# A WorkbenchPage renders as a WidgetTabbedPane whose *active* tab is a forward
# projection of the page selection: `WorkbenchPageToWidgetTabbedPane.projection_print`
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

using Projectured: WorkbenchToWidget, RecursiveProjection, ReplaceSelectionOperation,
    evaluate_operation, ConcreteReferencePath, FieldReference, RangeReference,
    GraphicsText, GraphicsCanvas, GraphicsViewport, MousePress, Modifiers, Change

# The 1-based active tab index encoded in a tabbed pane's forward-projected
# `:selection` (shape `selector_element_pairs[i].<rest>`); 0 when no tab is selected
# (the printer then renders tab 1).
function _active_tab_index(tabbed)
    sel = getfield(tabbed, :selection)[]
    sel isa ConcreteReferencePath || return 0
    h = sel.head
    (h isa FieldReference && h.name == "selector_element_pairs") || return 0
    t = sel.tail
    (t isa ConcreteReferencePath && t.head isa RangeReference) || return 0
    t.head.start + 1
end

# Force a Cell; descend a graphics tree gathering (abs_x, abs_y, text) for every
# GraphicsText (the tab strip lives inside a clipping GraphicsViewport).
_force(x) = x isa Projectured.Cell ? x[] : x
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
        iomap = projection_print(proj, doc)
        _active_tab_index(iomap.editing_page_iomap.output)
    end

    # No selection ⇒ no tab encoded (the printer falls back to rendering tab 1).
    @test active_after(nothing) == 0

    # Selecting an editor element makes *that* tab the active one — not tab 1.
    @test active_after(@reference editing_page.elements[1]) == 1
    @test active_after(@reference editing_page.elements[3]) == 3   # contact-list.json
    @test active_after(@reference editing_page.elements[5]) == 5

    # A caret deep inside the active tab's content still resolves to its tab: the
    # `elements[i]` prefix is preserved while the deep cursor suffix is dropped.
    @test active_after(@reference editing_page.elements[3].content) == 3
end

# ── Read side: clicking the JSON tab label selects the JSON editor element ──
@testset "clicking the contact-list.json tab selects the JSON editor" begin
    doc  = make_workbench_document_example()
    proj = make_workbench_projection_example()
    iomap = projection_print(proj, doc)

    acc = Tuple{Int,Int,String}[]
    _collect_texts!(acc, iomap.output, 0, 0)
    # The tab strip sits in the top row of the editing column.
    tab = filter(p -> p[3] == "contact-list.json" && p[2] < 40, acc)
    @test !isempty(tab)

    (tx, ty, _) = first(tab)
    ch = projection_read(proj, nothing,
                         Change(MousePress(:left, tx + 5, ty + 8, Modifiers()), nothing), iomap)
    op = ch === nothing ? nothing : ch.operation
    @test op isa ReplaceSelectionOperation

    evaluate_operation((; document = doc), op)
    # The editing page's tabbed pane now reports the JSON tab (index 3) as active.
    iomap2 = projection_print(RecursiveProjection(WorkbenchToWidget()), doc)
    @test _active_tab_index(iomap2.editing_page_iomap.output) == 3
end

end # @testset
end # function
