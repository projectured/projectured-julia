# Fragment of `ArrangementModule` — the arrangement of a collection as something
# that code and a language model can change and read: the verbs that filter and
# sort a collection, and the words that say how a collection shows.

"""
    get_arrangement_parts(description) -> Vector

The parts of `description` that a bar shows as chips: the conditions of a filter,
the keys of a sort, and a find, a group and the first items themselves.
"""
get_arrangement_parts(filter::ArrangementFilter) = Any[condition for condition in filter.conditions]
get_arrangement_parts(sort::ArrangementSort) = Any[key for key in sort.keys]
get_arrangement_parts(find::ArrangementFind) = Any[find]
get_arrangement_parts(group::ArrangementGroup) = Any[group]
get_arrangement_parts(first::ArrangementFirst) = Any[first]
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
describe_arrangement_part(group::ArrangementGroup) =
    string("by ", join((_describe_key(key) for key in group.keys), ", "),
           isempty(group.aggregates) ? "" :
               ": " * join((describe_arrangement_part(aggregate) for aggregate in group.aggregates), ", "))
describe_arrangement_part(aggregate::ArrangementAggregate) =
    aggregate.operator === :count ? "count" : string(aggregate.operator, " of ", _describe_key(aggregate.key))
describe_arrangement_part(first::ArrangementFirst) = string("first ", first.count)

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
part of the entry, such as `2 of 3 items: status ≠ "failed", ↑ delay`. A place
with a group says how many groups show, such as `2 groups of 3 items: by status:
count`. With `entry === nothing` every item shows, in its own order.
"""
function describe_arranged_collection(entry, items)
    total = length(items)
    entry === nothing && return string(total, total == 1 ? " item" : " items", ", all in their own order")
    parts = String[describe_arrangement_part(part)
                   for description in entry.projections for part in get_arrangement_parts(description)]
    groups = _count_shown_groups(entry, items)
    shown = groups === nothing ? string(length(compute_shown_rows(entry, items)), " of ", total, " items") :
                                 string(groups, groups == 1 ? " group" : " groups", " of ", total, " items")
    string(shown, isempty(parts) ? "" : ": " * join(parts, ", "))
end

# How many rows of groups the place of `entry` shows; `nothing` with no group.
_count_shown_groups(entry, items) =
    any(description -> description isa ArrangementGroup, entry.projections) ?
        length(collect_shown_items(entry, items)) : nothing

"""
    collect_shown_items(entry, items) -> Vector

What the place of `entry` shows of `items`, in the order in which it shows them:
the items that the filters, the sorts and the first items pick, or, with a group,
the rows of the groups ([`ArrangementGroupRow`](@ref)) that the picks after the
group keep. With `entry === nothing` every item, in its own order.
"""
function collect_shown_items(entry, items)
    entry === nothing && return Any[item for item in items]
    picked = Any[items[r] for r in compute_shown_rows(entry, items)]
    projections = collect(entry.projections)
    g = findfirst(description -> description isa ArrangementGroup, projections)
    g === nothing && return picked
    groups = Any[row for row in compute_group_rows(projections[g], picked)]
    for description in projections[(g + 1):end]
        description isa ArrangementGroup && break
        rows = _compute_description_rows(description, groups)
        rows === nothing || (groups = groups[rows])
    end
    groups
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
    run_on_editor_task!(() -> _arrange_collection!(editor, collection, _make_filter(conditions), "Filter"), editor; description = "filter_collection!")

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
    run_on_editor_task!(() -> _arrange_collection!(editor, collection, _make_sort(keys), "Sort"), editor; description = "sort_collection!")

"""
    group_collection!(collection, keys...; aggregates = [:count], editor = get_evaluation_editor()) -> Text

Show one row for each group of the items of the collection at `collection` that
have the same values at `keys`, with the `aggregates` over the items of each
group, and answer how the collection shows now. The data does not change, and
`group_collection!(collection)` with no key takes the group away. A second call
replaces the group of the first.

