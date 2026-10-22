# Fragment of `ResearchModule` — the edits of a study: the items that the view and
# the assistant make, and the operations that put them into a study.
#
# Each operation is an insert or a delete of an element of a list of the study,
# or a `ReplaceReferencedValueOperation` that carries the item it writes into, or
# a `CompoundOperation` of them. So it passes unchanged through every reader above
# the node it carries, and a history takes it back as one step.

# The fields of an item that hold a text: a string given for one becomes a
# `PrimitiveString`.
const _RESEARCH_TEXT_FIELDS = (:statement, :criterion, :purpose, :citation, :summary, :title,
                               :reason, :caveats)

# The fields of an item that hold one linked item, or `nothing`.
const _RESEARCH_LINK_FIELDS = (:question, :parent, :origin)

# The fields of an item that hold a list of linked items.
const _RESEARCH_LINK_LIST_FIELDS = (:basis, :tests, :uses, :supports, :opposes, :accepts, :rejects)

"""
    find_study_item(study, id) -> item or nothing

The item of `study` whose id is `id`, such as `"H1"`, or `nothing` when the study
holds none.
"""
function find_study_item end

function find_study_item(study::ResearchStudy, id::AbstractString)
    for kind in RESEARCH_KINDS
        startswith(id, kind.letter) || continue
        for item in getproperty(study, kind.field)
            item.id == id && return item
        end
    end
    nothing
end

"""
    collect_research_links(item) -> Vector{Pair{Symbol, Any}}

The links of `item`, as the name of the field `=>` the linked item, in the order
of the fields of its type: `:question => question_1`, `:supports => hypothesis_1`.
"""
function collect_research_links(item::ResearchItem)
    links = Pair{Symbol, Any}[]
    for name in fieldnames(typeof(item))
        if name in _RESEARCH_LINK_FIELDS
            linked = getproperty(item, name)
            linked === nothing || push!(links, name => linked)
        elseif name in _RESEARCH_LINK_LIST_FIELDS
            for linked in getproperty(item, name)
                push!(links, name => linked)
            end
        end
    end
    links
end

"""
    make_research_id(study, type) -> String

The id of the next item of `type` in `study`: the letter of its kind and one more
than the highest number of that kind, such as `"H3"`.
"""
function make_research_id(study::ResearchStudy, type::Type{<:ResearchItem})
    kind = get_research_kind(type)
    highest = 0
    for item in getproperty(study, kind.field)
        number = startswith(item.id, kind.letter) ?
                 tryparse(Int, item.id[nextind(item.id, 0, length(kind.letter) + 1):end]) : nothing
        number === nothing || (highest = max(highest, number))
    end
    kind.letter * string(highest + 1)
end

"""
    make_research_item(study, type; author = :person, time = get_research_time(), fields...)
        -> ResearchItem

A new item of `type` for `study`: the next id of its kind, the author, the time,
and the `fields`. A text field given as a string becomes a `PrimitiveString`. A
link given as an id, such as `supports = ["H1"]`, holds the item of the study that
has the id; an id that the study does not hold throws an `ArgumentError`. The item
is not yet in the study: `make_add_research_item_operation` puts it there.
"""
function make_research_item(study::ResearchStudy, type::Type{<:ResearchItem};
                            author::Symbol = :person, time::AbstractString = get_research_time(),
                            fields...)
    _check_author(author)
    values = Pair{Symbol, Any}[]
    for (name, value) in fields
        hasfield(type, name) ||
            throw(ArgumentError("A " * get_research_kind(type).name * " has no field `" *
                                string(name) * "`."))
        push!(values, name => _make_field_value(study, name, value))
    end
    type(; id = make_research_id(study, type), author, time = String(time), values...)
end

function _make_field_value(study, name::Symbol, value)
    name in _RESEARCH_TEXT_FIELDS && return _make_text(value)
    name in _RESEARCH_LINK_FIELDS && return value === nothing ? nothing : _find_linked_item(study, value)
    name in _RESEARCH_LINK_LIST_FIELDS && return Any[_find_linked_item(study, linked) for linked in value]
    value
end

_find_linked_item(study, item::ResearchItem) = item
function _find_linked_item(study, id::AbstractString)
    item = find_study_item(study, id)
    item === nothing && throw(ArgumentError("The study holds no item " * repr(String(id)) * "."))
    item
