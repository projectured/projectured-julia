# Fragment of `ResearchModule` — the map of a study: its items as the vertices of a
# graph and its links as the labelled edges, which the stages of the Graph domain
# lay out and draw. It is the map of IBIS and of a discourse graph: a person sees
# at one look which claims have evidence, and of which kind.

"""
A second view of a study: its items as the vertices of a graph, and its links as
the edges, each with the name of the link as its label.

- `study` — the study, which the view reads and does not copy.

Use it to show the structure of the argument of a study at one look.

# Example

    map_1 = ResearchMap(study = study_1)

See also `ResearchStudy`, `collect_research_links`.
"""
@document struct ResearchMap <: ResearchDocument
    study::Any = nothing
end

get_document_title(research_map::ResearchMap) =
    research_map.study === nothing ? "Map" : "Map of " * get_document_title(research_map.study)

"""
    ResearchMapToGraph()

Make the `GraphGraph` of the study of a `ResearchMap`: a vertex whose content is
each item of the lists of the study, in the order of `collect_study_items`, and a
directed edge from an item to each item of the study that it links to, labelled
with the words of its links to that item, such as "rests on, supports". The
accepts and the rejects of a decision are edges with no line: the pointer on a
decision lights the items it settled, and they draw no line across the map.

A vertex is the item as a whole: a press on it selects the item, and the item
under the pointer lights its vertex.
"""
struct ResearchMapToGraph <: Projection end

"""
    ResearchMapPartToWidget(; outline)

Draw a part of the map of a study: an item as a small row, with the mark of its
kind in the colour of its status, its id, its author and its time, its text in two
lines at most and the count of its elements; and the label of an edge as a word.
`outline` holds the values of an `OutlineTheme`.
"""
@projection UntrackedCell struct ResearchMapPartToWidget <: Projection
    outline::NamedTuple = make_theme_values_field(OutlineTheme, nothing)
end

@iomap struct ResearchMapToGraphIoMap
    projection::Any
    input::Any
    output::Any
    slots::Any
end

print_document(p::ResearchMapToGraph, recursion, research_map::ResearchMap, ctx) =
    _make_research_map_iomap(p, research_map, () -> _build_research_graph(p, research_map))

function _make_research_map_iomap(p, input, build)
    built = Cell(@computation build())
    ResearchMapToGraphIoMap(p, input, Cell(@computation built[].output), Cell(@computation built[].slots))
end

# The links of an item that the map draws no line for: what a decision settled.
_is_unlined_link(::Any, ::Val) = false
_is_unlined_link(::ResearchDecision, ::Val{:accepts}) = true
_is_unlined_link(::ResearchDecision, ::Val{:rejects}) = true

function _build_research_graph(p::ResearchMapToGraph, research_map::ResearchMap)
    study = research_map.study
    study isa ResearchStudy || return (output = GraphGraph(), slots = Any[])
    vertices = Any[]
    vertex_of = IdDict{Any, Any}()
    slots = Any[]
    for kind in RESEARCH_KINDS
        for (index, item) in enumerate(getproperty(study, kind.field))
            vertex = GraphVertex(item)
            push!(vertices, vertex)
            vertex_of[item] = vertex
            # A place of the item is the same place in the content of its vertex,
            # and any other place of the vertex, such as its box, is the item.
            input = Any[_make_field_step("study"), _make_field_step(kind.field), _make_element_step(index)]
            output = Any[_make_field_step("vertices"), _make_element_step(length(vertices))]
            push!(slots, OutlineSlot(input, vcat(output, Any[_make_field_step("content")])))
            push!(slots, OutlineSlot(input, output; whole = true))
        end
    end
    edges = Any[]
    for item in collect_study_items(study)
        # Two links to one item are one edge, so their labels do not overlap. An
        # edge that is all links with no line draws none.
        words = IdDict{Any, Vector{String}}()
        lined = IdDict{Any, Bool}()
        targets = Any[]
        for (name, linked) in collect_research_links(item)
            haskey(vertex_of, linked) || continue
            haskey(words, linked) || (push!(targets, linked); words[linked] = String[]; lined[linked] = false)
            _is_unlined_link(item, Val(name)) && continue
            lined[linked] = true
            word = _get_link_word(item, Val(name))
            word in words[linked] || push!(words[linked], word)
        end
        for linked in targets
            push!(edges, GraphEdge(vertex_of[item], vertex_of[linked]; directed = true, visible = lined[linked],
                                   label = lined[linked] ? PrimitiveString(join(words[linked], ", ")) : nothing))
        end
    end
    output = GraphGraph(vertices = vertices, edges = edges)
    # The graph holds the part of the selection and of the part under the pointer
    # of the map that the slots name, so the vertex of the item under the pointer
    # lights. The items keep their own paths.
    # The stages of the graph read typed paths, so the image carries the types of
    # the nodes of the graph that it passes.
    image = path -> begin
        found = map_outline_forward(slots, path)
        found isa ConcreteReference ? annotate_reference_types(output, found) : found
    end
    route_outline_paths!(research_map, output, image;
                         embedded = Any[getfield(vertex, :content)[] for vertex in vertices])
    (; output, slots)
