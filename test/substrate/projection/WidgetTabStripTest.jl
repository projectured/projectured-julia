# The four things a tab strip reports beside a tab click: a close button, a
# duplicate button, a new-tab button, and the grab that may become a drag. Each is
# opt-in on the pane.
#
# The tests never hardcode a pixel: they sweep the strip and assert on *which*
# operations appear and in what order along the x axis. So they check the seam
# (what the strip says, and where), not the theme's padding arithmetic.
function test_widget_tab_strip()
@testset "WidgetTabbedPane strip buttons" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_proj() = make_widget_projection_example(measure=_stub)

function _pane(; kwargs...)
    WidgetTabbedPane(Any[("one", WidgetLabel("1")),
                         ("two", WidgetLabel("2"))]; kwargs...)
end

# Sweep the strip band and collect `x => operation` for every operation of a type
# the strip itself produces.
function _sweep(proj, iomap, event_of)
    found = Tuple{Int,Any}[]
    for y in 0:2:40, x in 0:2:400
        op = read_intent(proj, iomap, event_of(x, y))
        # A tab click is a ReplaceSelectionOperation, so the sweep keeps one.
        op isa Union{ReplaceSelectionOperation, CloseTabOperation,
                     OpenTabOperation, DragTabOperation} || continue
        push!(found, (x, op))
    end
    found
end

_press(x, y) = MousePress(:left, x, y, ModifierKeys())
_down(x, y) = MouseDown(:left, x, y, ModifierKeys())

# The first x at which `predicate` holds, or `nothing`.
function _first_x(found, predicate)
    for (x, op) in found
        predicate(op) && return x
    end
    nothing
end

# A tab click is a plain selection replacement: the strip names the tab it was
# clicked on, in the pane's own coordinates, and the chain re-roots it. Matched on
# the printed path so this file needs none of the reference step types in scope.
_select_tab(op, index) =
    op isa ReplaceSelectionOperation &&
    occursin("selector_element_pairs[$index]", string(op.path))

@testset "a plain strip reports only tab clicks" begin
    pane = _pane()
    proj = _proj()
    iomap = print_document(proj, pane)
    found = _sweep(proj, iomap, _press)
    @test any(op -> _select_tab(op, 1), last.(found))
    @test any(op -> _select_tab(op, 2), last.(found))
    @test !any(op -> op isa CloseTabOperation, last.(found))
    @test !any(op -> op isa OpenTabOperation, last.(found))
    # No grab either, until the pane is draggable.
    @test isempty(_sweep(proj, iomap, _down))
end

