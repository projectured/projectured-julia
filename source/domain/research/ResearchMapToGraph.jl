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
    ResearchMapToGraph(; outline)

Make the `GraphGraph` of the study of a `ResearchMap`: a vertex for each item of the
lists of the study, in the order of `collect_study_items`, and a directed edge from
an item to each item of the study that it links to, labelled with the words of its
links to that item, such as "rests on, supports". The accepts and the rejects of a
decision are edges with no line: the pointer on a decision lights the items it
settled, and they draw no line across the map.

The content of a vertex is the small row of its item, made of the parts of the
outline kit with the values of the `OutlineTheme` in `outline`: the mark of its
kind in the colour of its status, its id, its author, its time and the count of
its elements, then its text at the width of a vertex. It behaves as the row of the
outline does: a press selects the item, the text takes the caret and keys, the
mark, the "⋯" that shows under the pointer, a right click and Shift+F10 open the
menu of the item, Return at the end of the text adds an item of the same kind, and
"Accept…" and "Reject…" open the panel of a decision in the vertex. The item under
the pointer lights its vertex.
"""
@projection UntrackedCell struct ResearchMapToGraph <: Projection
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
    outline = unwrap_cell(p.outline)
    vertices = Any[]
    vertex_of = IdDict{Any, Any}()
    slots = Any[]
    # The study keeps its own paths, as the documents that a row holds do.
    embedded = Base.IdSet{Any}(Any[study])
    for kind in RESEARCH_KINDS
        for (index, item) in enumerate(getproperty(study, kind.field))
            input = Any[_make_field_step("study"), _make_field_step(kind.field), _make_element_step(index)]
            output = Any[_make_field_step("vertices"), _make_element_step(length(vertices) + 1)]
            row = _make_map_row!(slots, embedded, outline, item, study, input,
                                 vcat(output, Any[_make_field_step("content")]))
            vertex = GraphVertex(row)
            push!(vertices, vertex)
            vertex_of[item] = vertex
            # Any other place of the vertex, such as its box, is the item.
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
            # A label in a layout of its own is as wide as its words, so it stands on
            # the middle of its line.
            label = lined[linked] ?
                VerticalLayout(Any[make_outline_label(outline, join(words[linked], ", "), :relation_text)]) : nothing
            push!(edges, GraphEdge(vertex_of[item], vertex_of[linked]; directed = true, visible = lined[linked],
                                   label))
        end
    end
    output = GraphGraph(vertices = vertices, edges = edges)
    # The graph holds the part of the selection and of the part under the pointer
    # of the map that the slots name, so the vertex of the item under the pointer
    # lights and the row of the item with the caret tints.
    # The stages of the graph read typed paths, so the image carries the types of
    # the nodes of the graph that it passes.
    image = path -> begin
        found = map_outline_forward(slots, path)
        found isa ConcreteReference ? annotate_reference_types(output, found) : found
    end
    route_outline_paths!(research_map, output, image; embedded = collect(embedded))
    # The stages of the graph put each vertex in a layout of their own, which hands
    # the vertex no path, so the row of each item takes its part of the paths of the
    # map from the map itself, and gives it on to its parts.
    for (index, vertex) in enumerate(vertices)
        steps = Any[_make_field_step("vertices"), _make_element_step(index), _make_field_step("content")]
        route_outline_paths!(research_map, vertex.content, path -> _find_path_below(image(path), steps);
                             embedded = collect(embedded))
    end
    (; output, slots)
end

# The part of `path` below `steps`, or `nothing` for a path that does not start so.
function _find_path_below(path, steps)
    rest = path
    for step in steps
        (rest isa ConcreteReference && rest.head == step) || return nothing
        rest = rest.tail
    end
    rest
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

# The width of the text of an item on the map, in units of the width of the facts
# of a row of the outline.
const _MAP_TEXT_COLUMNS = 3

# The small row of `item` on the map of `study`, at `place` in the graph, with its
# slots; `prefix` is the path of the item from the map. The first line holds the
# mark, which opens the menu of the item, the id, the author, the time, the count of
# the elements and the "⋯" that shows under the pointer; then come the text, a
# quiet field at the width of a vertex, and the panel of a decision while the study
# decides the item.
function _make_map_row!(slots, embedded, outline, item::ResearchItem, study, prefix, place)
    width = Fixed(_MAP_TEXT_COLUMNS * outline.meta_width)
    content_place = vcat(place, Any[_make_field_step("content")])
    rows = Any[]
    next_row_place() = vcat(content_place, _get_child_steps(length(rows) + 1), Any[_make_field_step("child")])

    compute_menu = () -> _make_research_menu(study, item, false; in_map = true)
    open_menu = () -> make_outline_menu_operation(item.id, compute_menu)
    mark = make_outline_mark(outline, _make_research_icon(item), "The menu of " * item.id, open_menu)
    menu = make_outline_control(outline, :ellipsis, "The menu of " * item.id, open_menu; size = :avatar_size)
    head = Any[mark, make_outline_label(outline, item.id, :id_text), _make_research_when(outline, item)...]
    count = length(item.elements)
    count == 0 ||
        push!(head, make_outline_label(outline, count == 1 ? "1 element" : string(count, " elements"), :relation_text))
    push!(head, menu)
    push!(rows, LayoutConstraint(HorizontalLayout(head; gap = outline.meta_gap, vertical_align = :center)))

    # The text: a field of prose takes the caret; a text of another domain shows as
    # plain text, two lines at most.
    (name_field, placeholder) = _get_name_field(item)
    role = has_research_status(item) && item.status === :rejected ? :quiet_text : :text
    text = if getproperty(item, name_field) isa PrimitiveString
        _make_text_part!(slots, embedded, outline, item, prefix, name_field, next_row_place(); role, placeholder)
    else
        make_outline_label(outline, () -> _format_plain_text(get_research_item_text(item)), role;
                           line = :text_line, max_lines = 2)
    end
    push!(rows, LayoutConstraint(text; width))

    draft = study.deciding
    if draft isa ResearchDecisionDraft && draft.item === item
        panel = _make_decision_panel!(slots, embedded, outline, study, draft, next_row_place();
                                      prefix = Any[_make_field_step("study")])
        push!(rows, LayoutConstraint(panel; width))
    end

    push!(slots, OutlineSlot(prefix, place; whole = true))
    padding = outline.row_padding
    make_outline_card(outline; content = VerticalLayout(rows; gap = outline.meta_gap), revealed = Any[menu],
                      title = item.id, compute_menu, keys = _make_research_row_keys(study, item),
                      width = _MAP_TEXT_COLUMNS * outline.meta_width + padding.left[] + padding.right[])
end

"""
    make_research_map_projection(; measure, theme = nothing, outline_theme = nothing,
                                 engine = make_deferred_layout_engine()) -> Projection

The projection that draws a `ResearchMap`: `ResearchMapToGraph` with the values of
the `OutlineTheme` `outline_theme`, then the stages of the Graph domain with the
layout `engine`, which draw the row of each vertex and the label of each edge
through the layout and widget projections with the font of the `ResearchTheme`
`theme`, so a vertex needs no other row of the renderer. The edges are curves, and
the map is in a scroll pane of its own, which scrolls a map that is larger than
the room that its host gives it.
"""
function make_research_map_projection(; measure, theme = nothing, outline_theme = nothing,
                                      engine = make_deferred_layout_engine())
    get_style(name) = get_research_style(theme, name)
    widgets = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(unwrap_cell(get_style(:font)); measure).dispatch)))
    stages = ChainingProjection(GraphGraphToGraphLayout(engine),
                                GraphLayoutToGraphicsCanvas(edge_shape = :curved))
    ChainingProjection(ResearchMapToGraph(; outline = make_theme_values_field(OutlineTheme, outline_theme)),
                       NestingProjection(make_scrolling_graph_projection(stages; measure);
                                         recursion = widgets))
end
