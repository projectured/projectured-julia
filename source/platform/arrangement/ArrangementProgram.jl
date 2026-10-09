# Fragment of `ArrangementModule` — the arrangement of a collection as something
# that code and a language model can change and read: the verbs that filter and
# sort a collection, and the words that say how a collection shows.

"""
    get_arrangement_parts(description) -> Vector

The parts of `description` that a bar shows as chips: the conditions of a filter,
the keys of a sort, and a find itself.
"""
get_arrangement_parts(filter::ArrangementFilter) = Any[condition for condition in filter.conditions]
get_arrangement_parts(sort::ArrangementSort) = Any[key for key in sort.keys]
get_arrangement_parts(find::ArrangementFind) = Any[find]
get_arrangement_parts(description) = Any[]

"""
    describe_arrangement_part(part) -> String

A part of an arrangement as a person reads it, as its chip says it: a condition,
such as `status ≠ "failed"`, a key of a sort, such as `↑ delay`, or a find.
"""
describe_arrangement_part(condition::ArrangementCondition) =
    string(_describe_key(condition.key), " ",
           get(_OPERATOR_TEXTS, condition.operator, string(condition.operator)), " ",
           condition.value isa AbstractString ? repr(condition.value) : string(condition.value))
describe_arrangement_part(key::ArrangementSortKey) =
    string(key.direction === :descending ? "↓ " : "↑ ", _describe_key(key.key))
describe_arrangement_part(find::ArrangementFind) = string("find ", repr(string(find.text)))

const _OPERATOR_TEXTS = Dict(:equal => "=", :not_equal => "≠", :less => "<", :greater => ">",
                             :at_most => "≤", :at_least => "≥", :contains => "contains")

# The path of a key as a person reads it: the names of its fields and the numbers
# of its items, "value" for the item itself, or "any value" for any value inside
# the item.
function _describe_key(key)
    key === nothing && return "any value"
    key isa EmptyReference && return "value"
    key isa Reference || return string(key)
    parts = String[]
    for step in get_reference_steps(strip_reference_types(key))
        if step isa FieldReferenceStep
            push!(parts, step.name)
        elseif step isa RangeReferenceStep
            push!(parts, string("[", step.start + 1, "]"))
        end
    end
    replace(join(parts, "."), ".[" => "[")
end

"""
    describe_arranged_collection(entry, items) -> String

How the place of `entry` shows `items`: how many items show, of all, and each
part of the entry, such as `2 of 3 items: status ≠ "failed", ↑ delay`. With
`entry === nothing` every item shows, in its own order.
"""
function describe_arranged_collection(entry, items)
    total = length(items)
    entry === nothing && return string(total, total == 1 ? " item" : " items", ", all in their own order")
    parts = String[describe_arrangement_part(part)
                   for description in entry.projections for part in get_arrangement_parts(description)]
    string(length(compute_shown_rows(entry, items)), " of ", total, " items",
           isempty(parts) ? "" : ": " * join(parts, ", "))
end

"""
    describe_arrangement(arrangement) -> String

How each collection that `arrangement` arranges shows, one after the other: its
path and what [`describe_arranged_collection`](@ref) says of it, such as
`runs: 2 of 3 items: status ≠ "failed", ↑ delay`.
"""
function describe_arrangement(arrangement::ArrangementDocument)
    texts = String[]
    for entry in arrangement.entries
        at = entry.at
        if at isa Reference
            items = try_evaluate_reference(arrangement.document, at, nothing)
            text = items === nothing ? "nothing" : describe_arranged_collection(entry, items)
            push!(texts, at isa EmptyReference ? text : string(_describe_key(at), ": ", text))
        else
            parts = String[describe_arrangement_part(part)
                           for description in entry.projections for part in get_arrangement_parts(description)]
            push!(texts, string("each place of a pattern: ", join(parts, ", ")))
        end
    end
    join(texts, "; ")
end

