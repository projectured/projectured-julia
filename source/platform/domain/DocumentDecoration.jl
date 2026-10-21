# Fragment of `DomainModule` — what a document says about itself wherever it is
# named: its icon, its conditions, its counts and a line of detail. The rows of a
# tree, the tabs and the items of an address bar draw it the same way. A kind
# names its state as conditions from one list, and the look of each condition is
# defined once, so the same state looks the same in every kind.

"""
    DocumentCondition(name; count = nothing, role = nothing)

One condition of a document: a name from the list of the conditions, such as
`:unsaved`, `:running` or `:failed`, a count when the condition counts something,
such as the open requests of an assistant, and a role that replaces the role of
the condition, such as the role of the result code of an unexpected outcome.

Use it in the `conditions` of a [`DocumentDecoration`](@ref).

# Example

    DocumentCondition(:unexpected; count = 3, role = :warning)

See also `DocumentDecoration` and `get_condition_look`.
"""
struct DocumentCondition
    name::Symbol
    count::Union{Int,Nothing}
    role::Union{Symbol,Nothing}
end

DocumentCondition(name::Symbol; count::Union{Integer,Nothing} = nothing, role::Union{Symbol,Nothing} = nothing) =
    DocumentCondition(name, count === nothing ? nothing : Int(count), role)

"""
    DocumentCount(text; role = nothing)

A count that a document shows after its name, as a pill: its text, such as
"2/4" or "3 FAIL", and its role, one of `:success`, `:warning`, `:error`, `:info`
and `:accent`, or `nothing` for a quiet pill.

Use it in the `counts` of a [`DocumentDecoration`](@ref).

# Example

    DocumentCount("2/4"; role = :accent)

See also `DocumentDecoration`.
"""
struct DocumentCount
    text::String
    role::Union{Symbol,Nothing}
end

DocumentCount(text::AbstractString; role::Union{Symbol,Nothing} = nothing) = DocumentCount(String(text), role)

"""
    DocumentDecoration(; icon, conditions, counts, detail, tooltip, work_item = false)

What a document says about itself wherever it is named: a row of a tree, a tab,
an item of an address bar. `icon` names the kind, a Lucide glyph as a `Symbol`;
a work item, such as a task, names its state here and says `work_item = true`, so
its top left and bottom left corners, which say a state, stay empty, and `:done`
tints its icon. `conditions` are its states,
from the list of the conditions ([`get_condition_look`](@ref)). `counts` are pills
after the name. `detail` is a line of dim text after the name, and `tooltip` more
text, after the conditions in words.

A decoration is never stored: a kind computes it from the state that it owns,
in [`get_document_decoration`](@ref), and a place that draws it follows that
state.

# Example

    DocumentDecoration(; icon = :file, conditions = [DocumentCondition(:unsaved)],
                       detail = "source/platform")

See also `get_document_decoration`, `DocumentCondition` and `DocumentCount`.
"""
struct DocumentDecoration
    icon::Union{Symbol,Nothing}
    conditions::Vector{DocumentCondition}
    counts::Vector{DocumentCount}
    detail::String
    tooltip::Any
    work_item::Bool
end

DocumentDecoration(; icon::Union{Symbol,Nothing} = nothing,
                   conditions::AbstractVector = DocumentCondition[],
                   counts::AbstractVector = DocumentCount[],
                   detail::AbstractString = "", tooltip = nothing, work_item::Bool = false) =
    DocumentDecoration(icon, DocumentCondition[conditions...], DocumentCount[counts...], String(detail), tooltip,
                       work_item)

"""
    get_document_decoration(document) -> DocumentDecoration

What `document` says about itself wherever it is named: its icon, its
conditions, its counts and its detail. A slice that owns a kind of document adds
a method that reads the state of the document, so the rows, the tabs and the
address items that name it follow that state. The default answers the decoration
of the document that a layer holds for a person to edit (`get_edited_field`), and
an empty decoration for any other document.

Use it to know how a document shows its state, such as whether a file has
unsaved edits.

# Example

    get_document_decoration(get_session_task_group_list())

See also `DocumentDecoration`, `get_condition_look` and `format_decoration_words`.
"""
function get_document_decoration end

