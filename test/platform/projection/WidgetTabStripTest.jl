# The three things a tab strip reports beside a tab click: a close button, a
# new-tab button, and the grab that may become a drag. Each is opt-in on the pane.
#
# The tests never hardcode a pixel: they sweep the strip and assert on *which*
# operations appear and in what order along the x axis. So they check the seam
# (what the strip says, and where), not the theme's padding arithmetic.
function test_widget_tab_strip()
@testset "WidgetTabbedPane strip buttons" begin

_stub = FixedMeasure(10, 18, 6, 0)
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

_press(x, y) = MouseClick(:left, x, y, ModifierKeys(); time = 0.0)
_down(x, y) = MouseDown(:left, x, y, ModifierKeys(); time = 0.0)

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
end

# Every press or down in the strip band that answers a strip report, with where.
function _sweep_points(proj, iomap, event_of)
    found = Tuple{Int,Int,Any}[]
    for y in 0:1:40, x in 0:1:400
        op = read_intent(proj, iomap, event_of(x, y))
        op isa Union{ReplaceSelectionOperation, CloseTabOperation, DragTabOperation} || continue
        push!(found, (x, y, op))
    end
    found
end

@testset "a press anywhere in the close column of a tab closes it" begin
    pane = _pane(closable = true, draggable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    presses = _sweep_points(proj, iomap, _press)
    column = Set(x for (x, _, op) in presses if op isa CloseTabOperation && op.tab_index == 1)
    @test !isempty(column)
    # Every press at an x of the column answers the close, at every height of the
    # strip: the column holds one button.
    @test all(op isa CloseTabOperation && op.tab_index == 1
              for (x, _, op) in presses if x in column)
    # A down on the close button is not a grab.
    downs = _sweep_points(proj, iomap, _down)
    @test !any(x in column && op isa DragTabOperation for (x, _, op) in downs)
    @test any(op -> op isa DragTabOperation && op.tab_index == 1, last.(downs))
end

# Every text of a printed strip, as (x, y, text, font), through its canvases and
# viewports.
function _strip_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String,StyleFont}[])
    if node isa GraphicsCanvas
        for e in node.elements
            _strip_texts(e, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _strip_texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text), node.font))
    end
    found
end

@testset "the name of the selected tab ends before its close button" begin
    # The selected tab draws its name in a heavier face than the other tabs. With the
    # real faces a long heavier name is wider by more than the gap before the button,
    # so the strip must give each name the width of its heavier face. The default
    # theme draws every tab in the text role, so no other size hides the difference.
    measure = FontFileMeasure()
    name = "The selected tab draws its long name in the medium face"
    pane = WidgetTabbedPane(Any[(name, WidgetLabel("1")), ("two", WidgetLabel("2"))];
                            closable = true)
    proj = RecursiveProjection(WidgetToGraphics(; measure))
    iomap = print_document(proj, pane)
    x, y, _, font = only(t for t in _strip_texts(iomap.output) if t[3] == name)
    regular = StyleFont(font.family, font.size; weight = 400)
    width = measure_string(measure, name, font).width
    @test font.weight > 400
    @test width - measure_string(measure, name, regular).width > get_theme_defaults(WidgetTheme).label_gap
    close = [px for py in 0:2:40, px in x:(x + ceil(Int, width) + 200)
             if read_intent(proj, iomap, _press(px, py)) isa CloseTabOperation]
    @test !isempty(close)
    @test x + width <= minimum(close)
end

# The text of the built-in icon `name`: each is a glyph of the icon font.
_icon_text(name) = string(Char(Dict(WidgetModule.LUCIDE_ICON_GLYPHS)[name]))

