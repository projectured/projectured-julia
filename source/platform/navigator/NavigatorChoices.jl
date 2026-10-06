# Fragment of `NavigatorModule` — the choices at a step of the address: the other
# parts that the step can name, and the operation that opens a choice in place of
# the step. The rest of the address after the step stays as far as it still reaches
# nodes of the types that it records, so a person compares one part across
# siblings, one choice at a time.

"""
    find_navigator_choices(document, step; query = "", limit = 50) -> Vector{Pair{String,ReferenceStep}}

The choices at `step` of an address, where `document` is the node that `step`
applies to. Each choice is a label and the step that names it; the current step
is one of them. At most `limit` choices.

- For a `FieldReferenceStep`: the fields of `document` that hold a document, in
  the order of the fields, by the title of the document or the name of the field.
  A field of view state is never a choice.
- For a `RangeReferenceStep` in its element form, `[i]`: the elements of
  `document`, by title or by the step, from `limit ÷ 2` elements before the
  current one, up to the first index that reaches no element. No element past
  the last choice is read, so a collection with no end works.

`query` narrows the list: a choice stays when its label holds each word of
`query`, with no case. For an element step, a number `n` gives element `n` alone
when it exists, and other words search the elements from the first, up to
`_CHOICE_SCAN_LIMIT` of them.

A domain adds a method for its own type of `document`, as the data frame adapter
does to name the cells of a row by their columns.
"""
function find_navigator_choices(document, step::FieldReferenceStep; query::AbstractString = "",
                                limit::Integer = _CHOICE_LIMIT)
    words = _get_query_words(query)
    choices = Pair{String,ReferenceStep}[]
    for name in fieldnames(typeof(document))
        length(choices) == limit && break
        is_view_state_field(name) && continue
        choice = FieldReferenceStep(String(name))
        node = try_evaluate_reference(document, Reference(choice), _NOT_REACHED)
        node isa Document || continue
        label = _get_address_label(node, (choice,))
        _is_query_match(label, words) && push!(choices, label => choice)
    end
    choices
end

function find_navigator_choices(document, step::RangeReferenceStep; query::AbstractString = "",
                                limit::Integer = _CHOICE_LIMIT)
    choices = Pair{String,ReferenceStep}[]
    step.stop == step.start + 1 || return choices
    number = tryparse(Int, strip(query))
    if number !== nothing
        choice = RangeReferenceStep(number - 1, number)
        node = number >= 1 ? try_evaluate_reference(document, Reference(choice), _NOT_REACHED) : _NOT_REACHED
        node === _NOT_REACHED || push!(choices, _get_address_label(node, (choice,)) => choice)
        return choices
    end
    words = _get_query_words(query)
    first_index = isempty(words) ? max(1, step.stop - limit ÷ 2) : 1
    for index in Iterators.countfrom(first_index)
        length(choices) == limit && break
        isempty(words) || index - first_index < _CHOICE_SCAN_LIMIT || break
        choice = RangeReferenceStep(index - 1, index)
        node = try_evaluate_reference(document, Reference(choice), _NOT_REACHED)
        node === _NOT_REACHED && break
        label = _get_address_label(node, (choice,))
        _is_query_match(label, words) && push!(choices, label => choice)
    end
    choices
end

find_navigator_choices(document, step; query::AbstractString = "", limit::Integer = _CHOICE_LIMIT) =
    Pair{String,ReferenceStep}[]

# The number of choices that a list shows when it asks for no other number.
const _CHOICE_LIMIT = 50

# The number of elements that a search of words reads at most.
const _CHOICE_SCAN_LIMIT = 1000

_get_query_words(query::AbstractString) = split(lowercase(query))

# Whether `label` holds each of `words`, with no case.
_is_query_match(label::AbstractString, words) =
    all(word -> occursin(word, lowercase(label)), words)

"""
    make_navigator_choice_operation(navigator, index, step) -> Operation or nothing

The operation that opens the page with `step` in place of step `index` of the
page address of `navigator`, as a new visit. The steps after it stay with the
types that the address records, and the page is the longest prefix that still
reaches nodes of those types, so the navigator keeps the part that the person
looks at where the new choice has it. The address keeps the steps that reach no
node, and the types view of the bar marks them. `nothing` when the page does not
change.
"""
function make_navigator_choice_operation(navigator::Navigator, index::Integer, step::ReferenceStep)
    content = navigator.content
    steps = get_reference_steps(get_navigator_page_address(navigator))
    1 <= index <= length(steps) || return nothing
    head = annotate_reference_types(content, extend_reference(EmptyReference(), steps[1:(index - 1)]..., step))
    rest = navigator.address
    for _ in 1:index
        rest = get_reference_tail(rest)
    end
    address = _attach_rest(head, rest)
    page = get_valid_reference_prefix(content, address)
    get_reference_steps(page) == steps && return nothing
    _make_visit_operation(navigator, NavigatorVisit(content, address, page),
                          vcat(navigator.back, _make_current_visit(navigator)), NavigatorVisit[])
end