end

map_reference_forward(p::ResearchMapToGraph, iomap::ResearchMapToGraphIoMap, reference) =
    map_outline_forward(iomap.slots, reference)

function map_reference_backward(p::ResearchMapToGraph, iomap::ResearchMapToGraphIoMap, reference)
    reference isa Reference || return nothing
    found = map_outline_backward(iomap.slots, reference)
    found === nothing && return nothing
    try
        annotate_reference_types(iomap.input, found)
    catch
        found
    end
end

print_document(p::ResearchMapPartToWidget, recursion, item::ResearchItem, ctx) =
    _make_research_iomap(p, item, () -> _build_map_part_view(p, item))

print_document(p::ResearchMapPartToWidget, recursion, label::PrimitiveString, ctx) =
    _make_research_iomap(p, label, () -> (output = VerticalLayout(Any[make_outline_label(p.outline,
                                                                                          () -> something(label.value, ""),
                                                                                          :relation_text)]),
                                          slots = Any[]))

# The width of the text of an item on the map, in units of the width of the facts
# of a row of the outline.
const _MAP_TEXT_COLUMNS = 3

function _build_map_part_view(p::ResearchMapPartToWidget, item::ResearchItem)
    outline = p.outline
    icon = _make_research_icon(item)
    mark = WidgetIcon(icon.name; role = icon.role, bottom_right = icon.bottom_right, size = outline.mark_size)
    head = Any[mark, make_outline_label(outline, item.id, :id_text), _make_research_when(outline, item)...]
    count = length(item.elements)
    count == 0 ||
        push!(head, make_outline_label(outline, count == 1 ? "1 element" : string(count, " elements"), :relation_text))
    text = make_outline_label(outline, () -> _format_plain_text(get_research_item_text(item)), :text;
                              line = :text_line, max_lines = 2)
    rows = Any[HorizontalLayout(head; gap = outline.meta_gap, vertical_align = :center),
               LayoutConstraint(text; width = Fixed(_MAP_TEXT_COLUMNS * outline.meta_width))]
    (output = VerticalLayout(rows; gap = outline.meta_gap), slots = Any[])
end

"""
    make_research_map_projection(; measure, theme = nothing, outline_theme = nothing,
                                 engine = make_deferred_layout_engine()) -> Projection

The projection that draws a `ResearchMap`: `ResearchMapToGraph`, then the stages
of the Graph domain with the layout `engine`, which draw each vertex and each edge
label through `ResearchMapPartToWidget` with the values of the `OutlineTheme`
`outline_theme` and the font of the `ResearchTheme` `theme`. The widgets of a part
draw through the layout and widget projections, so a part needs no other row of
the renderer.
"""
function make_research_map_projection(; measure, theme = nothing, outline_theme = nothing,
                                      engine = make_deferred_layout_engine())
    get_style(name) = get_research_style(theme, name)
    widgets = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(unwrap_cell(get_style(:font)); measure).dispatch)))
    part = ChainingProjection(ResearchMapPartToWidget(; outline = make_theme_values_field(OutlineTheme, outline_theme)),
                              widgets)
    ChainingProjection(ResearchMapToGraph(),
                       NestingProjection(ChainingProjection(GraphGraphToGraphLayout(engine),
                                                            GraphLayoutToGraphicsCanvas());
                                         recursion = part))
end

# A part of the map is drawn and not edited: no place of it maps to its input, so
# a press on a vertex selects the vertex.
map_reference_forward(::ResearchMapPartToWidget, ::ResearchToWidgetIoMap, reference) = nothing
map_reference_backward(::ResearchMapPartToWidget, ::ResearchToWidgetIoMap, reference) = nothing
