# Fragment of `ExplorerModule` — the view of an explorer: on the left the field of
# the filter, `+` and `▾` above the tree, or above the tree of the matches while
# the filter keeps rows out, and on the right the navigator, each document drawn by
# the row of its own type; and the reader that turns a press on a node into a page
# in the navigator, and reads the keys of the field of the filter.
#
#     filter.text<rest>    elements[1].child.children[1].children[1].content<rest>
#     tree.<rest>          elements[1].child.children[2].children[1].<rest>, while no filter
#     matches.<rest>       elements[1].child.children[2].children[1].<rest>, while a filter
#     navigator.<rest>     elements[2].child.<rest>

"""
    ExplorerToWidget(; gap)

Draw an [`Explorer`](@ref) as a split pane of two sides: on the left the field of
its filter and the buttons `+` and `▾` above its tree, and on the right the
navigator, each document drawn by the row of its own type. The navigator starts
three times as wide as the left side, and a drag of the divider between them
changes the two widths. `gap` separates the parts of the left side. While the
filter keeps rows out, the tree of the matches shows in the place of the tree.

A press on a node selects it, and the navigator shows its page; the keys stay in
the tree, so a person walks the nodes and reads each page. Ctrl+press opens the
page in a new tab, and a double press or Return puts the keyboard in the page.
`+` opens the menu of the kinds to add, as Insert does, and `▾` the menu of the
kinds of the rows that the tree read, which the filter keeps. A key in the field
of the filter edits the filter, Escape there empties it, and Return starts an
[`ExplorerSearch`](@ref) for its text below the node of the page. A visit of the
navigator to a page below the root section, such as by a link on the page, opens
the nodes above that page in the tree.
"""
@projection UntrackedCell struct ExplorerToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

@iomap struct ExplorerToWidgetIoMap
    projection::Any
    input::Any          # Explorer
    output::Any         # WidgetSplitPane
    add::Any            # the Action of `+`
    kinds::Any          # the Action of `▾`
end

_make_steps(steps...) = extend_reference(EmptyReference(), steps...)

_get_child_steps(k::Int) = (FieldReferenceStep("children"), RangeReferenceStep(k - 1, k))

# A side of the split pane: its slot, and the constraint that sets its share.
_get_side_steps(k::Int) = (FieldReferenceStep("elements"), RangeReferenceStep(k - 1, k), FieldReferenceStep("child"))

const _LEFT_STEPS = _get_side_steps(1)
const _BAR_STEPS = (_LEFT_STEPS..., _get_child_steps(1)...)
const _FIELD_STEPS = (_BAR_STEPS..., _get_child_steps(1)...)
const _HOLDER_STEPS = (_LEFT_STEPS..., _get_child_steps(2)...)
const _SHOWN_STEPS = (_HOLDER_STEPS..., _get_child_steps(1)...)
const _NAVIGATOR_STEPS = _get_side_steps(2)
const _FIELD_CONTENT_STEPS = (_FIELD_STEPS..., FieldReferenceStep("content"))

const _FILTER_FIELD_WIDTH = 80

# What the field of the filter says when the pointer rests on it.
_make_filter_field_note() =
    TooltipNote(; title = "Filter", keys = find_bound_keys(Explorer, "Put the keyboard in the filter"),
                text = "Show the rows whose label holds these words.",
                hint = "Return searches below the selected row. Escape clears the filter.")

# What `▾` says when the pointer rests on it: the kinds that the filter keeps.
_make_kinds_note(filter::ExplorerFilter) =
    TooltipNote(; title = "Kinds", text = "Show only the rows of the kinds that you choose.",
                facts = ["Shown" => isempty(filter.kinds) ? "every kind" : join(_format_kind_name.(filter.kinds), ", ")])

