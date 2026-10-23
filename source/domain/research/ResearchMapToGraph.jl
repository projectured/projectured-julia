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
with the words of its links to that item, such as "accepts, rests on".
"""
struct ResearchMapToGraph <: Projection end

"""
    ResearchMapPartToWidget(; styles…)

Draw a part of the map of a study: an item as a small card with its id, its status
and its text, and the label of an edge as a word.
"""
@projection UntrackedCell struct ResearchMapPartToWidget <: Projection
    heading_text::StyleText = get_research_style(nothing, :heading_text)
    muted_text::StyleText = get_research_style(nothing, :muted_text)
    gap::Int = get_research_style(nothing, :gap)
end

@iomap struct ResearchMapToGraphIoMap
    projection::Any
    input::Any
    output::Any
    slots::Any
end

print_document(p::ResearchMapToGraph, recursion, research_map::ResearchMap, ctx) =
    _make_research_map_iomap(p, research_map, () -> _build_research_graph(research_map.study))

function _make_research_map_iomap(p, input, build)
    built = Cell(@computation build())
    ResearchMapToGraphIoMap(p, input, Cell(@computation built[].output), Cell(@computation built[].slots))
end

function _build_research_graph(study)
    study isa ResearchStudy || return (output = GraphGraph(), slots = Any[])
    vertices = Any[]
    vertex_of = IdDict{Any, Any}()
    slots = Any[]
    for kind in RESEARCH_KINDS
        for (index, item) in enumerate(getproperty(study, kind.field))
            vertex = GraphVertex(item)
            push!(vertices, vertex)
            vertex_of[item] = vertex
            push!(slots, OutlineSlot(Any[_make_field_step("study"), _make_field_step(kind.field), _make_element_step(index)],
                                       Any[_make_field_step("vertices"), _make_element_step(length(vertices)),
                                           _make_field_step("content")]))
        end
    end
    edges = Any[]
    for item in collect_study_items(study)
        # Two links to one item are one edge, so their labels do not overlap.
        words = IdDict{Any, Vector{String}}()
        targets = Any[]
        for (name, linked) in collect_research_links(item)
            haskey(vertex_of, linked) || continue
            haskey(words, linked) || (push!(targets, linked); words[linked] = String[])
            word = _get_link_word(item, Val(name))
            word in words[linked] || push!(words[linked], word)
        end
        for linked in targets
            push!(edges, GraphEdge(vertex_of[item], vertex_of[linked]; directed = true,
                                   label = PrimitiveString(join(words[linked], ", "))))
        end
    end
    (output = GraphGraph(vertices = vertices, edges = edges), slots = slots)
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
    _make_research_iomap(p, label, () -> (output = VerticalLayout(Any[WidgetLabel(() -> something(label.value, "");
                                                                                  text_style = p.muted_text)]),
                                          slots = Any[]))

function _build_map_part_view(p::ResearchMapPartToWidget, item::ResearchItem)
    items = Any[WidgetLabel(item.id; text_style = p.heading_text)]
    if has_research_status(item)
        badge = WidgetBadge(() -> string(item.status); variant = :outline)
        set_cell_computation!(getfield(badge, :role), () -> _get_status_badge_role(item.status))
        push!(items, badge)
    end
    push!(items, WidgetLabel(() -> _format_plain_text(get_research_item_text(item))))
    card = WidgetCard(; content = HorizontalLayout(items; gap = p.gap, vertical_align = :center))
    (output = VerticalLayout(Any[card]), slots = Any[])
end

"""
    make_research_map_projection(; measure, theme = nothing, engine = make_deferred_layout_engine())
        -> Projection

The projection that draws a `ResearchMap`: `ResearchMapToGraph`, then the stages
of the Graph domain with the layout `engine`, which draw each vertex and each edge
label through `ResearchMapPartToWidget` with the styles of `theme`. The widgets of a
part draw through the layout and widget projections, so a part needs no other row
of the renderer.
"""
function make_research_map_projection(; measure, theme = nothing, engine = make_deferred_layout_engine())
    get_style(name) = get_research_style(theme, name)
    widgets = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(unwrap_cell(get_style(:font)); measure).dispatch)))
    part = ChainingProjection(ResearchMapPartToWidget(; heading_text = get_style(:heading_text),
                                                       muted_text = get_style(:muted_text),
                                                       gap = get_style(:gap)),
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
