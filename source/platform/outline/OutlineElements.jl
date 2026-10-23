# Fragment of `OutlineModule` — the elements of a record: documents of any domain,
# such as code, a page of text, a table or a chart, that a record holds in a list
# field named `elements` and that its row draws after its fields.

const _ELEMENTS_PATH = Reference(FieldReferenceStep("elements"))

"""
    make_add_element_operation(holder, document; index = length(holder.elements) + 1) -> Operation

Insert `document` among the elements of `holder`, a record with a list field
named `elements`, at the 1-based `index`, the end by default. The operation names
`holder`, so it acts the same from any part. The document is put in as it is, so a
document that a note of the clipboard holds stands at two places.
"""
make_add_element_operation(holder, document; index::Integer = length(holder.elements) + 1) =
    make_insert_elements_operation(_ELEMENTS_PATH, index, Any[document]; root = holder)

"""
    make_remove_element_operation(holder, index) -> Operation

Remove the element at the 1-based `index` from the elements of `holder`.
"""
make_remove_element_operation(holder, index::Integer) =
    make_delete_elements_operation(_ELEMENTS_PATH, index; root = holder)

"""
    make_move_element_operation(holder, index, to) -> Operation

Move the element at the 1-based `index` of the elements of `holder` so that it is
the element at `to`: a removal and an insertion of the same document, in one edit.
"""
function make_move_element_operation(holder, index::Integer, to::Integer)
    document = holder.elements[index]
    CompoundOperation(Any[make_remove_element_operation(holder, index),
                          make_add_element_operation(holder, document; index = to)])
end

"""
    make_element_choice_list(holder; place = Any) -> WidgetChoiceList

The list of the kinds of document that can stand as an element, which a person
types into to add a new, empty element to `holder`: the kinds of `is_element_type`,
named by `get_insertion_names`, with the icon of `get_insertion_icon` and the
summary of the docstring of each kind as its note. A choice adds the document
that `make_insertion_document` makes of the kind.
"""
function make_element_choice_list(holder; place::Type = Any)
    find = query -> WidgetChoice[_make_element_choice(T)
                                 for T in find_insertion_choices(Document, query; place, include = is_element_type)]
    WidgetChoiceList(; prompt = "Add", placeholder = "type a kind", empty = "No kind matches", find,
                     choose = T -> make_add_element_operation(holder, make_insertion_document(T)))
end

# The row of the kind `T`: its shortest name, its icon, and the summary of its
# docstring, cut to a short note.
function _make_element_choice(T::Type)
    names = get_insertion_names(T)
    aliases = get_insertion_aliases(T)
    label = isempty(aliases) ? names[min(2, length(names))] : first(aliases)
    note = _cut_note(compute_docstring_summary(T))
    WidgetChoice(uppercasefirst(label); value = T, icon = get_insertion_icon(T),
                 note = isempty(note) ? nothing : note)
end

# The first sentence of `text`, at most 60 characters.
function _cut_note(text::AbstractString)
    sentence = first(split(text, r"(?<=\.)\s"; limit = 2))
    length(sentence) <= 60 ? String(sentence) : String(first(sentence, 59)) * "…"
end

"""
    make_outline_element(outline; content, menu = nothing, revealed = ()) -> WidgetCard

The block of an element in the row of its record: `content`, the document drawn
through the view of its own domain, in a light inset, with the "⋯" of the element
beside it, which shows while the pointer is on the element or the caret is in it.
The block is a `:row` card, so it lights as a row does.
"""
function make_outline_element(outline; content, menu = nothing, revealed = ())
    inset = WidgetCard(; variant = :muted, content, margin = inset_default, border = inset_default,
                       padding = outline.inset_padding)
    parts = Any[LayoutConstraint(inset; width = Fill)]
    menu === nothing || push!(parts, menu)
    block = WidgetCard(; variant = :row, content = HorizontalLayout(parts; gap = outline.meta_gap, vertical_align = :top),
                       margin = inset_default, border = inset_default, padding = inset_default)
    for control in revealed
        _reveal_in_row!(control, block)
    end
    block
end

"""
    get_outline_element_steps() -> Vector

The steps from the block of an element, as `make_outline_element` makes it, to the
element itself, so a domain maps the place of the element in its slots.
"""
get_outline_element_steps() =
    Any[FieldReferenceStep("content"), FieldReferenceStep("children"), RangeReferenceStep(0, 1),
        FieldReferenceStep("child"), FieldReferenceStep("content")]

"""
    make_element_menu(holder, index; open = nothing) -> WidgetMenu

The menu of the element at `index` of the elements of `holder`: Move up and Move
down where it can move, and Remove. `open`, when given, is the operation that
opens the element in a tab of its own.
"""
function make_element_menu(holder, index::Integer; open = nothing)
    count = length(holder.elements)
    items = Any[]
    open === nothing || push!(items, WidgetMenuItem("Open in a tab"; operation = open), WidgetSeparator())
    push!(items, WidgetMenuItem("Move up"; operation = index > 1 ? make_move_element_operation(holder, index, index - 1) : nothing,
                                enabled = index > 1))
    push!(items, WidgetMenuItem("Move down"; operation = index < count ? make_move_element_operation(holder, index, index + 1) : nothing,
                                enabled = index < count))
    push!(items, WidgetSeparator())
    push!(items, WidgetMenuItem("Remove"; operation = make_remove_element_operation(holder, index)))
    WidgetMenu(items)
end

"""
    add_element!(holder, document; editor = get_evaluation_editor()) -> holder

Add `document` to the elements of `holder`, any record with a list field named
`elements`, such as a research item or a workflow step: code, a page of text, a
table or a chart, which the outline of the record draws through its own view.
The document is put in as it is, so a document that another part holds stands at
two places. Answer `holder`.

The edit goes through the readers of the editor when `holder` is a part of a
window, so the history of the tab records it, and Ctrl+Z takes it back.

Use it to keep a document that the work needs beside the record it belongs to.

# Example

    add_element!(step_1, PrimitiveString("a note"))
"""
function add_element!(holder, document; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "add_element!") do
        operation = make_add_element_operation(get_document(holder), get_document(document))
        if holder isa ReferencedDocument && editor isa Editor && editor.iomap !== nothing
            reference = extend_reference(get_reference(holder), FieldReferenceStep("elements"))
            rooted = find_rooted_operation(editor, reference, relative -> operation;
                                           description = "Add an element")
            rooted === nothing || (evaluate_operation(editor, rooted); return holder)
        end
        evaluate_operation(editor, operation)
        holder
    end
end