end
_find_linked_item(study, value) =
    throw(ArgumentError("A link holds an item of the study or its id, and this is a " *
                        string(nameof(typeof(value))) * "."))

_check_author(author::Symbol) =
    author in RESEARCH_AUTHORS ? author :
        throw(ArgumentError("An item has no author :" * string(author) * "; its authors are :person and :assistant."))

"""
    make_add_research_item_operation(study, item) -> Operation

Append `item` to the list of its kind in `study`.
"""
function make_add_research_item_operation(study::ResearchStudy, item::ResearchItem)
    field = get_research_kind(item).field
    make_insert_elements_operation(Reference(FieldReferenceStep(String(field))),
                                   length(getproperty(study, field)) + 1, Any[item]; root = study)
end

"""
    collect_research_item_holders(study, item) -> Vector

The items of `study` that link to `item`, and the report of the study when it
holds `item`.
"""
function collect_research_item_holders(study::ResearchStudy, item::ResearchItem)
    holders = Any[]
    for other in collect_study_items(study)
        other === item && continue
        any(link -> last(link) === item, collect_research_links(other)) && push!(holders, other)
    end
    study.report !== nothing && _holds_document(study.report, item, IdDict{Any, Bool}()) &&
        push!(holders, study.report)
    holders
end

# Whether the tree under `node` holds `target` itself, at any depth.
function _holds_document(node, target, visited::IdDict)
    node === target && return true
    node isa Document || return false
    haskey(visited, node) && return false
    visited[node] = true
    for name in fieldnames(typeof(node))
        is_view_state_field(name) && continue
        raw = getfield(node, name)
        value = raw isa AbstractCell ? raw[] : raw
        if is_element_collection(value) || value isa AbstractVector
            any(element -> _holds_document(element, target, visited), value) && return true
        elseif _holds_document(value, target, visited)
            return true
        end
    end
    false
end

"""
    make_delete_research_item_operation(study, item) -> Operation

Remove `item` from the list of its kind in `study`. An item that another item
links to, or that the report holds, is not removed: the call throws an
`ArgumentError` that names the items that hold it.
"""
function make_delete_research_item_operation(study::ResearchStudy, item::ResearchItem)
    holders = collect_research_item_holders(study, item)
    isempty(holders) ||
        throw(ArgumentError(item.id * " is held by " *
                            join((holder isa ResearchItem ? holder.id : "the report" for holder in holders), ", ") *
                            "; remove those links first."))
    field = get_research_kind(item).field
    index = findfirst(element -> element === item, collect(getproperty(study, field)))
    index === nothing &&
        throw(ArgumentError("The study holds no item " * repr(item.id) * " in its " * string(field) * "."))
    make_delete_elements_operation(Reference(FieldReferenceStep(String(field))), index; root = study)
end

"""
    make_record_decision_operation(study, decision) -> CompoundOperation

Append `decision` to the decisions of `study`, and write the status of each item
that it accepts or rejects: `:accepted` or `:rejected`. One undo takes the
decision and the statuses back. An item that the decision names must be an item
of the study with a status, and not both accepted and rejected.
"""
function make_record_decision_operation(study::ResearchStudy, decision::ResearchDecision)
    operations = Any[make_add_research_item_operation(study, decision)]
    for (items, status) in ((decision.accepts, :accepted), (decision.rejects, :rejected))
        for item in items
            _check_decided_item(study, decision, item)
            push!(operations, ReplaceReferencedValueOperation(item, "status", status))
        end
    end
    CompoundOperation(operations)
end

function _check_decided_item(study, decision, item)
    item isa ResearchItem && has_research_status(item) ||
        throw(ArgumentError("A decision accepts and rejects items with a status, and this is a " *
                            string(nameof(typeof(item))) * "."))
    any(element -> element === item, collect(getproperty(study, get_research_kind(item).field))) ||
        throw(ArgumentError("The study holds no item " * repr(item.id) * "."))
    any(element -> element === item, collect(decision.accepts)) &&
        any(element -> element === item, collect(decision.rejects)) &&
        throw(ArgumentError("A decision both accepts and rejects " * item.id * "."))
    nothing
end
