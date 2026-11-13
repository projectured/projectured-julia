# A click reaches the innermost part under the pointer, in an editor that is built
# as the app builds it: the window, the gesture tracker and the pane are on the
# way. Alt means "select, do not act" (D10): a plain click does what the part does,
# an Alt+click always puts the caret at the character, and an Alt+double click
# always selects the innermost part as a whole.
#
# For each point, the expected part comes from two sources that the readers
# under test do not decide:
#
# - the forward map: each part of the document maps forward to the node that
#   draws it, so every part whose node draws the element under the point is a
#   part that the answer must lie inside;
# - the drawn caret: an Alt+click on a text puts the caret on the character
#   under the point, and the forward map of that caret draws it there. The glyph
#   of an icon font is a picture, not a text (P4), so it takes no caret.
#
# A plain click on a text does something: it acts, as a control does, chooses a
# part, as a header chooses its line, or puts the caret (D9); a plain click that
# does nothing fails. An Alt+double click at the point selects the part that holds
# the caret of the Alt+click as a whole, a ring or a band of the selection is
# drawn at the point, and the mouse target of a move there names the same part. A
# text of only whitespace draws nothing, so it is an empty area: a band hugs the
# characters that draw, so the mark of the part that the Alt+double click selects
# there can lie beside the point, and that part can hold the part of the caret and
# of the move, as a leaf holds the space around its operator.

import ProjecturedKernelExample: HeadlessBackend, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display

_pc_read_value(value) = value isa AbstractCell ? _pc_read_value(value[]) : value

_pc_strip_types(reference) = reference isa Reference ? strip_reference_types(reference) : reference

_pc_extend_reference(reference, steps...) =
    concat_references(reference, extend_reference(EmptyReference(), steps...))

_pc_is_in_box(box, x, y) = box.x <= x < box.x + box.width && box.y <= y < box.y + box.height

_pc_get_center(box) = (box.x + box.width ÷ 2, box.y + box.height ÷ 2)

_pc_is_within(prefix, path) = prefix == path || is_reference_prefix(prefix, path)

# A drawn element: the node, its reference in the output of the editor, its box in
# the frame of its window, and the canvases and viewports above it.
struct _PcElement
    node::Any
    reference::Reference
    box::NamedTuple
    above::Vector{Any}
end

# Every element that draws something, in the order of the paint, so the last one
# whose box holds a point is the one on top there. A `GraphicsPointerShape` sets
# the shape of the pointer over its box and draws nothing. `keep` leaves out an
# element before its box is measured.
function _pc_collect_elements!(found, output, window_box, node, reference, above, depth = 0;
                               keep = _ -> true)
    depth > 40 && return found
    node = _pc_read_value(node)
    if node isa GraphicsCanvas
        inner = vcat(above, Any[node])
        elements = _pc_read_value(getfield(node, :elements))
        elements isa Union{AbstractVector, CellVector} || return found
        for k in 1:length(elements)
            element = _pc_read_value(elements[k])
            element isa ListNode && continue
            _pc_collect_elements!(found, output, window_box, element,
                                  _pc_extend_reference(reference, FieldReferenceStep("elements"),
                                                       ElementReferenceStep(k)),
                                  inner, depth + 1; keep)
        end
    elseif node isa GraphicsViewport
        _pc_collect_elements!(found, output, window_box, getfield(node, :content),
                              _pc_extend_reference(reference, FieldReferenceStep("content")),
                              vcat(above, Any[node]), depth + 1; keep)
    elseif node isa GraphicsDocument && !(node isa GraphicsPointerShape) && keep(node)
        box = try
            find_reference_box(output, reference; visible = true)
        catch
            nothing
        end
        (box === nothing || box.width <= 0 || box.height <= 0) && return found
        push!(found, _PcElement(node, reference, (x = box.x - window_box.x, y = box.y - window_box.y,
                                                  width = box.width, height = box.height), above))
    end
    found
end

# Whether `node` marks the selection: a ring, an outline in the colour of the
# selection ring or of the focus ring, which a control draws when it is selected,
# or a band, a fill in the colour of the selection band.
function _pc_is_selection_mark(node)
    node isa GraphicsRect || return false
    theme = get_theme_defaults(GraphicsTheme)
    focus = get_theme_defaults(WidgetTheme).ring
    is_same(a, b) = a.red == b.red && a.green == b.green && a.blue == b.blue
    fill = _pc_read_value(node.color)
    border = _pc_read_value(node.border_color)
    (Int(_pc_read_value(node.border_width)) > 0 && (is_same(border, theme.selection_ring) || is_same(border, focus))) ||
        (fill.alpha > 0 && is_same(fill, theme.selection_band))
