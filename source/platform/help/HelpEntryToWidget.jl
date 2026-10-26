# Fragment of `HelpModule` — the page of one type in a tree of the help: its name,
# where it is defined, its supertypes, the names that make it, its whole
# docstring and the table of its fields, in a scroll pane of its own, because a
# navigator puts none around a page.

"""
    HelpEntryToWidget(; gap, name, detail, description, muted)

Draw a [`HelpEntry`](@ref) as its page, in a scroll pane: the name of the type,
the module that defines it, the type with its supertypes, such as
`AboutPage <: Document`, for a document type the names that a person types into
an empty tab to make one, the whole docstring, one line of the page for each
line of the text, or "No description." for a type with none, and a table of the
fields that a person can set: the field and its type, each as wide as its widest
cell, and the docstring of the field in the rest of the width. A type with no
such field says "No fields.". The page is read only.

The projection holds its styles and no theme; `make_help_entry_projection` fills
them from a theme.
"""
@projection UntrackedCell struct HelpEntryToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
    name::StyleText = get_help_style(nothing, :name_text)
    detail::StyleText = get_help_style(nothing, :detail_text)
    description::StyleText = get_help_style(nothing, :description_text)
    muted::StyleText = get_help_style(nothing, :muted_text)
end

"""
    make_help_entry_projection(; theme = nothing, gap) -> HelpEntryToWidget

The projection of the page of a type in a tree of the help, with the styles of
`theme`: a `HelpTheme`, scaled or not, or the default styles for `nothing`.
`gap` is the space between the parts of the page.
"""
function make_help_entry_projection(; theme = nothing, gap = get_widget_style(nothing, :section_gap))
    get_style(name) = get_help_style(theme, name)
    HelpEntryToWidget(; gap, name = get_style(:name_text), detail = get_style(:detail_text),
                      description = get_style(:description_text), muted = get_style(:muted_text))
end

function print_document(p::HelpEntryToWidget, recursion, entry::HelpEntry, context)
    body = VerticalLayout(Any[]; gap = p.gap, child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements),
                          () -> Cell[Cell(part) for part in _make_help_entry_parts(p, entry)])
    root = VerticalLayout(Any[LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          child_width = Fill)
    iomap = ChildrenIoMap(p, entry, root, Cell(Any[]))
    set_output_path_computations!(root, entry, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The parts of the page, from the top: the name, the module, the names to type,
# and the text, whose lines stand with no gap between them.
function _make_help_entry_parts(p::HelpEntryToWidget, entry::HelpEntry)
    parts = Any[WidgetLabel(entry.name; text_style = p.name)]
    T = entry.type
    T isa Type && push!(parts, WidgetLabel(join(String.(fullname(parentmodule(T))), "."); text_style = p.detail))
    isempty(entry.supertypes) ||
        push!(parts, WidgetLabel(entry.name * " <: " * entry.supertypes; text_style = p.detail))
    isempty(entry.typed) ||
        push!(parts, WidgetLabel("Names to type in an empty tab: " * entry.typed; text_style = p.detail))
    if isempty(entry.text)
        push!(parts, WidgetLabel("No description."; text_style = p.muted))
    else
        lines = Any[WidgetLabel(String(line); text_style = p.description) for line in split(entry.text, '\n')]
        push!(parts, VerticalLayout(lines; child_width = Fill))
    end
    push!(parts, isempty(entry.fields) ? WidgetLabel("No fields."; text_style = p.muted) :
                     _make_help_widget_table(_HELP_FIELD_COLUMNS,
                                             [[field.name, field.type, field.description] for field in entry.fields]))
    parts
end

# The field and its type are as wide as their widest cell, and the docstring of
# the field takes the rest of the width.
const _HELP_FIELD_COLUMNS = ["field" => Content, "type" => Content, "description" => Fill]

# A type draws as its page inside any document that a renderer draws.
make_graphics_projection(::Type{<:HelpEntry}; measure, appearance) =
    ChainingProjection(
        make_help_entry_projection(; theme = get_scaled_theme!(appearance, HelpTheme),
                                   gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        VerticalLayoutToGraphicsCanvas())