"""
    filter_collection!(collection, conditions...; editor = get_evaluation_editor()) -> Text

Show only the items of the collection at `collection` for which every condition
holds, in their order, and answer how the collection shows now. The data does not
change: the filter is a part of the arrangement of the document, which the bar of
the collection shows, and Show all or `filter_collection!(collection)` with no
condition takes it away. A second call replaces the conditions of the first.

A condition is `key => comparison`. `key` is the path of a value inside an item: a
field, such as `"status"`, a path of fields, such as `"address.city"`, `""` for
the item itself, or `nothing` for any value inside the item. `comparison` is
`==(value)`, `!=(value)`, `<(value)`, `>(value)`, `<=(value)`, `>=(value)` or
`contains(text)`. A comparison alone is a condition on the item itself.

Use it to show the part of a list, a set of runs or the rows of a table that a
person asks about, without a change of the data.

# Example

    filter_collection!(runs_1, "status" => !=("failed"), "delay" => >(0.2))
    filter_collection!(runs_1)          # every run again

`collection` is a `Reference` from the root of the editor's document, or a
`ReferencedDocument`. A path below an arranged document can leave out the step
`document` of the arrangement, so the same reference works before and after the
first call. Each call is one edit, which the readers of the editor carry as they
carry the edit of a chip that a person presses. It reads the IoMap that the frame
prints, so it runs on the editor's task.

See also `sort_collection!`.
"""
filter_collection!(collection, conditions...; editor = get_evaluation_editor()) =
    _arrange_collection!(editor, collection, _make_filter(conditions), "Filter")

"""
    sort_collection!(collection, keys...; editor = get_evaluation_editor()) -> Text

Show the items of the collection at `collection` in the order of `keys`, and
answer how the collection shows now. The data keeps its own order: the sort is a
part of the arrangement of the document, and `sort_collection!(collection)` with no
key takes it away. A second call replaces the keys of the first.

A key is the path of a value inside an item, as for `filter_collection!`, in
ascending order, or `key => :descending`. Items that are equal in the first key
are in the order of the next key, and else in their own order. Numbers come before
text, and a missing value last.

Use it to put the items of a list, a set of runs or the rows of a table in the
order that a person asks for, without a change of the data.

# Example

    sort_collection!(runs_1, "delay", "id" => :descending)
    sort_collection!(runs_1)            # the runs in their own order

See also `filter_collection!`.
"""
sort_collection!(collection, keys...; editor = get_evaluation_editor()) =
    _arrange_collection!(editor, collection, _make_sort(keys), "Sort")

"""
    make_filter_collection_operation(collection, conditions...; editor = get_evaluation_editor())
        -> Operation or nothing

The edit that [`filter_collection!`](@ref) makes, as an operation from the root of
the editor's document, which it does not evaluate; `nothing` when no arrangement
and no tab holds the collection. A caller that runs while the editor evaluates
another operation posts it.
"""
make_filter_collection_operation(collection, conditions...; editor = get_evaluation_editor()) =
    _make_arrange_operation(editor, collection, _make_filter(conditions), "Filter")

"""
    make_sort_collection_operation(collection, keys...; editor = get_evaluation_editor())
        -> Operation or nothing

The edit that [`sort_collection!`](@ref) makes, as an operation from the root of
the editor's document, which it does not evaluate.
"""
make_sort_collection_operation(collection, keys...; editor = get_evaluation_editor()) =
    _make_arrange_operation(editor, collection, _make_sort(keys), "Sort")

_make_filter(conditions) = ArrangementFilter(Any[_make_condition(condition) for condition in conditions])
_make_sort(keys) = ArrangementSort(Any[_make_sort_key(key) for key in keys])

function _arrange_collection!(editor, collection, description, words::String)
    operation = _make_arrange_operation(editor, collection, description, words)
    operation === nothing &&
        throw(ArgumentError("No arrangement and no tab holds the collection at " *
                            string(strip_reference_types(_get_collection_reference(collection))) *
                            ", so it can not be arranged."))
    evaluate_operation(editor, operation)
    Text(_describe_collection_at(editor.document, _get_collection_reference(collection)))
end

# The edit, read from the collection by the readers of the editor: from the
# collection itself, or from the deepest place above it that a reader follows a
# route into. `nothing` when it comes back as it went, because no reader holds an
# arrangement of the collection or can make one.
function _make_arrange_operation(editor, collection, description, words::String)
    root = editor.document
    (path, _, _) = _find_arranged_path(root, _get_collection_reference(collection))
    place = annotate_reference_types(root, path)
    log = string(words, " ", describe_reference(place, root))
    operation = read_rooted_operation(editor, place, ArrangeCollectionOperation(EmptyReference(), description);
                                      description = log)
    operation isa Operation && !_is_arrange_operation(operation) && return operation
    operation = find_rooted_operation(editor, place, relative -> ArrangeCollectionOperation(relative, description);
                                      description = log)
    (operation === nothing || _is_arrange_operation(operation)) ? nothing : operation
end