function print_document(p::ExplorerToWidget, recursion, explorer::Explorer, context)
    filter = getfield(explorer, :filter)[]
    field = WidgetText(""; width = _FILTER_FIELD_WIDTH, placeholder = "Filter", tooltip = _make_filter_field_note())
    set_cell_computation!(getfield(field, :content), () -> String(filter.text))
    add = Action("Add an entry"; icon = :plus)
    kinds = Action("Keep the rows of some kinds"; icon = :funnel)
    add_note = TooltipNote(; title = "Add an entry", keys = find_bound_keys(Explorer, "Add an entry"),
                           text = "Add an entry after the selected one.",
                           facts = ["Kinds" => join(first.(_collect_entry_kinds()), ", ")])
    bar = GridLayout(Any[field, WidgetToolbarItem(add; tooltip = add_note),
                         WidgetToolbarItem(kinds; tooltip = () -> _make_kinds_note(filter))], 3;
                     horizontal_gap = p.gap, vertical_align = :center, column_policies = Any[Fill, Content, Content])
    # The tree, or the tree of the matches while the filter keeps rows out: the one
    # child of a layout whose children follow, so the other one prints when it
    # comes.
    holder = VerticalLayout(CellVector(@computation Any[something(getfield(explorer, :matches)[],
                                                                  getfield(explorer, :tree)[])]),
                            Cell(:left), Cell(0), Cell(Fill), Cell(Fill), Cell(nothing))
    left = GridLayout(Any[bar, holder], 1; vertical_gap = p.gap, column_policy = Fill,
                      row_policies = Any[Content, Fill])
    output = WidgetSplitPane(:horizontal, Any[LayoutConstraint(left; width = Relative(1)),
                                              LayoutConstraint(getfield(explorer, :navigator)[]; width = Relative(3))])
    iomap = ExplorerToWidgetIoMap(p, explorer, output, add, kinds)
    set_output_path_computations!(output, explorer, path -> map_reference_forward(p, iomap, path); dormant = false)
    # A layout passes a key by its own selection, so each one carries the part of
    # the path of the split pane below it.
    for (widget, steps) in ((left, _LEFT_STEPS), (bar, _BAR_STEPS), (field, _FIELD_STEPS), (holder, _HOLDER_STEPS))
        set_output_path_computations!(widget, output, path -> _find_path_below(path, steps))
    end
    iomap
end

# The rest of `path` after `steps`, or `nothing` when it does not start with them.
function _find_path_below(path, steps)
    for step in steps
        (path isa ConcreteReference && path.head == step) || return nothing
        path = path.tail
    end
    path
end

# Whether the tree of the matches shows in the place of the tree.
_is_match_tree_shown(explorer::Explorer) = getfield(explorer, :matches)[] !== nothing

function map_reference_forward(::ExplorerToWidget, iomap::ExplorerToWidgetIoMap, reference)
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    reference isa ConcreteReference || return nothing
    head = get_reference_head(reference)
    head isa FieldReferenceStep || return nothing
    rest = strip_reference_types(get_reference_tail(reference))
    steps = if head.name == "navigator"
        _NAVIGATOR_STEPS
    elseif head.name in ("tree", "matches")
        (head.name == "matches") == _is_match_tree_shown(iomap.input) || return nothing
        _SHOWN_STEPS
    elseif head.name == "filter"
        (rest isa ConcreteReference && get_reference_head(rest) == FieldReferenceStep("text")) || return nothing
        rest = get_reference_tail(rest)
        _FIELD_CONTENT_STEPS
    else
        return nothing
    end
    annotate_reference_types(iomap.output, concat_references(_make_steps(steps...), rest))
end

function map_reference_backward(::ExplorerToWidget, iomap::ExplorerToWidgetIoMap, reference)
    reference isa ConcreteReference || return EmptyReference()
    path = strip_reference_types(reference)
    rest = _find_path_below(path, _NAVIGATOR_STEPS)
    rest === nothing || return concat_references(_make_steps(FieldReferenceStep("navigator")), rest)
    rest = _find_path_below(path, _SHOWN_STEPS)
    rest === nothing ||
        return concat_references(_make_steps(FieldReferenceStep(_is_match_tree_shown(iomap.input) ? "matches" : "tree")),
                                 rest)
    rest = _find_path_below(path, _FIELD_CONTENT_STEPS)
    rest === nothing || return concat_references(_make_steps(FieldReferenceStep("filter"), FieldReferenceStep("text")), rest)
    EmptyReference()
end

