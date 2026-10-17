# Fragment of `ExplorerModule` — the page of a section: a card for each entry,
# with the name of the entry, and the first children of the entry below it. Each
# name is a link to its page.

"""
    ExplorerSectionToWidget(; gap, limit)

Draw an [`ExplorerSection`](@ref) as its page: a card for each entry, with the
name of the entry as the title of the card, and the first `limit` children of
the entry as lines in the card. The title and each line are links: a press opens
the page in the navigator around the page, and Ctrl+press opens it in a new tab.
The page follows the entries, so an entry that comes or goes shows or leaves at
once. A section with no entry says so.
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
    root = VerticalLayout(Any[LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          horizontal_align = :left)
    iomap = ChildrenIoMap(p, section, root, Cell(Any[]))
    # The part under the pointer, so a link lights and takes a press.
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(section, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# The card of the entry `k`: its name as a link, and a link for each of its first
# children.
function _make_entry_card(p::ExplorerSectionToWidget, section::ExplorerSection, k::Int, entry)
    place = _make_steps(FieldReferenceStep("entries"), ElementReferenceStep(k))
    title = _make_section_link(section, format_tree_node_label(entry), place)
    lines = Any[_make_section_link(section, format_tree_node_label(child), concat_references(place, reference))
                for (reference, child) in collect_tree_children(entry; limit = p.limit)]
    isempty(lines) && return WidgetCard(; title)
    WidgetCard(; title, content = VerticalLayout(lines; child_width = Fill))
end

# A link to the part at `reference` from `section`: a press opens its page here,
# and Ctrl+press in a new tab.
function _make_section_link(section::ExplorerSection, text::AbstractString, reference::Reference)
    open(place) = (_, _) -> OpenPageOperation(section, reference, place)
    WidgetButton(text; gestures = GestureBinding[
        GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), open(:here);
                       description = "Open as a page", domain = "explorer"),
        GestureBinding(MouseClickPattern(:left; modifiers = [:ctrl]), open(:new_tab);
                       description = "Open in a new tab", domain = "explorer")])
end

# A section draws as its page inside any document that a renderer draws. The cards
# come back through the recursion of the renderer.
make_graphics_projection(::Type{<:ExplorerSection}; measure, appearance) =
    ChainingProjection(
        ExplorerSectionToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        VerticalLayoutToGraphicsCanvas())