end

# Whether a mark of the selection that the output draws now holds the point, or,
# with `anywhere`, whether the output draws a mark of the selection at all.
function _pc_is_selection_drawn(session, x, y; anywhere::Bool = false)
    output = _pc_read_value(get_iomap_output(session.editor.iomap))
    window = _pc_read_value(_pc_read_value(output.windows)[1])
    marks = _pc_collect_elements!(_PcElement[], output, session.window_box, _pc_read_value(window.content),
                                  session.window_reference, Any[]; keep = _pc_is_selection_mark)
    anywhere ? !isempty(marks) : any(mark -> _pc_is_in_box(mark.box, x, y), marks)
end

# Whether the element is the glyph of an icon font: a text of only characters of
# the private use area of Unicode, where an icon font such as Lucide keeps its
# pictures.
function _pc_is_icon_glyph(node)
    node isa GraphicsText || return false
    text = String(_pc_read_value(node.text))
    !isempty(text) && all(character -> 0xe000 <= UInt32(character) <= 0xf8ff, text)
end

# Whether the element is a text of only whitespace, which draws nothing.
_pc_is_blank_text(node) = node isa GraphicsText && all(isspace, String(_pc_read_value(node.text)))

# The element on top at a point of the window.
function _pc_find_top(elements, x, y)
    top = nothing
    for element in elements
        _pc_is_in_box(element.box, x, y) && (top = element)
    end
    top
end

# The node that a forward image reaches, and whether the image names a range
# inside that node, such as characters of a text, rather than the node.
function _pc_find_image_node(output, image)
    image === nothing && return (nothing, false)
    steps = collect(get_reference_steps(strip_reference_types(image)))
    for cut in 0:min(length(steps), 3)
        path = extend_reference(EmptyReference(), steps[1:(end - cut)]...)
        node = try
            _pc_read_value(evaluate_reference(output, path))
        catch
            nothing
        end
        node isa GraphicsDocument && return (node, cut > 0)
    end
    (nothing, false)
end

# Whether the last step of `path`, also inside a step that a projection
# introduced, names a place inside a value: a caret or a range of a text.
function _pc_is_place(path)
    path isa ConcreteReference || return false
    steps = collect(get_reference_steps(path))
    step = last(steps)
    step isa ProjectionReferenceStep && return _pc_is_place(step.output_path)
    step isa RangeReferenceStep && return step.stop != step.start + 1
    nameof(typeof(step)) in (:TextRangeReferenceStep, :TextSpanReferenceStep, :TextColumnReferenceStep)
end

# `path` without the place at its end: the part that holds a caret.
function _pc_cut_place(path)
    path isa ConcreteReference || return path
    steps = collect(get_reference_steps(path))
    step = last(steps)
    head = extend_reference(EmptyReference(), steps[1:(end - 1)]...)
    if step isa ProjectionReferenceStep
        # An output path that loses every step names the node that printed it.
        inner = _pc_cut_place(step.output_path)
        inner isa EmptyReference && return head
        return _pc_extend_reference(head, ProjectionReferenceStep(step.projection, inner))
    end
    _pc_is_place(path) ? head : path
end

# `path` with no node types, also inside the output path of an introduced step.
function _pc_normalize(path)
    path isa Reference || return path
    steps = map(collect(get_reference_steps(strip_reference_types(path)))) do step
        step isa ProjectionReferenceStep ?
            ProjectionReferenceStep(step.projection, _pc_normalize(step.output_path)) : step
    end
    extend_reference(EmptyReference(), steps...)
end

# Whether two paths name the same part, whatever node types they carry.
_pc_is_same_part(a, b) = _pc_normalize(a) == _pc_normalize(b)

# Whether the part `outer` holds the part `inner` or is it, whatever node types they
# carry, also inside a step that a projection introduced at the same place.
function _pc_is_part_within(outer, inner)
    (outer isa Reference && inner isa Reference) || return false
    a = collect(get_reference_steps(_pc_normalize(outer)))
    b = collect(get_reference_steps(_pc_normalize(inner)))
    length(a) <= length(b) || return false
    for i in eachindex(a)
        a[i] == b[i] && continue
        (i == length(a) && a[i] isa ProjectionReferenceStep && b[i] isa ProjectionReferenceStep &&
         a[i].projection == b[i].projection) || return false
        return _pc_is_part_within(a[i].output_path, b[i].output_path)
    end
    true
