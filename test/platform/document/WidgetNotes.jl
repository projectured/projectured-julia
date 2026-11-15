# Reading what a widget says, for the tests of a control that a projection builds:
# the note that a rest of the pointer on a widget opens, and the widgets of one
# type below a document.

# The content of the one layer that the dwell binding of `document` answers, or
# `nothing` when the binding does not answer.
function _read_widget_note(document)
    operation = read_gesture(document, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

# The widgets of type `T` under `value`, found through the fields of documents, the
# values of cells and the items of vectors, in the order of a walk. A test finds a
# control that a projection builds this way, and reads its note with
# `_read_widget_tooltip`.
function _find_widgets_below(value, ::Type{T}; found = Any[], seen = IdDict{Any,Nothing}(), depth = 60) where {T}
    value isa Cell && (value = value[])
    (depth == 0 || value isa Union{Number, AbstractString, Symbol, Function, Type, Nothing} || haskey(seen, value)) &&
        return found
    seen[value] = nothing
    value isa T && push!(found, value)
    if value isa AbstractVector
        foreach(item -> _find_widgets_below(item, T; found, seen, depth = depth - 1), collect(value))
    elseif value isa Document || value isa LayoutConstraint
        for name in fieldnames(typeof(value))
            name === :tooltip && continue
            _find_widgets_below(getfield(value, name), T; found, seen, depth = depth - 1)
        end
    end
    found
end