function get_document_decoration(document)
    field = get_edited_field(document)
    field === nothing && return DocumentDecoration()
    get_document_decoration(getproperty(document, field))
end

"""
    ConditionLook(place, glyph, role, words)

How a condition looks wherever a document is named: its `place`, a corner of the
icon (`:top_left`, `:top_right`, `:bottom_left`, `:bottom_right`), `:after_name`
for a fact of a kind, or `:none`; its `glyph`, a Lucide glyph, or `nothing` for a
condition that shows its count only; the `role` of the tint and of the mark; and
its `words` in a tooltip.

See also `get_condition_look`.
"""
struct ConditionLook
    place::Symbol
    glyph::Union{Symbol,Nothing}
    role::Union{Symbol,Nothing}
    words::String
end

"""
    get_condition_look(::Val{name}) -> ConditionLook

How the condition `name` looks. The platform answers the conditions of
[`DOCUMENT_CONDITIONS`](@ref): each corner of the icon has one meaning in every
kind. The top left says the work that goes on now, the top right what waits for
an answer of the person, the bottom left what went wrong, and the bottom right
the document against its source. A package adds a method for a fact of its own
kind, which shows after the name, or at the corner whose meaning it has. An
unknown condition has no look.

Use it to know where and how a condition shows.

# Example

    get_condition_look(Val(:unsaved))

See also `DocumentCondition` and `DOCUMENT_CONDITIONS`.
"""
function get_condition_look end

get_condition_look(::Val) = ConditionLook(:none, nothing, nothing, "")
get_condition_look(::Val{:failed}) = ConditionLook(:bottom_left, :x, :error, "failed")
get_condition_look(::Val{:waiting}) = ConditionLook(:top_right, nothing, :warning, "waits for you")
get_condition_look(::Val{:unexpected}) = ConditionLook(:bottom_left, :warning, :warning, "not as expected")
get_condition_look(::Val{:running}) = ConditionLook(:top_left, :loader, :accent, "running")
get_condition_look(::Val{:conflict}) =
    ConditionLook(:bottom_right, :warning, :warning, "unsaved edits, and the file changed on disk")
get_condition_look(::Val{:changed_on_disk}) = ConditionLook(:bottom_right, :refresh, :info, "changed on disk")
get_condition_look(::Val{:done}) = ConditionLook(:none, nothing, :success, "done")
get_condition_look(::Val{:unsaved}) = ConditionLook(:bottom_right, :dot, nothing, "unsaved edits")
get_condition_look(::Val{:read_only}) = ConditionLook(:bottom_right, :lock, nothing, "read only")
get_condition_look(::Val{:filtered}) = ConditionLook(:bottom_right, :funnel, nothing, "filtered")
get_condition_look(::Val{:pending}) = ConditionLook(:top_left, :hourglass, nothing, "not started")
get_condition_look(::Val{:stopped}) = ConditionLook(:none, nothing, nothing, "stopped")

"""
    DOCUMENT_CONDITIONS

The conditions of the platform, in their order: the tint of a decoration is the
role of the first condition that holds and has a role, and a corner shows the
first condition that holds and goes there. A condition of a package comes after
them.
"""
const DOCUMENT_CONDITIONS = (:failed, :waiting, :unexpected, :running, :conflict, :changed_on_disk, :done,
                             :unsaved, :read_only, :filtered, :pending, :stopped)

# The conditions of `decoration` in the order of `DOCUMENT_CONDITIONS`, and those
# of a package after them in their own order.
function _sort_decoration_conditions(decoration::DocumentDecoration)
    rank(condition) = something(findfirst(==(condition.name), DOCUMENT_CONDITIONS), length(DOCUMENT_CONDITIONS) + 1)
    sort(decoration.conditions; by = rank)
end

# The role of `condition`: its own, else the role of its look.
_get_condition_role(condition::DocumentCondition) =
    something(condition.role, Some(get_condition_look(Val(condition.name)).role))

"""
    find_decoration_tint(decoration) -> Symbol or nothing

The role of the tint of the icon of `decoration`: the role of the first of its
conditions, in the order of [`DOCUMENT_CONDITIONS`](@ref), that has a role and
tints. `:done` tints only the icon of a work item, which names its state, so any
other decoration passes it by. `nothing` for no tint.

See also `collect_decoration_marks`.
"""
function find_decoration_tint end