end

_pc_format_step(step::ProjectionReferenceStep) =
    string("‹", nameof(typeof(_pc_read_value(step.projection))), " ", _pc_format_path(step.output_path), "›")
_pc_format_step(step) = string(extend_reference(EmptyReference(), step))

_pc_format_path(path) = path isa ConcreteReference ?
    join(_pc_format_step.(get_reference_steps(strip_reference_types(path)))) : string(path)

# `path` after the steps of `base`, as `@` and the rest.
function _pc_format_relative(path, base)
    path isa ConcreteReference || return string(path)
    steps = collect(get_reference_steps(strip_reference_types(path)))
    head = base isa ConcreteReference ? collect(get_reference_steps(base)) : ReferenceStep[]
    (length(steps) >= length(head) && steps[1:length(head)] == head) || return "/" * _pc_format_path(path)
    "@" * _pc_format_path(extend_reference(EmptyReference(), steps[(length(head) + 1):end]...))
end

# The parts of the document, each as a path from the root of the editor with the
# node that its forward image reaches. A forward image that ends in a region, the
# box around a range over several segments such as an object of several lines,
# takes no part: its box holds points that the range does not.
function _pc_collect_parts(editor, document, base, output; limit = 3000)
    parts = Any[]
    matches = search_references(document, _ -> true; limit, maxvisits = 200_000)
    for part in Reference[EmptyReference(); collect(matches)]
        path = concat_references(base, _pc_strip_types(part))
        image = try
            map_reference_forward(editor.projection, editor.iomap, annotate_reference_types(editor.document, path))
        catch
            nothing
        end
        node, is_range = _pc_find_image_node(output, image)
        node === nothing && continue
        any(step -> step isa RegionReferenceStep, get_reference_steps(strip_reference_types(image))) && continue
        box = is_range ? (try find_reference_box(output, image; visible = true) catch; nothing end) : nothing
        push!(parts, (path = path, node = node, is_range = is_range, box = box))
    end
    parts
end

# The parts whose image draws `element` at the point (sx, sy) of the screen.
function _pc_find_drawing_parts(parts, element, sx, sy)
    found = Reference[]
    for part in parts
        (part.node === element.node || any(node -> node === part.node, element.above)) || continue
        part.is_range && (part.box === nothing || !_pc_is_in_box(part.box, sx, sy)) && continue
        push!(found, part.path)
    end
    found
end

# Whether `operation`, or a member of it, is the action of a control rather than
# a path, a write of view state, a timer of the gesture tracker or nothing.
function _pc_is_action(operation)
    operation === nothing && return false
    operation isa CompoundOperation && return any(_pc_is_action, operation.operations)
    operation isa ReplaceViewStateOperation && return false
    # A press that selects a document and shows it, as a link does, acted.
    operation isa ShowSelectionOperation && return true
    occursin("Timer", string(nameof(typeof(operation)))) && return false
    operation isa WrappingOperation && return _pc_is_action(get_wrapped_operation(operation))
    !(operation isa ReplacePathOperation || operation isa DoNothingOperation)
end

# One event, then frames until the editor is idle: the last operation that a
# frame applied, or `nothing`.
function _pc_send!(session, event)
    editor = session.editor
    push_event!(editor.backend, WindowInput(session.window_id, event))
    applied = nothing
    for _ in 1:4
        run_frame!(editor)
        editor.operation === nothing || (applied = editor.operation)
        editor.wake_pending[] = false
    end
    applied
end

# A press and a release at (x, y). The times of the events lie in the past, 10
# seconds apart: the gesture tracker answers a release with a timer, and gives the
# click only when the timer is due by the wall clock, because a second press could
# still make a double click. So each timer is due at once, and no two presses
# make a double click.
function _pc_press!(session, x, y, modifiers)
    session.clock[] += 10.0
    _pc_send!(session, MouseDown(:left, x, y, modifiers; time = session.clock[]))
    up = _pc_send!(session, MouseUp(:left, x, y, modifiers; time = session.clock[] + 0.01))
    (up = up, selection = _pc_strip_types(get_selection(session.editor.document)))
end