A key is the path of a value inside an item, as for `filter_collection!`. An
aggregate is `:count`, or `key => operator`, where the operator is `:sum`,
`:mean`, `:minimum`, `:maximum`, or one that a slice adds
(`compute_arrangement_aggregate`). A filter, a sort and the first items after the
group act on its rows, and a key of a row is the name of a column, such as
`"count"` or `"mean of delay"`.

Use it to count or sum the items of a list by a value they share, such as the
runs of each state, without a change of the data.

# Example

    group_collection!(runs_1, "status"; aggregates = [:count, "delay" => :mean])
    group_collection!(runs_1)           # the runs again, one row each

See also `limit_collection!`, `filter_collection!` and `sort_collection!`.
"""
group_collection!(collection, keys...; aggregates = Any[:count], editor = get_evaluation_editor()) =
    _arrange_collection!(editor, collection, _make_group(keys, aggregates), "Group")

# @optional: the count is what the call says, and a call with no count takes the first
# items away, as a call of `filter_collection!` with no condition takes the filter away.
limit_collection!(collection, count = nothing; editor = get_evaluation_editor()) =
    _arrange_collection!(editor, collection, _make_first(count), "Limit")

# The docstring follows the definition, because the marker above the definition
# is a comment, and Julia drops a docstring that a comment parts from its code.
@doc """
    limit_collection!(collection, count = nothing; editor = get_evaluation_editor()) -> Text

Show only the first `count` items of the collection at `collection`, in the order
that its filter, its sort and its group give, and answer how the collection shows
now. `limit_collection!(collection)` with no count shows every item again. A
second call replaces the count of the first.

Use it to show the few items that a person asks about, such as the ten slowest
runs after a sort.

# Example

    sort_collection!(runs_1, "delay" => :descending)
    limit_collection!(runs_1, 10)
    limit_collection!(runs_1)           # every run again

See also `group_collection!` and `sort_collection!`.
""" limit_collection!

"""
    make_filter_collection_operation(collection, conditions...; editor = get_evaluation_editor())
        -> Operation or nothing

The edit that [`filter_collection!`](@ref) makes, as an operation from the root of
the editor's document, which it does not evaluate; `nothing` when no arrangement
and no tab holds the collection. A caller that runs while the editor evaluates
another operation posts it.
"""
make_filter_collection_operation(collection, conditions...; editor = get_evaluation_editor()) =
    run_on_editor_task!(() -> _make_arrange_operation(editor, collection, _make_filter(conditions), "Filter"), editor; description = "make_filter_collection_operation")

"""
    make_sort_collection_operation(collection, keys...; editor = get_evaluation_editor())
        -> Operation or nothing

The edit that [`sort_collection!`](@ref) makes, as an operation from the root of
the editor's document, which it does not evaluate.
"""
make_sort_collection_operation(collection, keys...; editor = get_evaluation_editor()) =
    run_on_editor_task!(() -> _make_arrange_operation(editor, collection, _make_sort(keys), "Sort"), editor; description = "make_sort_collection_operation")

"""
    make_group_collection_operation(collection, keys...; aggregates = [:count], editor = get_evaluation_editor())
        -> Operation or nothing

The edit that [`group_collection!`](@ref) makes, as an operation from the root of
the editor's document, which it does not evaluate.
"""
make_group_collection_operation(collection, keys...; aggregates = Any[:count], editor = get_evaluation_editor()) =
    _make_arrange_operation(editor, collection, _make_group(keys, aggregates), "Group")

"""
    make_limit_collection_operation(collection, count = nothing; editor = get_evaluation_editor())
        -> Operation or nothing

The edit that [`limit_collection!`](@ref) makes, as an operation from the root of
the editor's document, which it does not evaluate.
"""
# @optional: the count is what the call says, and a call with no count takes the first
# items away, as a call of `filter_collection!` with no condition takes the filter away.
make_limit_collection_operation(collection, count = nothing; editor = get_evaluation_editor()) =
    _make_arrange_operation(editor, collection, _make_first(count), "Limit")

"""
    make_arrangement_entry(at; filter = [], sort = [], group = [], aggregates = [:count], first = nothing)
        -> ArrangementEntry or nothing

