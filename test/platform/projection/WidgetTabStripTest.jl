# The three things a tab strip reports beside a tab click: a close button, a
# new-tab button, and the grab that may become a drag. Each is opt-in on the pane.
# The close button is a toolbar button of the page of the tab.
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
        op = read_intent(proj, nothing, Intent(event_of(x, y)), iomap).operation
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
    on_button = [(x, y) for y in 0:2:40, x in 0:2:400
                 if read_intent(proj, nothing, Intent(_press(x, y)), iomap).operation isa CloseTabOperation]
    @test !isempty(on_button)
    @test !any(read_intent(proj, nothing, Intent(_down(x, y)), iomap).operation isa DragTabOperation for (x, y) in on_button)
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
        op = read_intent(proj, nothing, Intent(event_of(x, y)), iomap).operation
        op isa Union{ReplaceSelectionOperation, CloseTabOperation, DragTabOperation} || continue
        push!(found, (x, y, op))
    end
    found
end

@testset "a press on the close button closes the tab, and a press above or below it opens the tab" begin
    pane = _pane(closable = true, draggable = true)
    proj = _proj()
    iomap = print_document(proj, pane)
    presses = _sweep_points(proj, iomap, _press)
    button = [(x, y) for (x, y, op) in presses if op isa CloseTabOperation && op.tab_index == 1]
    @test !isempty(button)
    # The presses that close the tab fill the box of the button.
    xs, ys = first.(button), last.(button)
    @test length(button) == (maximum(xs) - minimum(xs) + 1) * (maximum(ys) - minimum(ys) + 1)
    # The strip is higher than the button, and a press above or below it opens the tab.
    beside = [op for (x, y, op) in presses if x in xs && !(y in ys)]
    @test !isempty(beside) && all(op -> _select_tab(op, 1), beside)
    # A down on the close button is not a grab, and a down beside it is.
    downs = _sweep_points(proj, iomap, _down)
    @test !any((x, y) in button && op isa DragTabOperation for (x, y, op) in downs)
    @test any(x in xs && !(y in ys) && op isa DragTabOperation && op.tab_index == 1 for (x, y, op) in downs)
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
             if read_intent(proj, nothing, Intent(_press(px, py)), iomap).operation isa CloseTabOperation]
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

# The IO map of the strip among the IO maps that `node` holds: a walk of the
# fields of each IO map, its cells and its lists.
function _find_strip_iomap(node, seen = Base.IdSet{Any}())
    node = unwrap_cell(node)
    (node === nothing || node in seen) && return nothing
    node isa WidgetModule.WidgetTabbedPaneToGraphicsCanvasIoMap && return node
    if node isa IoMap
        push!(seen, node)
        for name in fieldnames(typeof(node))
            name in (:projection, :input) && continue
            found = _find_strip_iomap(getfield(node, name), seen)
            found === nothing || return found
        end
    elseif node isa Union{AbstractVector, Tuple, CellVector}
        push!(seen, node)
        for element in node
            found = _find_strip_iomap(element, seen)
            found === nothing || return found
        end
    end
    nothing
end