# The steps from the root section to the node of the tree that `path`, from the
# explorer, names; `nothing` for a path that names no node.
function _find_node_steps(path)
    path isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    (length(steps) >= 2 && steps[1] == FieldReferenceStep("tree") && steps[2] == FieldReferenceStep("root")) ||
        return nothing
    steps[3:end]
end

# The steps from the root section to the document of the row that `path`, from the
# explorer, names in the tree or in the tree of the matches; `nothing` for a path
# that names no row.
function _find_shown_node_steps(explorer::Explorer, path)
    steps = _find_node_steps(path)
    steps === nothing || return steps
    path isa ConcreteReference || return nothing
    rest = collect(get_reference_steps(strip_reference_types(path)))
    (length(rest) >= 2 && rest[1] == FieldReferenceStep("matches") && rest[2] == FieldReferenceStep("root")) ||
        return nothing
    matches = getfield(explorer, :matches)[]
    matches === nothing && return nothing
    match = matches.root
    rest = rest[3:end]
    while !isempty(rest)
        (length(rest) >= 2 && rest[1] == FieldReferenceStep("children") && rest[2] isa RangeReferenceStep) ||
            return nothing
        k = rest[2].stop
        1 <= k <= length(match.children) || return nothing
        (match, rest) = (match.children[k], rest[3:end])
    end
    match.steps
end

# Whether the selection of `explorer` is in the field of its filter.
function _is_filter_selected(explorer::Explorer)
    selection = get_selection(explorer)
    selection isa ConcreteReference && get_reference_head(selection) == FieldReferenceStep("filter")
end

# Escape in the field of the filter: the filter is empty, and the node of the page
# of the navigator is selected in the tree.
function _make_clear_filter_operation(explorer::Explorer)
    filter = getfield(explorer, :filter)[]
    page = get_navigator_page_address(getfield(explorer, :navigator)[])
    node = concat_references(_make_steps(FieldReferenceStep("tree"), FieldReferenceStep("root")),
                             strip_reference_types(page))
    CompoundOperation(Any[ReplaceViewStateOperation(CompoundOperation(Any[
                              ReplaceReferencedValueOperation(filter, "text", ""),
                              ReplaceReferencedValueOperation(filter, "kinds", Any[])])),
                          ReplaceSelectionOperation(annotate_reference_types(explorer, node))])
end

# An edit of the field of the filter is view state, as the open nodes and the page
# are, so an undo records none of it.
function _mark_filter_edits(operation)
    operation isa CompoundOperation && return CompoundOperation(Any[_mark_filter_edits(part) for part in operation.operations])
    (operation isa ReplacePathOperation || operation isa WrappingOperation) && return operation
    reference = operation_reference(operation)
    (reference isa ConcreteReference && get_reference_head(reference) == FieldReferenceStep("filter")) ?
        ReplaceViewStateOperation(operation) : operation
end

# What the explorer answers for an answer of its tree or of the tree of the
# matches: a selection of a row shows the page of its document in the navigator
# and keeps the selection in the tree, or with Ctrl opens the page in a new tab; an
# open of a row moves into its page in the navigator; a press on `+` opens the menu
# of the kinds to add, and a press on `▾` the menu of the kinds that the filter
# keeps. `nothing` for any other answer.
function _convert_explorer_answer(iomap::ExplorerToWidgetIoMap, operation, gesture)
    explorer = iomap.input
    navigator = getfield(explorer, :navigator)[]
    if operation isa InvokeActionOperation && operation.action === iomap.add
        # With no node selected, `+` adds at the end of the root section.
        place = something(_find_selected_place(explorer, get_selection(explorer)),
                          _find_entry_place(getfield(explorer, :tree)[].root, ReferenceStep[]))
        return something(_make_add_menu_operation(explorer, place, gesture), DoNothingOperation())
    end
    operation isa InvokeActionOperation && operation.action === iomap.kinds &&
        return _make_kind_menu_operation(explorer, gesture)
    if operation isa ReplaceSelectionOperation
        steps = _find_shown_node_steps(explorer, operation.path)
        steps === nothing && return nothing
        address = _make_steps(steps...)
        gesture isa MouseClick && gesture.modifiers.ctrl &&
            return CompoundOperation(Any[operation, OpenPageOperation(navigator.content, address, :new_tab)])
        visit = make_navigator_open_operation(navigator, address)
        visit === nothing && return nothing
        # The visit writes the navigator, and its selection would leave the tree.
        return CompoundOperation(Any[operation, _get_visit_writes(visit)])
    end
    if operation isa OpenPageOperation && operation.document === nothing
        steps = _find_shown_node_steps(explorer, operation.reference)
        steps === nothing && return nothing
        visit = make_navigator_open_operation(navigator, _make_steps(steps...))
        # The first press of a double press already shows the page, so the open
        # only puts the keyboard in it, as a visit does.
        visit === nothing && (visit = ReplaceSelectionOperation(
            annotate_reference_types(navigator, _make_steps(FieldReferenceStep("content"), steps...))))
        return reroot_operation(visit, (FieldReferenceStep("navigator"),))
    end
    nothing
