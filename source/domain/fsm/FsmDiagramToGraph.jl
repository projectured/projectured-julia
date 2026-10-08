# Fragment of `FsmModule`.
#
# FsmDiagram → GraphGraph: the state diagram. One vertex per state, one directed
# edge per transition that has a target, and the two graph highlights derived from
# the diagram's live fields — so the stock `GraphToGraphLayout →
# GraphLayoutToGraphicsCanvas` stages draw the whole picture, including the current-state
# ring and the last-transition re-stroke, with no fsm-specific rendering code.
#
# A vertex's content is the `FsmState` **itself**, held by identity, so clicking a
# node selects the real state through the graph pipeline's existing
# `vertex_layouts[i].vertex.content.…` routing. The diagram renders it through
# `FsmStateToSyntaxLabel` — the state's name alone. Projecting a state through the
# full notation would inline its whole transition list into the node box, and for
# a self-loop would not terminate.
#
# The highlights are computed cells over `diagram.live_state` /
# `diagram.live_transition`, resolved to the `GraphVertex` / `GraphEdge` by
# identity. A live driver writing those two integers repaints the overlay without
# touching any vertex content, so the layout engine is never re-run mid-run.
#
# Known v1 limits, both inherited from the graph slice and recorded in the plan: a
# self-loop transition (`target === its own state`) routes to a zero-length line
# and so does not render, and edges are not clickable — a stay has no edge at all,
# and both are edited in the notation.
# ── Node and edge content projections ────────────────────────────────────────
#
# Compact forms used only inside the diagram: a state renders as its name, a
# transition as its trigger/guard/action — the target is the edge itself, so
# repeating it on the label would be noise.

@projection UntrackedCell struct FsmStateToSyntaxLabel
    name::StyleText = get_fsm_style(nothing, :state_label_text)
end

@projection_template FsmStateToSyntaxLabel FsmState (p, doc) ->
    SyntaxLeaf(bound(:name, String,
                     make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                      placeholder = "state",
                                      style = p.name)))

@projection UntrackedCell struct FsmTransitionToSyntaxLabel
    keyword::StyleText = get_fsm_style(nothing, :trigger_text)
    ref::StyleText     = get_fsm_style(nothing, :event_reference_text)
    chrome::StyleText  = get_fsm_style(nothing, :chrome_text)
end

_trigger_label(doc) = begin
    trigger = doc.trigger
    trigger === nothing ? "" :
        trigger isa FsmTimer ? "timeout($(trigger.name))" : trigger.name
end

@projection_template FsmTransitionToSyntaxLabel FsmTransition (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        doc.trigger === nothing ||
            push!(children, SyntaxLeaf(TextString(() -> _trigger_label(doc), p.ref)))
        if doc.guard !== nothing
            push!(children, SyntaxLeaf(TextString(isempty(children) ? "when " : " when ", p.keyword)))
            push!(children, project(:guard))
        end
        if doc.action !== nothing
            push!(children, SyntaxLeaf(TextString(isempty(children) ? "/ " : " / ", p.chrome)))
            push!(children, project(:action))
        end
        # A transition with nothing to say still needs a child: an empty
        # concatenation has no text and would leave the edge unlabeled with no
        # hint that anything is there.
        isempty(children) && push!(children, SyntaxLeaf(TextString("always", p.chrome)))
        children
    end)

"""
    FsmToSyntaxLabel(; theme = nothing, julia_theme = nothing, syntax_theme = nothing)

The diagram's label table: the two compact forms above, with the full notation
as the fallback so a box holding a foreign content type still renders. The
builder gives each projection the style of its role with `get_fsm_style`, from
`theme`, a `FsmTheme` scaled or not, or the default styles for `nothing`;
`julia_theme` and `syntax_theme` reach the fallback's embedded Julia nodes.
"""
function FsmToSyntaxLabel(; theme = nothing, julia_theme = nothing, syntax_theme = nothing)
    get_style(name) = get_fsm_style(theme, name)
    TypeDispatchingProjection(
        FsmState      => FsmStateToSyntaxLabel(; name = get_style(:state_label_text)),
        FsmTransition => FsmTransitionToSyntaxLabel(; keyword = get_style(:trigger_text),
                                                      ref = get_style(:event_reference_text),
                                                      chrome = get_style(:chrome_text)),
        Any           => FsmToSyntax(; theme, julia_theme, syntax_theme),
    )