@testset "the close button is a toolbar button: a surface under the pointer, a darker one while held" begin
    pane = _pane(closable = true)
    proj = _proj()
    driver = MttDriver(proj, pane)
    iomap = driver.iomap
    presses = _sweep_points(proj, iomap, _press)
    bx, by = first((x, y) for (x, y, op) in presses if op isa CloseTabOperation && op.tab_index == 1)
    tx, ty = first((x, y) for (x, y, op) in presses if _select_tab(op, 1))
    button = pane.selector_element_pairs[1].close
    @test button isa WidgetToolbarItem
    cim = getfield(_find_strip_iomap(iomap), :close_iomaps)[][1]
    hovered, held = cim.projection.layer_hovered_color, cim.projection.layer_pressed_color
    layers() = [e.color for e in cim.output.elements
                if e isa GraphicsRect && Int(e.w) > 0 && e.color in (hovered, held)]
    # Flat at rest, and flat while the pointer is on the name of the tab.
    @test isempty(layers())
    _mtt_move!(driver, tx, ty, 1.0)
    @test isempty(layers())
    # The surface of a button while the pointer is on the button.
    _mtt_move!(driver, bx, by, 2.0)
    @test get_mouse_target(button) !== nothing
    @test layers() == [hovered]
    # A down on the button is the button's, and it holds the button down.
    _mtt_apply!(driver, read_intent(proj, nothing, Intent(_down(bx, by)), iomap).operation)
    @test button.pressed === true
    @test layers() == [held]
    # A move off the button ends the press, and the surface goes.
    _mtt_move!(driver, tx, ty, 3.0)
    @test button.pressed === false
    @test isempty(layers())
    # The button says what it does.
    @test string(button.action.label) == "Close"
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
        press = read_intent(proj, nothing, Intent(_press(x, y)), iomap).operation
        middle = read_intent(proj, nothing, Intent(_middle(x, y)), iomap).operation
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
    @test all(isnothing(read_intent(proj, nothing, Intent(_middle(x, y)), plain_iomap).operation) for y in rows, x in 0:2:400)
end

# The first viewport in `node`, the view of the strip, as `(x, y, width, height)` in
# the frame of `node`.
function _strip_view(node, ox = 0, oy = 0)
    node isa GraphicsViewport && return (ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h))
    node isa GraphicsCanvas || return nothing
    for e in node.elements
        found = _strip_view(e, ox + Int(node.x), oy + Int(node.y))
        found === nothing || return found
    end
    nothing
end

# The right edge of each rectangle that is drawn outside every viewport.
function _right_edges_outside_views(node, ox = 0, found = Int[])
    if node isa GraphicsCanvas
        for e in node.elements
            _right_edges_outside_views(e, ox + Int(node.x), found)
        end
    elseif node isa GraphicsRect
        push!(found, ox + Int(node.x) + Int(node.w))
    end
    found
end

# The x of the name `name` in the strip, and whether the name shows whole in the
# view of the strip.
function _shown_tab(iomap, name)
    view_x, _, view_w, _ = _strip_view(iomap.output)
    x = only(x for (x, _, text, _) in _strip_texts(iomap.output) if text == name)
    (x, view_x <= x && x + 10 * length(name) <= view_x + view_w)
end

@testset "a strip that does not fit shows its open tab and stays where the wheel puts it" begin
    proj = _proj()
    # Names of two or three characters keep their width, so the strip scrolls them.
    pane = WidgetTabbedPane(Any[("t$i", WidgetLabel("$i")) for i in 1:10])
    open_tab!(index) = set_selection!(pane, Reference(FieldReferenceStep("selector_element_pairs"),
                                                      ElementReferenceStep(index)))
    context = with_exact_size(PrinterContext(); width = Cell(Int32(200)), height = Cell(Int32(80)))
    print_pane() = print_document(proj, nothing, pane, context)
    editor = (document = pane,)
    open_tab!(9)
    iomap = print_pane()
    # The open tab shows, and nothing is drawn past the right edge of the slot: the
    # line under the tabs and the page stop there.
    @test _shown_tab(iomap, "t9")[2]
    @test !_shown_tab(iomap, "t1")[2]
    @test maximum(_right_edges_outside_views(iomap.output)) <= 200
    # A turn of the wheel over the strip moves it toward the first tab, and the open
    # tab goes out of view and stays out.
    view_x, view_y, _, view_h = _strip_view(iomap.output)
    for second in 1:200
        _shown_tab(iomap, "t1")[2] && break
        evaluate_operation(editor, read_intent(proj, nothing, Intent(MouseScroll(0, 1, view_x + 5, view_y + view_h ÷ 2;
                                                                         time = Float64(second))), iomap).operation)
        iomap = print_pane()
    end
    @test _shown_tab(iomap, "t1")[2]
    @test !_shown_tab(iomap, "t9")[2]
    # A click on a tab in view opens it, and the strip does not move.
    x, _ = _shown_tab(iomap, "t2")
    evaluate_operation(editor, read_intent(proj, nothing, Intent(_press(x + 2, view_y + view_h ÷ 2)), iomap).operation)
    iomap = print_pane()
    @test _shown_tab(iomap, "t2")[1] == x
    # A tab that opens in another way shows.
    open_tab!(10)
    iomap = print_pane()
    @test _shown_tab(iomap, "t10")[2]