@testset "a closable strip reports a close on each tab's right edge" begin
    pane = _pane(closable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    found = _sweep(proj, iomap, _press)

    select1 = _first_x(found, op -> _select_tab(op, 1))
    close1  = _first_x(found, op -> op isa CloseTabOperation && op.tab_index == 1)
    select2 = _first_x(found, op -> _select_tab(op, 2))
    close2  = _first_x(found, op -> op isa CloseTabOperation && op.tab_index == 2)
    @test all(!isnothing, (select1, close1, select2, close2))
    # Each tab's close button sits at its right edge, so the four run in order.
    @test select1 < close1 < select2 < close2
    # Every close report names the pane it came from.
    @test all(op -> op.widget === pane,
              [op for (_, op) in found if op isa CloseTabOperation])
end

@testset "a new-tab button follows the last tab" begin
    pane = _pane(new_tab = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    found = _sweep(proj, iomap, _press)
    new_x = _first_x(found, op -> op isa OpenTabOperation)
    last_tab = _first_x(found, op -> _select_tab(op, 2))
    @test new_x !== nothing
    @test last_tab < new_x
end

@testset "an empty pane still offers its new-tab button" begin
    pane = WidgetTabbedPane(Any[]; new_tab = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    found = _sweep(proj, iomap, _press)
    @test any(op -> op isa OpenTabOperation, last.(found))
end

@testset "a draggable strip reports a grab on the tab under the button" begin
    pane = _pane(draggable = true, closable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    found = _sweep(proj, iomap, _down)
    @test any(op -> op isa DragTabOperation && op.tab_index == 1, last.(found))
    @test any(op -> op isa DragTabOperation && op.tab_index == 2, last.(found))
    # A grab is a whole-tab gesture except on the close button, which is a click.
    grab1 = _first_x(found, op -> op isa DragTabOperation && op.tab_index == 1)
    grab2 = _first_x(found, op -> op isa DragTabOperation && op.tab_index == 2)
    @test grab1 < grab2
    presses = _sweep(proj, iomap, _press)
    close1 = _first_x(presses, op -> op isa CloseTabOperation && op.tab_index == 1)
    @test !any(x == close1 && op isa DragTabOperation for (x, op) in found)
end

@testset "the reports are inert when nobody claims them" begin
    pane = _pane(closable = true, new_tab = true, draggable = true)
    # An unclaimed report reaching the editor does nothing rather than failing.
    @test evaluate_operation(nothing, CloseTabOperation(pane, 1)) === nothing
    @test evaluate_operation(nothing, OpenTabOperation(pane)) === nothing
    @test evaluate_operation(nothing, DragTabOperation(pane, 1)) === nothing
    @test evaluate_operation(nothing, DuplicateTabOperation(pane, 1)) === nothing
end

# A pane whose first page offers a duplicate and whose second does not.
function _duplicable_pane(; kwargs...)
    WidgetTabbedPane(Any[("one", WidgetLabel("1"), nothing, true),
                         ("two", WidgetLabel("2"), nothing, false)]; kwargs...)
end

# Every press or down in the strip band that answers a strip report, with where.
function _sweep_points(proj, iomap, event_of)
    found = Tuple{Int,Int,Any}[]
    for y in 0:1:40, x in 0:1:400
        op = read_intent(proj, iomap, event_of(x, y))
        op isa Union{CloseTabOperation, DuplicateTabOperation, DragTabOperation} || continue
        push!(found, (x, y, op))
    end
    found
end

@testset "a duplicable page splits its close column: the + above the x" begin
    pane = _duplicable_pane(closable = true, duplicable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    found = _sweep_points(proj, iomap, _press)
    duplicates = [(x, y) for (x, y, op) in found if op isa DuplicateTabOperation]
    closes1 = [(x, y) for (x, y, op) in found if op isa CloseTabOperation && op.tab_index == 1]
    @test !isempty(duplicates)
    @test !isempty(closes1)
    # Every duplicate report names the first tab and the pane it came from.
    @test all(op -> op.tab_index == 1 && op.widget === pane,
              [op for (_, _, op) in found if op isa DuplicateTabOperation])
    # One column: the same x range, the + wholly above the x.
    @test extrema(first.(duplicates)) == extrema(first.(closes1))
    @test maximum(last.(duplicates)) < minimum(last.(closes1))
    # The second page keeps its whole close button.
    @test any(op -> op isa CloseTabOperation && op.tab_index == 2, last.(found))
end

@testset "a pane that is not duplicable offers no +, whatever its pages say" begin
    pane = _duplicable_pane(closable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    @test !any(op -> op isa DuplicateTabOperation, last.(_sweep_points(proj, iomap, _press)))
end

@testset "a down on the + is not a grab" begin
    pane = _duplicable_pane(closable = true, duplicable = true, draggable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    presses = _sweep_points(proj, iomap, _press)
    downs = _sweep_points(proj, iomap, _down)
    plus = Set((x, y) for (x, y, op) in presses if op isa DuplicateTabOperation)
    @test !isempty(plus)
    @test !any((x, y) in plus for (x, y, op) in downs if op isa DragTabOperation)
    @test any(op -> op isa DragTabOperation && op.tab_index == 1, last.(downs))
end

end # testset
end # function