end

# ── The diagram stage ────────────────────────────────────────────────────────

struct FsmDiagramToGraph <: Projection end

@iomap struct FsmDiagramToGraphIoMap
    projection::Any
    input::Any
    output::Any
end

function print_document(p::FsmDiagramToGraph, recursion,
                        diagram::Union{FsmDiagram, FsmNothing, FsmInsertion}, ctx)
    iomap_cell = Cell(nothing)
    machine = diagram isa FsmDiagram ? diagram.machine : nothing

    _states() = machine isa FsmMachine ? [s for s in machine.states if s isa FsmState] : FsmState[]

    # One vertex per state, rebuilt when the state list changes. The vertex
    # objects are what the highlight and the edges point at, so both read this
    # same cell rather than rebuilding their own.
    vertex_cells = Cell(@computation begin
        pairs = Pair{FsmState,Any}[]
        for s in _states()
            push!(pairs, s => GraphVertex(Cell(s), Cell(nothing)))
        end
        pairs
    end)

    _vertex_for(state) = begin
        for (s, v) in vertex_cells[]
            s === state && return v
        end
        nothing
    end

    vertices = CellVector(@computation Any[v for (_, v) in vertex_cells[]])

    # One edge per transition that goes somewhere. A stay has no target, so it
    # has no edge; the label is the transition itself, held by identity.
    edge_cells = Cell(@computation begin
        result = Any[]
        machine isa FsmMachine || return result
        for s in _states()
            source = _vertex_for(s)
            source === nothing && continue
            for t in s.transitions
                t isa FsmTransition || continue
                target_state = t.target
                target_state === nothing && continue
                target = _vertex_for(target_state)
                target === nothing && continue
                push!(result, (t, GraphEdge(source, target; directed=true, label=t)))
            end
        end
        result
    end)

    edges = CellVector(@computation Any[e for (_, e) in edge_cells[]])

    # The live overlay: two integers resolved to objects by identity. Reading
    # only these cells is what keeps a transition arriving mid-run from
    # invalidating anything the layout engine depends on.
    highlight_vertex = Cell(@computation begin
        diagram isa FsmDiagram || return nothing
        index = diagram.live_state
        states = _states()
        (index < 1 || index > length(states)) && return nothing
        _vertex_for(states[index])
    end)

    highlight_edge = Cell(@computation begin
        diagram isa FsmDiagram || return nothing
        index = diagram.live_transition
        machine isa FsmMachine || return nothing
        flat = get_fsm_transitions(machine)
        (index < 1 || index > length(flat)) && return nothing
        transition = flat[index]
        for (t, e) in edge_cells[]
            t === transition && return e
        end
        nothing
    end)

    graph = GraphGraph(vertices, edges, highlight_vertex, highlight_edge,
        Cell(@computation let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, diagram.selection)
        end),
        Cell(@computation map_mouse_target_forward(diagram, path -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, path)
        end)))

    iomap = FsmDiagramToGraphIoMap(p, diagram, graph)
    iomap_cell[] = iomap
    iomap
end

# machine.states[i].rest... ↔ vertices[i].content.rest...
# The state rides unchanged under `.content`, so the label projection's own
# iomap (held by the graph stages downstream) handles the tail.
function map_reference_forward(::FsmDiagramToGraph, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference ::GraphGraph
        ::FsmDiagram.machine.states[i].rest... =>
            (@reference ::GraphGraph.vertices::CellVector[i]::GraphVertex.content.^(rest))
        __ => nothing
    end
end

function map_reference_backward(::FsmDiagramToGraph, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference ::FsmDiagram
        ::GraphGraph.vertices[i].content.rest... =>
            (@reference ::FsmDiagram.machine::FsmMachine.states::CellVector[i].^(rest))
        __ => nothing
    end
end