end

# The names of the tabs that `iomap` draws in the band of its strip, in the order of
# the strip.
function _drawn_names(iomap, names)
    _, view_y, _, view_h = _strip_view(iomap.output)
    [text for (_, y, text, _) in sort(_strip_texts(iomap.output); by = first)
     if view_y <= y < view_y + view_h && !isempty(text) && any(name -> startswith(name, rstrip(text, '…')), names)]
end

@testset "in a slot the long names shrink to share the width, and a cut name ends with …" begin
    proj = _proj()
    names = ["a", "b", "a long name of a tab", "another long name"]
    pane = WidgetTabbedPane(Any[(name, WidgetLabel(name)) for name in names])
    natural = print_document(proj, pane)
    natural_w = Int(unwrap_cell(natural.output.w))
    context = with_exact_size(PrinterContext(); width = Cell(Int32(natural_w - 100)), height = Cell(Int32(80)))
    iomap = print_document(proj, nothing, pane, context)
    drawn = _drawn_names(iomap, names)
    # The short names keep their width, and the long ones end with "…".
    @test drawn[1] == "a" && drawn[2] == "b"
    @test endswith(drawn[3], "…") && endswith(drawn[4], "…")
    @test startswith(names[3], rstrip(drawn[3], '…')) && startswith(names[4], rstrip(drawn[4], '…'))
    # All tabs show, and the strip draws no menu button and nothing past the slot.
    view_x, _, view_w, _ = _strip_view(iomap.output)
    @test all(view_x <= x && x + 10 * length(text) <= view_x + view_w
              for (x, _, text, _) in _strip_texts(iomap.output) if text in drawn)
    @test maximum(_right_edges_outside_views(iomap.output)) <= natural_w - 100
end

@testset "below the least width of a name a menu button lists the tabs, and an item opens its tab" begin
    proj = _proj()
    names = ["$i tab number" for i in 1:10]
    pane = WidgetTabbedPane(Any[(name, WidgetLabel(name)) for name in names])
    context = with_exact_size(PrinterContext(); width = Cell(Int32(200)), height = Cell(Int32(80)))
    iomap = print_document(proj, nothing, pane, context)
    # The names are cut at their least width, four widths of "M".
    @test _drawn_names(iomap, names)[1] == "1 t…"
    # A sweep of the strip finds the menu button at its right end.
    view_x, view_y, view_w, view_h = _strip_view(iomap.output)
    found = nothing
    for x in (view_x + view_w):2:200
        answer = read_intent(proj, nothing, Intent(_press(x, view_y + view_h ÷ 2)), iomap).operation
        answer isa WrappingOperation && (answer = get_wrapped_operation(answer))
        answer isa OpenContextMenuOperation && (found = answer; break)
    end
    @test found isa OpenContextMenuOperation
    found isa OpenContextMenuOperation || return
    items = [item for (_, menu, _) in found.layers for item in menu.elements if item isa WidgetMenuItem]
    @test [item.action.label for item in items] == names
    # The item of a tab selects that tab of the list of the pages, as a click on it.
    item = items[7]
    part = find_menu_item_part(found, item.operation)
    evaluate_operation((document = pane,),
                       reroot_operation(item.operation, Tuple(get_reference_steps(strip_reference_types(part)))))
    @test WidgetModule._tab_index_from_selection(get_stored_selection(pane), 10) == 7
    iomap = print_document(proj, nothing, pane, context)
    @test "7 t…" in _drawn_names(iomap, names)
    @test _shown_tab(iomap, "7 t…")[2]
    # After a turn of the wheel hides the open tab, its item shows it again.
    for second in 1:100
        _shown_tab(iomap, "1 t…")[2] && break
        evaluate_operation((document = pane,), read_intent(proj, nothing, Intent(MouseScroll(0, 1, view_x + 5, view_y + view_h ÷ 2;
                                                                                    time = Float64(second))), iomap).operation)
        iomap = print_document(proj, nothing, pane, context)
    end
    @test !_shown_tab(iomap, "7 t…")[2]
    evaluate_operation((document = pane,),
                       reroot_operation(item.operation, Tuple(get_reference_steps(strip_reference_types(part)))))
    iomap = print_document(proj, nothing, pane, context)
    @test _shown_tab(iomap, "7 t…")[2]
