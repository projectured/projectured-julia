# Fragment of `WidgetModule` — the keys of a find bar view, and the operations of
# its three states. Each write of a state is view state, so undo keeps no step
# for it. Ctrl+F and Escape are `override` rules: they take their key also after
# the part under the caret answered it, as the find bar of an editor does.

const _FIND_BAR_STEP = FieldReferenceStep("bar")
const _FIND_CONTENT_STEP = FieldReferenceStep("content")

"""
    make_find_bar_show_operation(view::FindBarView) -> operation or nothing

The operation of Ctrl+F: show and expand the bar, and put the caret in it. The
caret goes where the bar keeps it from the last time, or else at the end of the
text of the first stop of the bar, such as the field of the pattern. `nothing`
when the bar is shown and expanded and holds the caret.
"""
function make_find_bar_show_operation(view::FindBarView)
    bar = view.bar
    operations = Any[]
    _get_find_bar_flag(bar, :visible) === false &&
        push!(operations, _write_view_state(bar, "visible", true))
    _get_find_bar_flag(bar, :collapsed) === true &&
        push!(operations, _write_view_state(bar, "collapsed", false))
    if !_is_caret_in_find_bar(view)
        caret = _find_find_bar_caret(bar)
        caret === nothing ||
            push!(operations, ReplaceSelectionOperation(ConcreteReference(_FIND_BAR_STEP, caret)))
    end
    isempty(operations) ? nothing : CompoundOperation(operations)
end

"""
    make_find_bar_hide_operation(view::FindBarView) -> operation or nothing

The operation of Escape with the caret in the bar: hide the bar, and put the
caret back where it was in the content, which keeps it as a dormant selection, or
on the whole content. `nothing` when the caret is not in the bar.
"""
function make_find_bar_hide_operation(view::FindBarView)
    _is_caret_in_find_bar(view) || return nothing
    operations = Any[]
    _get_find_bar_flag(view.bar, :visible) === nothing ||
        push!(operations, _write_view_state(view.bar, "visible", false))
    caret = something(_find_dormant_caret(view.content), EmptyReference())
    push!(operations, ReplaceSelectionOperation(ConcreteReference(_FIND_CONTENT_STEP, caret)))
    CompoundOperation(operations)
end

"""
    make_find_bar_placement_operation(view::FindBarView) -> ReplaceViewStateOperation

The press on the button beside the bar: the bar goes over the content, or back
above it.
"""
make_find_bar_placement_operation(view::FindBarView) =
    _write_view_state(view, "overlaid", !view.overlaid)

# The value of a flag of the bar, or `nothing` when the bar has no such field.
_get_find_bar_flag(bar, name::Symbol) = hasproperty(bar, name) ? getproperty(bar, name) : nothing

# Whether the live caret of the view is in the bar.
function _is_caret_in_find_bar(view::FindBarView)
    selection = get_selection(view)
    selection isa ConcreteReference && get_reference_head(selection) == _FIND_BAR_STEP
end

# Where the caret goes in the bar: where the bar keeps it, or at the end of the
# text of its first stop when that stop is a field with a text, or on that stop.
function _find_find_bar_caret(bar)
    stored = get_stored_selection(bar)
    stored === nothing || return stored
    stop = get_first_focusable_path(bar)
    stop === nothing && return nothing
    field = evaluate_reference(bar, stop)
    field isa ObjectField || return stop
    value = get_object_field_value(field)
    (value isa Union{AbstractString, Real} && !(value isa Bool)) || return stop
    n = length(string(value))
    concat_references(stop, make_object_field_range_reference(field, n, n))
end

# The caret that `side` keeps as a dormant selection, as a path from `side`: its
# own, or the one of the first document below it that keeps one. A caret in the
# bar walks through the object of a field, which can be the content, and writes
# the selection of that object, so the dormant caret of the content can sit lower.
function _find_dormant_caret(side)
    is_live_selection(side) || return get_stored_selection(side)
    holders = search_references(side, node -> node !== side && node isa Document &&
                                              hasproperty(node, :selection) && !is_live_selection(node))
    isempty(holders) && return nothing
    holder = first(holders)
    concat_references(holder, get_stored_selection(evaluate_reference(side, holder)))
end

@gestures FindBarView begin
    override(KeyDown(:f; ctrl)) => "Show the find bar" => make_find_bar_show_operation(doc)
    override(KeyDown(:escape)) => "Hide the find bar" => make_find_bar_hide_operation(doc)
end