# A double click at (x, y): two presses 0.05 s apart, which the gesture tracker
# makes a click of count 2.
function _pc_double_press!(session, x, y, modifiers)
    session.clock[] += 10.0
    t = session.clock[]
    _pc_send!(session, MouseDown(:left, x, y, modifiers; time = t))
    _pc_send!(session, MouseUp(:left, x, y, modifiers; time = t + 0.01))
    _pc_send!(session, MouseDown(:left, x, y, modifiers; time = t + 0.05))
    up = _pc_send!(session, MouseUp(:left, x, y, modifiers; time = t + 0.06))
    (up = up, selection = _pc_strip_types(get_selection(session.editor.document)))
end

# A move into (x, y) from outside the window, so the part under the point is
# entered anew: the mouse target that it leaves at the root.
function _pc_move!(session, x, y)
    session.clock[] += 10.0
    _pc_send!(session, MouseMove(-1, -1; time = session.clock[]))
    _pc_send!(session, MouseMove(x, y; time = session.clock[] + 0.01))
    _pc_strip_types(get_mouse_target(session.editor.document))
end

_pc_select!(session, path) =
    evaluate_operation(session.editor, ReplaceSelectionOperation(annotate_reference_types(session.editor.document, path)))

_pc_count!(session, key) = (session.counts[key] = get(session.counts, key, 0) + 1)

# The first frames of `backtrace` in the source of a package, as " at file:line <
# file:line", so a line of failure names where a throw comes from.
function _pc_format_origin(backtrace; count = 3)
    frames = String[]
    for frame in stacktrace(backtrace)
        file = string(frame.file)
        occursin(r"/(source|example)/", file) || continue
        push!(frames, "$(basename(file)):$(frame.line)")
        length(frames) == count && break
    end
    isempty(frames) ? "" : " at " * join(frames, " < ")
end

# The checks at the centre of `element`.
function _pc_check_point!(session, element)
    base = session.base
    x, y = _pc_get_center(element.box)
    top = _pc_find_top(session.elements, x, y)
    top === nothing && return nothing
    drawing = _pc_find_drawing_parts(session.parts, top, x + session.window_box.x, y + session.window_box.y)
    # A part whose image is coarser than the part, such as an open page that maps
    # to the canvas of its whole tabbed pane, also holds the point; the deepest
    # part sets the depth.
    deepest = isempty(drawing) ? base : drawing[argmax(length.(get_reference_steps.(drawing)))]
    what = top.node isa GraphicsText ? repr(String(_pc_read_value(top.node.text))) : string(nameof(typeof(top.node)))
    at = "$(session.label) ($x, $y) on $what"
    blank = _pc_is_blank_text(top.node)
    format(path) = _pc_format_relative(path, base)
    _pc_count!(session, :points)
    text = top.node isa GraphicsText && !_pc_is_icon_glyph(top.node)
    # A plain click does what the part does: it acts, as a control does on the
    # click, which is the release, chooses a part, or puts the caret (D9). On a
    # text it must do something.
    _pc_select!(session, base)
    layout = _pc_get_text_layout(session)
    plain = _pc_press!(session, x, y, ModifierKeys())
    # A press that moves what is drawn, as an option of a toggle group does, acted.
    acted = _pc_is_action(plain.up) || _pc_get_text_layout(session) != layout
    if text && !acted
        if plain.selection === nothing || _pc_is_same_part(plain.selection, base)
            push!(session.failures, "$at: a plain click does nothing: $(format(plain.selection))")
        elseif !_pc_is_within(base, plain.selection)
            push!(session.failures, "$at: a plain click selects $(format(plain.selection)), outside the document")
        elseif _pc_is_place(plain.selection) && !_pc_is_within(deepest, plain.selection)
            push!(session.failures, "$at: the caret $(format(plain.selection)) is not inside $(format(deepest))")
        end
    end
    # An Alt+click puts the caret on the character under the point, whatever the
    # part does, and the caret is drawn there.
    caret = nothing
    if text
        _pc_select!(session, base)
        alt = _pc_press!(session, x, y, ModifierKeys(alt = true))
        if _pc_is_action(alt.up)
            push!(session.failures, "$at: an Alt+click acts")
        elseif !_pc_is_place(alt.selection)
            push!(session.failures, "$at: an Alt+click gives no caret: $(format(alt.selection))")
        else
            caret = alt.selection
            _pc_count!(session, :carets)
            _pc_is_within(deepest, caret) ||
                push!(session.failures, "$at: the caret $(format(caret)) is not inside $(format(deepest))")
            editor = session.editor
            image = try
                map_reference_forward(editor.projection, editor.iomap, annotate_reference_types(editor.document, caret))
            catch
                nothing
            end
            box = image === nothing ? nothing :
                (try find_reference_box(session.output, image; visible = true) catch; nothing end)
            if box === nothing
                push!(session.failures, "$at: the caret $(format(caret)) is not drawn")
            else
                cx = box.x - session.window_box.x
                one = max(2, top.box.width ÷ max(1, length(String(_pc_read_value(top.node.text)))))
                abs(cx - x) <= one + 1 ||
                    push!(session.failures, "$at: the caret is drawn at x = $cx, not at the character")
            end
        end
    end
    # An Alt+double click selects the innermost part: no part that draws the
    # element lies below it, and it is the part that holds the caret of the
    # Alt+click.
    _pc_select!(session, base)
    whole = _pc_double_press!(session, x, y, ModifierKeys(alt = true)).selection
    _pc_count!(session, :wholes)
    if whole === nothing || _pc_is_place(whole)
        push!(session.failures, "$at: an Alt+double click selects no part: $(format(whole))")
    else
        _pc_is_within(deepest, whole) ||
            push!(session.failures, "$at: an Alt+double click selects $(format(whole)), outside $(format(deepest))")
        caret === nothing || _pc_is_same_part(_pc_cut_place(caret), whole) ||
            blank && _pc_is_part_within(whole, _pc_cut_place(caret)) ||
            push!(session.failures, "$at: an Alt+double click selects $(format(whole)), not " *
                                    "$(format(_pc_cut_place(caret))), the part of the caret")
        _pc_is_selection_drawn(session, x, y; anywhere = blank) ||
            push!(session.failures, blank ?
                  "$at: an Alt+double click selects $(format(whole)), and no ring or band is drawn" :
                  "$at: an Alt+double click selects $(format(whole)), and no ring or band holds the point")
    end
    # A move names the part that the Alt+double click selects.
    target = _pc_move!(session, x, y)
    _pc_count!(session, :moves)
    if target === nothing
        push!(session.failures, "$at: a move names no part under the pointer")
    elseif whole !== nothing && !_pc_is_place(whole) && !_pc_is_same_part(_pc_cut_place(target), whole) &&
           !(blank && _pc_is_part_within(whole, _pc_cut_place(target)))
        push!(session.failures, "$at: a move names $(format(target)), not $(format(whole)), " *
                                "the part of the Alt+double click")
    end
    nothing