const _TINTING_CONDITIONS = (:failed, :waiting, :unexpected, :running, :conflict, :changed_on_disk, :done)

function find_decoration_tint(decoration::DocumentDecoration)
    for condition in _sort_decoration_conditions(decoration)
        condition.name in _TINTING_CONDITIONS || continue
        condition.name === :done && !decoration.work_item && continue
        role = _get_condition_role(condition)
        role === nothing || return role
    end
    nothing
end

"""
    find_shared_decoration_tint(documents) -> Symbol or nothing

The tint that the decorations of all of `documents` share
([`find_decoration_tint`](@ref)), or `nothing` when one has another tint, one
has none, or there is no document. A count of documents, such as the pill of a
roster, takes it, so the pill of a list of tasks that all run has the colour of a
task that runs.

Use it to colour a count of documents by what the documents are.

# Example

    find_shared_decoration_tint(collect(roster.rows))

See also `find_decoration_tint`.
"""
function find_shared_decoration_tint end

function find_shared_decoration_tint(documents)
    tint = nothing
    for (k, document) in enumerate(documents)
        role = find_decoration_tint(get_document_decoration(document))
        role === nothing && return nothing
        k == 1 ? (tint = role) : (role === tint || return nothing)
    end
    tint
end

"""
    collect_decoration_marks(decoration) -> NamedTuple

The marks of the icon of `decoration`: for each corner, `top_left`, `top_right`,
`bottom_left` and `bottom_right`, the first of its conditions that goes there, as
`(glyph, count, role)`, or `nothing`; and `after_name`, the facts of a kind that
show after the name, each as `(glyph, role)`. A corner shows the count of a
condition that has one, else its glyph. The top left and the bottom left corners
of a work item stay empty, because its icon names its state.

See also `find_decoration_tint` and `format_decoration_words`.
"""
function collect_decoration_marks end

function collect_decoration_marks(decoration::DocumentDecoration)
    corners = Dict{Symbol,Any}(:top_left => nothing, :top_right => nothing,
                               :bottom_left => nothing, :bottom_right => nothing)
    after_name = Any[]
    for condition in _sort_decoration_conditions(decoration)
        look = get_condition_look(Val(condition.name))
        role = _get_condition_role(condition)
        if look.place === :after_name
            look.glyph === nothing || push!(after_name, (glyph = look.glyph, role = role))
        elseif haskey(corners, look.place) && corners[look.place] === nothing
            (look.glyph === nothing && condition.count === nothing) && continue
            look.place in (:top_left, :bottom_left) && decoration.work_item && continue
            corners[look.place] = (glyph = look.glyph, count = condition.count, role = role)
        end
    end
    (top_left = corners[:top_left], top_right = corners[:top_right],
     bottom_left = corners[:bottom_left], bottom_right = corners[:bottom_right], after_name = after_name)
end

"""
    collect_decoration_conditions(decoration) -> Vector{DocumentCondition}

The conditions of `decoration` that a person reads in words, in the order of
[`DOCUMENT_CONDITIONS`](@ref): each one whose look has words. A tooltip says
them, each with its count when it has one.

See also `format_decoration_words`.
"""
collect_decoration_conditions(decoration::DocumentDecoration) =
    DocumentCondition[condition for condition in _sort_decoration_conditions(decoration)
                      if !isempty(get_condition_look(Val(condition.name)).words)]

"""
    format_decoration_words(decoration) -> String

The conditions of `decoration` in words, one line each, with the count of a
condition that has one, then its tooltip: the text of the tooltip of a row or a
tab, which says also a condition that no corner shows.

See also `collect_decoration_marks`.
"""
function format_decoration_words end

function format_decoration_words(decoration::DocumentDecoration)
    lines = String[]
    for condition in collect_decoration_conditions(decoration)
        words = get_condition_look(Val(condition.name)).words
        push!(lines, condition.count === nothing ? words : string(words, ": ", condition.count))
    end
    decoration.tooltip isa AbstractString && !isempty(decoration.tooltip) && push!(lines, decoration.tooltip)
    join(lines, "\n")
end