_is_arrange_operation(operation) = operation isa ArrangeCollectionOperation ||
    (operation isa WrappingOperation && _is_arrange_operation(get_wrapped_operation(operation)))

_get_collection_reference(collection::Reference) = collection
_get_collection_reference(collection::ReferencedDocument) = get_reference(collection)

# How the collection at `reference` shows, after an edit of its arrangement.
function _describe_collection_at(root, reference)
    (path, arrangement, at) = _find_arranged_path(root, reference)
    items = try_evaluate_reference(root, path, nothing)
    items === nothing && return "The collection is no longer there."
    entry = arrangement === nothing ? nothing : _find_entry_at(arrangement.entries, at, Reference)
    describe_arranged_collection(entry, items)
end

# The path of `reference` in `root`, with the step `document` of each arrangement
# on it where the path leaves it out, the nearest arrangement on it, and the path
# from the document of that arrangement; `(path, nothing, nothing)` when no
# arrangement is on it.
function _find_arranged_path(root, reference::Reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    taken = ReferenceStep[]
    arrangement, base = nothing, 0
    node = root
    i = 1
    while true
        if node isa ArrangementDocument &&
           (i > length(steps) || !(steps[i] == FieldReferenceStep("document") || steps[i] == FieldReferenceStep("entries")))
            push!(taken, FieldReferenceStep("document"))
            arrangement, base = node, length(taken)
            node = node.document
            continue
        end
        i > length(steps) && break
        node isa ArrangementDocument && steps[i] == FieldReferenceStep("document") &&
            ((arrangement, base) = (node, length(taken) + 1))
        push!(taken, steps[i])
        node = try
            evaluate_reference_step(steps[i], node)
        catch exception
            is_passthrough_exception(exception) && rethrow()
            append!(taken, steps[(i + 1):end])
            break
        end
        i += 1
    end
    path = extend_reference(EmptyReference(), taken...)
    arrangement === nothing && return (path, nothing, nothing)
    (path, arrangement, extend_reference(EmptyReference(), taken[(base + 1):end]...))
end

# A condition as code writes it: `key => comparison`, a comparison alone for the
# item itself, or an `ArrangementCondition`.
_make_condition(condition::ArrangementCondition) = condition
_make_condition(condition::Pair) =
    ArrangementCondition(_make_key(first(condition)), _get_comparison(last(condition))...)
_make_condition(comparison) = ArrangementCondition(EmptyReference(), _get_comparison(comparison)...)

# The operator and the value of a comparison with one value.
function _get_comparison(comparison)
    if comparison isa Base.Fix2
        operator = get(_COMPARISON_OPERATORS, comparison.f, nothing)
        operator === nothing || return (operator, comparison.x)
    elseif comparison isa Base.Fix1 && comparison.f === occursin
        return (:contains, comparison.x)
    end
    throw(ArgumentError("A condition compares with one value: ==(value), !=(value), <(value), " *
                        ">(value), <=(value), >=(value) or contains(text), not " * repr(comparison) * "."))
end

const _COMPARISON_OPERATORS = IdDict{Any,Symbol}(
    (==) => :equal, isequal => :equal, (!=) => :not_equal, (<) => :less, (>) => :greater,
    (<=) => :at_most, (>=) => :at_least, contains => :contains)

# A key as code writes it: a path of field names with dots, `""` for the item
# itself, `nothing` for any value inside it, or a reference.
_make_key(key::Nothing) = nothing
_make_key(key::Reference) = strip_reference_types(key)
_make_key(key::Symbol) = _make_key(String(key))
_make_key(key::AbstractString) =
    isempty(key) ? EmptyReference() :
        extend_reference(EmptyReference(), (FieldReferenceStep(String(name)) for name in split(key, '.'))...)
_make_key(key) = throw(ArgumentError("A key is the path of a value inside an item, such as \"status\" or " *
                                     "\"address.city\", not " * repr(key) * "."))

# A key of a sort as code writes it: a key, `key => :ascending` or
# `key => :descending`, or an `ArrangementSortKey`.
_make_sort_key(key::ArrangementSortKey) = key
function _make_sort_key(key::Pair)
    direction = last(key)
    direction in (:ascending, :descending) ||
        throw(ArgumentError("The direction of a sort is :ascending or :descending, not " * repr(direction) * "."))
    ArrangementSortKey(_make_key(first(key)), direction)
end
_make_sort_key(key) = ArrangementSortKey(_make_key(key), :ascending)