end

"""
    walk_part_clicks(document, projection; width = 1200, height = 800, limit = 200,
                     label = "", counts = Dict{Symbol,Int}(), remake = nothing) -> Vector{String}

Build an editor on `document` and `projection` as the app builds it, and press a
plain click, an Alt+click, an Alt+double click and a move at the centre of each element that it draws
for `document`, at most `limit` of them. Answer one line for each answer that is
not at the innermost part under the point. `counts` gets the number of the
points, the carets, the whole selections and the moves that the walk checked, so
a caller can assert that it checked something.

The elements of `document` are those below the node of its forward image. A
document with no forward image gets one line and no press: the walk can not tell
its elements from those of the window, such as the close button of a tab. A press
that removes `document` from the editor stops the walk with one line.

A press can change what is drawn, as an option of a toggle group that orders a
view does, and the points after it would press places that moved. So when a
point moves a text, the walk builds the editor again from `remake()`, which
answers a new `(document, projection)` that draws as the first one did, and goes
on with the next point; with no `remake`, it stops with one line.
"""
function walk_part_clicks(document, projection; width = 1200, height = 800, limit = 200, label = "",
                          counts = Dict{Symbol,Int}(), remake = nothing)
    failures = String[]
    opened = _pc_open_session(document, projection, width, height, label, counts, failures)
    opened isa String && return [opened]
    session, shown = opened
    counts[:elements] = length(shown)
    k = 0
    while k < min(length(shown), limit)
        k += 1
        element = shown[k]
        x, y = _pc_get_center(element.box)
        throws(exception) = "$label ($x, $y): throws " * first(sprint(showerror, exception), 300) *
                            _pc_format_origin(catch_backtrace())
        layout = try
            _pc_get_text_layout(session)
        catch exception
            push!(failures, throws(exception) * ", so the walk stops")
            break
        end
        try
            _pc_check_point!(session, element)
        catch exception
            push!(failures, throws(exception))
            _pc_count!(session, :throws)
        end
        if find_document_path(session.root, session.document) === nothing
            push!(failures, "$label ($x, $y): a press removes the document from the editor, so the walk stops")
            break
        end
        # The pointer leaves, so a light that shows a text under it is gone. A press
        # that moved what is drawn needs a new editor for the next point.
        moved = try
            session.clock[] += 10.0
            _pc_send!(session, MouseMove(-1, -1; time = session.clock[]))
            _pc_get_text_layout(session) != layout
        catch exception
            push!(failures, throws(exception) * ", so the walk stops")
            break
        end
        moved || continue
        if remake === nothing
            push!(failures, "$label ($x, $y): a press moves what is drawn, so the walk stops")
            break
        end
        opened = try
            _pc_open_session(remake()..., width, height, label, counts, failures)
        catch exception
            "$label ($x, $y): the editor does not build again: " * first(sprint(showerror, exception), 300)
        end
        opened isa String && (push!(failures, opened); break)
        session, shown = opened
    end
    failures