end

# Every rectangle of a printed strip, as (x, y, width), through its canvases and
# viewports.
function _strip_rects(node, ox = 0, oy = 0, found = Tuple{Int,Int,Int}[])
    if node isa GraphicsCanvas
        for e in node.elements
            _strip_rects(e, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _strip_rects(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsRect
        push!(found, (ox + Int(node.x), oy + Int(node.y), Int(node.w)))
    end
    found
end

# The part under the pointer that `operation`, the answer to a move, names, or
# `nothing`.
function _target_of(operation)
    operation isa ReplaceMouseTargetOperation && return operation.path
    operation isa CompoundOperation || return nothing
    for member in operation.operations
        target = _target_of(member)
        target === nothing || return target
    end
    nothing
end

@testset "the name of a tab reads like the text of a control: a plain click opens the tab, an Alt+click puts the caret" begin
    pane = _pane()
    proj = _proj()
    iomap = print_document(proj, pane)
    x, y, _, _ = only(t for t in _strip_texts(iomap.output) if t[3] == "two")
    alt = ModifierKeys(alt = true)
    # A plain click on the name opens its tab.
    @test _select_tab(read_intent(proj, iomap, _press(x + 10 + 1, y + 2)), 2)
    # An Alt+click after the first character puts the caret there, in the name.
    caret = read_intent(proj, iomap, MouseClick(:left, x + 10 + 1, y + 2, alt; time = 0.0))
    @test caret isa ReplaceSelectionOperation
    name = strip_reference_types(WidgetModule._make_tab_name_part(pane.selector_element_pairs[2].selector, 2))
    @test strip_reference_types(caret.path) ==
          concat_references(name, ConcreteReference(RangeReferenceStep(1, 1), EmptyReference()))
    # The caret maps forward to its place in the name.
    box = find_reference_box(iomap.output, map_reference_forward(proj, iomap, caret.path); measure = _stub)
    @test box !== nothing && (Int(box.x), Int(box.y)) == (x + 10, y)
    # A press with Alt starts the drag of a range there, and grabs no tab.
    down = read_intent(proj, iomap, MouseDown(:left, x + 10 + 1, y + 2, alt; time = 0.0))
    @test down isa CompoundOperation && any(op -> op isa StartDragOperation, down.operations)
    # A move on the name names the character under the pointer.
    target = _target_of(read_intent(proj, iomap, MouseMove(x + 10 + 1, y + 2; time = 0.0)))
    @test target !== nothing && strip_reference_types(target) == strip_reference_types(caret.path)
    # The name selected as a whole draws a band behind it, as wide as the name.
    band(rects) = any(rect -> rect[1] == x && rect[3] == 3 * 10, rects)
    @test !band(_strip_rects(iomap.output))
    evaluate_operation((document = pane,), ReplaceSelectionOperation(annotate_reference_types(pane, name)))
    @test band(_strip_rects(print_document(proj, pane).output))
end

@testset "in a slot the line under the tabs reaches the edge also when the open page has no content" begin
    proj = _proj()
    pane = WidgetTabbedPane(Any[("a", nothing), ("b", WidgetLabel("b"))])
    context = with_exact_size(PrinterContext(); width = Cell(Int32(200)), height = Cell(Int32(80)))
    iomap = print_document(proj, nothing, pane, context)
    @test 190 <= maximum(_right_edges_outside_views(iomap.output)) <= 200
end

end # testset
end # function
