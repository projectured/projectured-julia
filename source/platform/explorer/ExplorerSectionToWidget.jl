# Fragment of `ExplorerModule` — the page of a section: its title, and a card for
# each entry, with the name of the entry, and the first children of the entry
# below it. Each name is a link to its page.
#
#     title<rest>    children[1].content<rest>

"""
    ExplorerSectionToWidget(; gap, limit)

Draw an [`ExplorerSection`](@ref) as its page: a field with its title, and a card
for each entry, with the name of the entry as the title of the card, and the
first `limit` children of the entry as lines in the card. The title and each line
are links: a press opens the page in the navigator around the page, and
Ctrl+press opens it in a new tab. The page follows the entries, so an entry that
comes or goes shows or leaves at once. A section with no entry says so. A key in
the field edits the title, which F2 on the node of the section reaches.
"""
@projection UntrackedCell struct ExplorerSectionToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
    limit::Int = 5
end

function print_document(p::ExplorerSectionToWidget, recursion, section::ExplorerSection, context)
    body = VerticalLayout(Any[]; gap = p.gap, child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        entries = section.entries
        isempty(entries) && return Cell[Cell(WidgetLabel("This section has no entry."))]
        Cell[Cell(_make_entry_card(p, section, k, entries[k])) for k in eachindex(entries)]
    end)
    title = WidgetText(""; width = _TITLE_FIELD_WIDTH)
    set_cell_computation!(getfield(title, :content), () -> String(section.title))
    set_output_path_computations!(title, section, path -> _map_title_field_path(path))
    root = VerticalLayout(Any[title, LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          horizontal_align = :left, gap = p.gap)
    iomap = ChildrenIoMap(p, section, root, Cell(Any[]))
    # The part under the pointer, so a link lights and takes a press, and the
    # selection, so a key goes to the field of the title that holds the caret.
    set_output_path_computations!(root, section, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

const _TITLE_FIELD_WIDTH = 240

# The place in the field of the title that a path of the section names:
# `title<rest>` is `content<rest>`.
function _map_title_field_path(reference)
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    steps[1] == FieldReferenceStep("title") || return nothing
    extend_reference(EmptyReference(), FieldReferenceStep("content"), steps[2:end]...)
end

function map_reference_forward(p::ExplorerSectionToWidget, iomap, reference)
    field = _map_title_field_path(reference)
    (field === nothing || iomap === nothing) &&
        return invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
    annotate_reference_types(iomap.output, extend_reference(EmptyReference(), FieldReferenceStep("children"),
                                                            RangeReferenceStep(0, 1), get_reference_steps(field)...))
end

function map_reference_backward(p::ExplorerSectionToWidget, iomap, reference)
    if reference isa ConcreteReference
        steps = get_reference_steps(strip_reference_types(reference))
        length(steps) >= 3 && steps[1] == FieldReferenceStep("children") && steps[2] == RangeReferenceStep(0, 1) &&
            steps[3] == FieldReferenceStep("content") &&
            return extend_reference(EmptyReference(), FieldReferenceStep("title"), steps[4:end]...)
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# The card of the entry `k`: its name as a link, and a link for each of its first
# children.
function _make_entry_card(p::ExplorerSectionToWidget, section::ExplorerSection, k::Int, entry)
    place = _make_steps(FieldReferenceStep("entries"), ElementReferenceStep(k))
    title = _make_section_link(section, format_tree_node_label(entry), place)
    lines = Any[_make_section_link(section, format_tree_node_label(child), concat_references(place, reference))
                for (reference, child) in collect_tree_children(entry; limit = p.limit)]
    tooltip = make_decoration_note(get_document_decoration(entry))
    isempty(lines) && return WidgetCard(; title, tooltip)
    WidgetCard(; title, content = VerticalLayout(lines; child_width = Fill), tooltip)
end

# A link to the part at `reference` from `section`.
_make_section_link(section::ExplorerSection, text::AbstractString, reference::Reference) =
    WidgetLink(text, DocumentLocator(section, reference))

# A section draws as its page inside any document that a renderer draws. The cards
# come back through the recursion of the renderer.
make_graphics_projection(::Type{<:ExplorerSection}; measure, appearance) =
    ChainingProjection(
        ExplorerSectionToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        VerticalLayoutToGraphicsCanvas())