end

# An editor on `document` and `projection`, with the elements that it draws for
# `document`: `(session, shown)`, or the line of a failure when the walk can not
# press it.
function _pc_open_session(document, projection, width, height, label, counts, failures)
    editor = build_editor(document, projection; backend = HeadlessBackend(),
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "ProjecturEd", width, height))
    run_frame!(editor)
    root = editor.document
    base = find_document_path(root, document)
    base === nothing && return "$label: the document is not in the editor"
    base = _pc_strip_types(base)
    # No ring and no caret is drawn while the elements are collected.
    replace_selection!(root, nothing)
    run_frame!(editor)
    output = _pc_read_value(get_iomap_output(editor.iomap))
    window = _pc_read_value(_pc_read_value(output.windows)[1])
    window_box = (x = Int(_pc_read_value(window.x)), y = Int(_pc_read_value(window.y)))
    window_reference = extend_reference(EmptyReference(), FieldReferenceStep("windows"), ElementReferenceStep(1),
                                        FieldReferenceStep("content"))
    elements = _pc_collect_elements!(_PcElement[], output, window_box, _pc_read_value(window.content),
                                     window_reference, Any[])
    parts = _pc_collect_parts(editor, document, base, output)
    index = findfirst(part -> part.path == base, parts)
    if index === nothing
        counts[:elements] = 0
        return "$label: the document has no forward image, so no element is pressed"
    end
    node = parts[index].node
    shown = filter(element -> element.node === node || any(above -> above === node, element.above), elements)
    session = (; editor, root, document, base, output, window_id = _pc_read_value(window.id), window_box,
               window_reference, elements, parts, failures, counts, label, clock = Ref(time() - 1.0e6))
    (session, shown)
end

# Each text that the window draws now, with its box: two of them differ when a press
# moved what is drawn. A light or a mark of the selection moves no text.
function _pc_get_text_layout(session)
    output = _pc_read_value(get_iomap_output(session.editor.iomap))
    window = _pc_read_value(_pc_read_value(output.windows)[1])
    texts = _pc_collect_elements!(_PcElement[], output, session.window_box, _pc_read_value(window.content),
                                  session.window_reference, Any[]; keep = node -> node isa GraphicsText)
    [(String(_pc_read_value(text.node.text)), text.box) for text in texts]
end

"""
    test_part_click(example; limit = 200, broken = nothing)

Run [`walk_part_clicks`](@ref) on `example`, print each failure, and assert that
the walk pressed a point and that no answer is outside the innermost part.
`broken` is a predicate of a line of failure, or `nothing`: the failures that it
names are known, and they count as one broken assertion.
"""
function test_part_click(example; limit = 200, broken = nothing)
    @testset "a click reaches the innermost part: $(example.name)" begin
        counts = Dict{Symbol,Int}()
        failures = walk_part_clicks(example.make_document(), example.make_projection();
                                    label = example.name, limit, counts,
                                    remake = () -> (example.make_document(), example.make_projection()))
        known = broken === nothing ? String[] : filter(broken, failures)
        foreach(line -> println("  ", line), setdiff(failures, known))
        @test get(counts, :points, 0) > 0
        @test isempty(setdiff(failures, known))
        isempty(known) || @test_broken isempty(known)
    end
end