@testset "a tab draws no duplicate button" begin
    pane = _pane(closable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    texts = _strip_texts(iomap.output)
    @test any(t -> t[3] == _icon_text(:close), texts)
    @test !any(t -> t[3] == _icon_text(:plus), texts)
end

# The x of each close button that a printed strip draws.
_drawn_closes(iomap) = [t[1] for t in _strip_texts(iomap.output) if t[3] == _icon_text(:close)]

# The canvas that holds the text `text`, the innermost one, or `nothing`.
function _canvas_of(node, text)
    if node isa GraphicsCanvas
        for element in node.elements
            element isa GraphicsText && string(element.text) == text && return node
            found = _canvas_of(element, text)
            found === nothing || return found
        end
    elseif node isa GraphicsViewport
        return _canvas_of(node.content, text)
    end
    nothing
end

# What a press at a point of the strip answers, in a form two sweeps can compare.
_part_of(op) = op isa CloseTabOperation ? (:close, op.tab_index) :
               op isa DragTabOperation ? (:grab, op.tab_index) : (:tab, string(op.path))

@testset "the open tab shows its close button, another tab only under the pointer" begin
    pane = _pane(closable = true)
    proj = _proj()
    driver = MttDriver(proj, pane)
    iomap = driver.iomap
    presses = _sweep_points(proj, iomap, _press)
    column2 = [x for (x, _, op) in presses if op isa CloseTabOperation && op.tab_index == 2]
    x2, y2 = first((x, y) for (x, y, op) in presses if _select_tab(op, 2))
    # At rest the open tab, the first, shows its button, and the second does not.
    @test length(_drawn_closes(iomap)) == 1
    @test !any(x -> minimum(column2) <= x <= maximum(column2), _drawn_closes(iomap))
    header = _canvas_of(iomap.output, "two")
    @test header !== nothing
    # The pointer on the name of the second tab shows its button, in its column.
    _mtt_move!(driver, x2, y2, 1.0)
    closes = _drawn_closes(iomap)
    # The move redraws the canvas of the button, and the strip keeps the canvas of
    # the header.
    @test _canvas_of(iomap.output, "two") === header
    @test length(closes) == 2
    @test any(x -> minimum(column2) <= x <= maximum(column2), closes)
    # No part of the strip moves while the button shows.
    @test [(x, y, _part_of(op)) for (x, y, op) in _sweep_points(proj, iomap, _press)] ==
          [(x, y, _part_of(op)) for (x, y, op) in presses]
    # The pointer off the window hides it again.
    _mtt_leave!(driver, 2.0)
    @test length(_drawn_closes(iomap)) == 1
end

_middle(x, y) = MouseClick(:middle, x, y, ModifierKeys(); time = 0.0)

@testset "a middle click on a tab closes it, and does nothing elsewhere in the strip" begin
    pane = _pane(closable = true, new_tab = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    rows = Set(y for (_, y, op) in _sweep_points(proj, iomap, _press) if op isa CloseTabOperation)
    @test !isempty(rows)
    on_tab = Tuple{Int,Any}[]
    elsewhere = Any[]
    for y in rows, x in 0:1:400
        press = read_intent(proj, iomap, _press(x, y))
        middle = read_intent(proj, iomap, _middle(x, y))
        index = press isa CloseTabOperation ? press.tab_index :
                _select_tab(press, 1) ? 1 : _select_tab(press, 2) ? 2 : 0
        index > 0 ? push!(on_tab, (index, middle)) : push!(elsewhere, middle)
    end
    @test any(t -> t[1] == 1, on_tab) && any(t -> t[1] == 2, on_tab)
    @test all(middle isa CloseTabOperation && middle.tab_index == index && middle.widget === pane
              for (index, middle) in on_tab)
    # The new-tab button and the empty end of the strip give nothing.
    @test !isempty(elsewhere) && all(isnothing, elsewhere)
    # A strip that does not close tabs gives nothing to a middle click.
    plain = _pane()
    plain_iomap = print_document(proj, plain)
    @test all(isnothing(read_intent(proj, plain_iomap, _middle(x, y))) for y in rows, x in 0:2:400)
end

end # testset
end # function