end

function read_intent(p::ExplorerToWidget, recursion, change::Intent, iomap::ExplorerToWidgetIoMap)
    explorer = iomap.input
    gesture = change.gesture
    # Escape in the field of the filter empties the filter, whatever the field
    # answered.
    change.route === nothing && gesture isa KeyDown && gesture.key === :escape &&
        !_has_modifier_key(gesture.modifiers) && _is_filter_selected(explorer) &&
        return Intent(gesture, _make_clear_filter_operation(explorer), change.description, change.domain)
    # Return there starts a search for its text below the node of the page.
    if change.route === nothing && gesture isa KeyPress && gesture.char == '\n' &&
       !_has_modifier_key(gesture.modifiers) && _is_filter_selected(explorer)
        text = strip(getfield(explorer, :filter)[].text)
        isempty(text) ||
            return Intent(gesture, StartExplorerSearchOperation(explorer, String(text)), change.description,
                          change.domain)
    end
    answer = invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    operation = answer.operation
    operation === nothing && return answer
    # A key that the tree answered reaches the table of the explorer as a claimed
    # key, so only an `override` rule takes it, as the keys that move an entry do.
    if change.route === nothing && gesture isa Union{KeyPress, KeyDown}
        own = read_gesture(explorer, gesture; claimed = operation)
        own === nothing || return Intent(answer.gesture, own, answer.description, answer.domain)
    end
    converted = something(_convert_explorer_answer(iomap, operation, gesture), operation)
    Intent(answer.gesture, _add_tree_reveal(explorer, _mark_filter_edits(converted)), answer.description,
           answer.domain)
end

# An answer that makes the navigator visit a page below the root section, such as a
# link on a page, opens the nodes above that page in the tree too, so its row shows.
function _add_tree_reveal(explorer::Explorer, operation)
    tree = getfield(explorer, :tree)[]
    address = _find_visit_address(getfield(explorer, :navigator)[], tree.root, operation)
    address === nothing && return operation
    reveal = make_tree_reveal_operation(tree, address)
    reveal === nothing ? operation : CompoundOperation(Any[operation, reveal])
end

# The address of the page that `operation` makes `navigator` visit while its content
# is `root`, or `nothing` when it visits no page there.
function _find_visit_address(navigator, root, operation)
    (address, content) = (nothing, navigator.content)
    function visit(part)
        if part isa CompoundOperation
            foreach(visit, part.operations)
        elseif part isa WrappingOperation
            visit(get_wrapped_operation(part))
        elseif part isa ReplaceReferencedValueOperation && part.document === navigator
            steps = get_reference_steps(strip_reference_types(part.reference))
            length(steps) == 1 && steps[1] == FieldReferenceStep("address") && (address = part.value)
            length(steps) == 1 && steps[1] == FieldReferenceStep("content") && (content = part.value)
        end
        nothing
    end
    visit(operation)
    (address isa Reference && content === root) ? address : nothing
end

_has_modifier_key(modifiers) = modifiers.ctrl || modifiers.shift || modifiers.alt || modifiers.meta

# The tree and the navigator come back through the recursion of the renderer,
# which draws each with the row of its own type.
make_graphics_projection(::Type{<:Explorer}; measure, appearance) =
    ChainingProjection(
        ExplorerToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        WidgetSplitPaneToGraphicsCanvas(get_scaled_theme!(appearance, WidgetTheme)))