The entry at the collection `at` that the verbs make when code calls them in this
order: `filter_collection!` with the conditions of `filter`, `sort_collection!`
with the keys of `sort`, `group_collection!` with the keys of `group` and
`aggregates`, and `limit_collection!` with `first`. Each keyword takes what its
verb takes. `nothing` when every keyword is empty.

Use it to arrange a collection that no frame printed yet, such as one that a new
tab is about to show: put the entry in the `ArrangementDocument` that the tab
shows.
"""
function make_arrangement_entry(at::Reference; filter = Any[], sort = Any[], group = Any[],
                                aggregates = Any[:count], first = nothing)
    descriptions = Any[]
    isempty(filter) || push!(descriptions, _make_filter(filter))
    isempty(sort) || push!(descriptions, _make_sort(sort))
    isempty(group) || push!(descriptions, _make_group(group, aggregates))
    first === nothing || push!(descriptions, _make_first(first))
    isempty(descriptions) ? nothing : ArrangementEntry(strip_reference_types(at), descriptions)
end

_make_filter(conditions) = ArrangementFilter(Any[_make_condition(condition) for condition in conditions])
_make_sort(keys) = ArrangementSort(Any[_make_sort_key(key) for key in keys])
_make_group(keys, aggregates) =
    ArrangementGroup(Any[_make_key(key) for key in keys], Any[_make_aggregate(a) for a in aggregates])
_make_first(::Nothing) = ArrangementFirst(0)
_make_first(count::Integer) = ArrangementFirst(Int(count))
_make_first(count) = throw(ArgumentError("The count of the first items is a whole number, not " * repr(count) * "."))

# An aggregate as code writes it: `:count`, `key => operator`, or an
# `ArrangementAggregate`. An operator with no method of
# `compute_arrangement_aggregate` is refused here, where the code names it.
_make_aggregate(aggregate::ArrangementAggregate) = aggregate
_make_aggregate(operator::Symbol) = _make_aggregate("" => operator)
function _make_aggregate(aggregate::Pair)
    operator = last(aggregate)
    (operator isa Symbol && hasmethod(compute_arrangement_aggregate, Tuple{Val{operator}, Vector{Any}})) ||
        throw(ArgumentError("An aggregate is :count, :sum, :mean, :minimum or :maximum, or an operator " *
                            "that a slice adds, not " * repr(operator) * "."))
    ArrangementAggregate(_make_key(first(aggregate)), operator)
end
_make_aggregate(aggregate) =
    throw(ArgumentError("An aggregate is :count or key => operator, such as \"delay\" => :mean, not " *
                        repr(aggregate) * "."))

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
_get_collection_reference(collection::ReferencedDocument) =
    extend_reference(get_reference(collection), get_arranged_collection_steps(get_document(collection))...)

"""
    get_arranged_collection_steps(document) -> Tuple

The steps from `document` to the collection that it shows, for a document that
shows a collection of its own, as a roster shows its rows: a verb of the
arrangement that a referenced `document` is given arranges that collection. The
default is no step: the document is the collection.
"""
get_arranged_collection_steps(document) = ()

# How the collection at `reference` shows, after an edit of its arrangement.
function _describe_collection_at(root, reference)
    found = find_arranged_collection(root, reference)
    found === nothing && return "The collection is no longer there."
    describe_arranged_collection(found.entry, found.items)
end

"""
    find_arranged_collection(root, reference) -> NamedTuple or nothing

The collection at `reference` in `root` and how it is arranged: `(path, items,
entry)`, the path of the collection from `root` with the step `document` of each
arrangement on it, the collection, and the entry of the nearest arrangement at it
or `nothing`. A path below an arranged document can leave out the step `document`.
`nothing` when the path reaches no collection.
"""
function find_arranged_collection(root, reference::Reference)
    (path, arrangement, at) = _find_arranged_path(root, strip_reference_types(reference))
    items = try_evaluate_reference(root, path, nothing)
    items === nothing && return nothing
    entry = arrangement === nothing ? nothing : _find_entry_at(arrangement.entries, at, Reference)
    (path = path, items = items, entry = entry)
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
            is_fault_exception(exception) || rethrow()
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
