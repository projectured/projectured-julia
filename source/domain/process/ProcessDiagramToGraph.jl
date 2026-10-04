# Fragment of `ProcessModule`.
#
# ProcessDiagram → GraphGraph: the flowchart. The structured tree is walked once
# into vertices and edges, so the stock `GraphToGraphLayout →
# GraphLayoutToGraphicsCanvas` stages draw the whole picture — boxes, arrows, the
# current-node ring and the last-arrow re-stroke — with no process-specific
# rendering code.
#
# ## What becomes a vertex
#
# Every step, decision, loop header and jump gets one vertex whose content is the
# document node **itself**, held by identity, so clicking a box selects the real
# node through the graph pipeline's existing `vertex_layouts[i].vertex.content.…`
# routing. Sequences do not: they are the tree's structure, and the picture shows
# structure as edges. The start and stop ovals are `ProcessTerminal`s the stage
# synthesizes — picture, not semantics, with no node behind them.
#
# ## What becomes an edge
#
# The walk is the standard structured-control-flow construction: `emit(node,
# next)` draws `node` and points it at the vertex control reaches afterwards.
#
# - a sequence chains: each node's `next` is the following node's entry, and the
#   last one's is the sequence's own `next`;
# - a decision points `yes` at its then-branch entry and `no` at its else-branch
#   entry — or straight at `next` when that branch is empty or absent. **There is
#   no merge vertex**: both tails already point at the successor, which is what
#   the recursion hands them;
# - a `while` points `yes` at its body entry and `no` at `next`, and its body's
#   `next` is the loop header itself — that back-edge is the loop;
# - a `foreach` has the same two exits, labelled `next`/`done`;
# - `break` points at the enclosing loop's exit, `continue` at its header,
#   `return` at the stop terminal.
#
# Vertices are created in document order in a first pass and wired in a second,
# so the vector order the layout engine sees matches the notation's reading
# order.
#
# ## The live overlay
#
# `highlight_vertex` and `highlight_edge` are computed cells over the diagram's
# debug session: the node it names resolves to a vertex by identity, and the
# `(previous, current)` pair resolves to the edge between them. Deriving the stroked arrow from the
# node *pair* is what keeps edges picture-only — the document has no edge to
# index and the runtime never learns a picture vocabulary. Both cells read
# nothing else, so a step arriving mid-run repaints the overlay without
# invalidating anything the layout engine depends on.
#
# Known v1 limits: a selection is mapped only when it names a node exactly (a
# caret *inside* a step's action does not light up its box), and edges are not
# clickable.
# ── Node and edge content projections ────────────────────────────────────────
#
# Compact forms used only inside the diagram. A box shows what the node *is*,
# never its children — projecting a decision through the full notation would
# inline both its branches into the box the branches hang off.

@projection UntrackedCell struct ProcessStepToSyntaxLabel
    text::StyleText = get_process_style(nothing, :action_text)
end

# A described step shows its prose; a code-only step shows its code, which is
# the only thing it has to say.
@projection_template ProcessStepToSyntaxLabel ProcessStep (p, doc) ->
    SyntaxConcatenation(() -> begin
        if !isempty(doc.description)
            Any[ SyntaxLeaf(bound(:description, String,
                                  make_hinted_text(() -> doc.description;
                                                   empty_thunk = () -> isempty(doc.description),
                                                   placeholder = "step",
                                                   style = p.text))) ]
        elseif doc.action !== nothing
            Any[ project(:action) ]
        else
            Any[ SyntaxLeaf(TextString("step", p.text)) ]
        end
    end)

@projection UntrackedCell struct ProcessDecisionToSyntaxLabel
    chrome::StyleText = get_process_style(nothing, :chrome_text)
end

@projection_template ProcessDecisionToSyntaxLabel ProcessDecision (p, doc) ->
    SyntaxConcatenation(() -> Any[ doc.condition === nothing ?
                                   SyntaxLeaf(TextString("<condition>", p.chrome)) :
                                   project(:condition) ])

@projection UntrackedCell struct ProcessWhileToSyntaxLabel
    keyword::StyleText = get_process_style(nothing, :keyword_text)
    chrome::StyleText  = get_process_style(nothing, :chrome_text)
end

@projection_template ProcessWhileToSyntaxLabel ProcessWhile (p, doc) ->
    SyntaxConcatenation(() -> Any[ SyntaxLeaf(TextString("while ", p.keyword)),
                                   doc.condition === nothing ?
                                   SyntaxLeaf(TextString("<condition>", p.chrome)) :
                                   project(:condition) ])

@projection UntrackedCell struct ProcessForeachToSyntaxLabel
    keyword::StyleText = get_process_style(nothing, :keyword_text)
    chrome::StyleText  = get_process_style(nothing, :chrome_text)
end

@projection_template ProcessForeachToSyntaxLabel ProcessForeach (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("for ", p.keyword)) ]
        push!(children, doc.variable === nothing ?
                        SyntaxLeaf(TextString("<variable>", p.chrome)) : project(:variable))
        push!(children, SyntaxLeaf(TextString(" in ", p.keyword)))
        push!(children, doc.iterable === nothing ?
                        SyntaxLeaf(TextString("<iterable>", p.chrome)) : project(:iterable))
        children
    end)

@projection UntrackedCell struct ProcessTerminalToSyntaxLabel
    style::StyleText = get_process_style(nothing, :terminal_text)
end

@projection_template ProcessTerminalToSyntaxLabel ProcessTerminal (p, doc) ->
    SyntaxLeaf(TextString(() -> String(doc.kind), p.style))

@projection UntrackedCell struct ProcessEdgeLabelToSyntaxLeaf
    style::StyleText = get_process_style(nothing, :chrome_text)
end

@projection_template ProcessEdgeLabelToSyntaxLeaf ProcessEdgeLabel (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.text, p.style))

"""
    ProcessToSyntaxLabel(; theme = nothing, julia_theme = nothing, syntax_theme = nothing)

The diagram's label table: the compact per-node forms above, with the full
notation as the fallback so a box holding a foreign content type still renders.
The builder gives each projection the style of its role with
`get_process_style`, from `theme`, a `ProcessTheme` scaled or not, or the
default styles for `nothing`; `julia_theme` and `syntax_theme` reach the
fallback's embedded Julia nodes.
"""
function ProcessToSyntaxLabel(; theme = nothing, julia_theme = nothing, syntax_theme = nothing)
    get_style(name) = get_process_style(theme, name)
    live_styles = (current = get_style(:current_text), breakpoint = get_style(:breakpoint_text))
    keyword_chrome_styles = (keyword = get_style(:keyword_text), chrome = get_style(:chrome_text))
    TypeDispatchingProjection(
        ProcessStep     => ProcessStepToSyntaxLabel(; text = get_style(:action_text)),
        ProcessDecision => ProcessDecisionToSyntaxLabel(; chrome = get_style(:chrome_text)),
        ProcessWhile    => ProcessWhileToSyntaxLabel(; keyword_chrome_styles...),
        ProcessForeach  => ProcessForeachToSyntaxLabel(; keyword_chrome_styles...),
        ProcessBreak    => ProcessBreakToSyntaxLeaf(; keyword = get_style(:keyword_text), live_styles...),
        ProcessContinue => ProcessContinueToSyntaxLeaf(; keyword = get_style(:keyword_text), live_styles...),
        ProcessReturn   => ProcessReturnToSyntaxNode(; keyword = get_style(:keyword_text),
                                                        chrome = get_style(:chrome_text), live_styles...),
        ProcessTerminal => ProcessTerminalToSyntaxLabel(; style = get_style(:terminal_text)),
        ProcessEdgeLabel => ProcessEdgeLabelToSyntaxLeaf(; style = get_style(:chrome_text)),
        Any             => ProcessToSyntax(; theme, julia_theme, syntax_theme),
    )
end

# ── The flowchart walk ───────────────────────────────────────────────────────

# Which node types get a box. A sequence is structure (drawn as edges) and the
# model is the whole picture, so neither does.
_has_vertex(node) = node isa ProcessDocument &&
                    !(node isa ProcessSequence) && !(node isa ProcessModel)

# One pass over the tree, returning the vertices in document order, the edges,
# and the node → vertex pairs the highlight and the reference mapping resolve
# through.
function _build_flowchart(model)
    nodes = model === nothing ? Any[] : process_nodes(model)
    pairs = Pair{Any,Any}[]
    middle = Any[]
    for node in nodes
        _has_vertex(node) || continue
        vertex = GraphVertex(Cell(node), Cell(nothing))
        push!(middle, vertex)
        push!(pairs, node => vertex)
    end

    start = GraphVertex(Cell(ProcessTerminal(:start)), Cell(nothing))
    stop = GraphVertex(Cell(ProcessTerminal(:stop)), Cell(nothing))
    edges = Any[]

    vertex_for(node) = begin
        for (n, v) in pairs
            n === node && return v
        end
        nothing
    end

    edge!(from, to, text = nothing) = begin
        (from === nothing || to === nothing) && return nothing
        push!(edges, GraphEdge(from, to; directed = true,
                               label = text === nothing ? nothing : ProcessEdgeLabel(text)))
    end

    # `loop` is (header, exit) of the innermost enclosing loop, or nothing.
    emit_sequence(steps, next, loop) = begin
        cursor = next
        for node in Iterators.reverse(steps)
            cursor = emit(node, cursor, loop)
        end
        cursor
    end

    emit(node, next, loop) = begin
        vertex = vertex_for(node)
        vertex === nothing && return next
        if node isa ProcessDecision
            then_entry = emit_sequence(get_body_steps(node.then_branch), next, loop)
            else_entry = node.else_branch === nothing ? next :
                         emit_sequence(get_body_steps(node.else_branch), next, loop)
            edge!(vertex, then_entry, "yes")
            edge!(vertex, else_entry, "no")
        elseif node isa ProcessWhile
            edge!(vertex, emit_sequence(get_body_steps(node.body), vertex, (vertex, next)), "yes")
            edge!(vertex, next, "no")
        elseif node isa ProcessForeach
            edge!(vertex, emit_sequence(get_body_steps(node.body), vertex, (vertex, next)), "next")
            edge!(vertex, next, "done")
        elseif node isa ProcessBreak
            loop === nothing || edge!(vertex, loop[2])
        elseif node isa ProcessContinue
            loop === nothing || edge!(vertex, loop[1])
        elseif node isa ProcessReturn
            edge!(vertex, stop)
        else
            edge!(vertex, next)
        end
        vertex
    end

    body = model isa ProcessModel ? get_body_steps(model.body) : Any[]
    edge!(start, emit_sequence(body, stop, nothing))

    (vertices = Any[start; middle; stop], edges = edges, pairs = pairs)
end

# ── The diagram stage ────────────────────────────────────────────────────────

struct ProcessDiagramToGraph <: Projection end

@iomap struct ProcessDiagramToGraphIoMap
    projection::Any
    input::Any
    output::Any
end

function print_document(p::ProcessDiagramToGraph, recursion,
                        diagram::Union{ProcessDiagram, ProcessNothing, ProcessInsertion}, ctx)
    iomap_cell = Cell(nothing)
    model = diagram isa ProcessDiagram ? diagram.model : nothing

    # One cell holds the whole walk: vertices, edges and the node → vertex map
    # are one construction and must never disagree about identity.
    flowchart = Cell(@computation _build_flowchart(model isa ProcessModel ? model : nothing))

    vertices = CellVector(@computation Any[v for v in flowchart[].vertices])
    edges = CellVector(@computation Any[e for e in flowchart[].edges])

    # The live overlay. `session` is duck-typed on purpose: the diagram is
    # drawable with nothing attached, and the debug slice is what fills it in.
    highlight_vertex = Cell(@computation begin
        diagram isa ProcessDiagram || return nothing
        session = diagram.session
        session === nothing && return nothing
        _vertex_of(flowchart[], session.current)
    end)

    highlight_edge = Cell(@computation begin
        diagram isa ProcessDiagram || return nothing
        session = diagram.session
        session === nothing && return nothing
        from = _vertex_of(flowchart[], session.previous_document)
        to = _vertex_of(flowchart[], session.current)
        (from === nothing || to === nothing) && return nothing
        for e in flowchart[].edges
            e.source === from && e.target === to && return e
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

    iomap = ProcessDiagramToGraphIoMap(p, diagram, graph)
    iomap_cell[] = iomap
    iomap
end

# The box drawing `node`, or `nothing` when there is none — which is what a
# node with no box (a sequence), a position of nowhere, and a stale position
# all look like. Every one of them means *no highlight*, never a wrong one.
function _vertex_of(flowchart, node)
    node === nothing && return nothing
    for (n, v) in flowchart.pairs
        n === node && return v
    end
    nothing
end

# ── Reference mapping ────────────────────────────────────────────────────────
#
# The tree's shape is not the picture's shape — a box's node lives at an
# arbitrary path, not at `states[i]` — so neither direction can be written as a
# path pattern the way `FsmDiagramToGraph` writes it. Forward evaluates the
# reference and asks which box the value has; backward asks the tree where the
# box's node lives. Both are whole-node only in v1.

function map_reference_forward(p::ProcessDiagramToGraph, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return @reference ::GraphGraph
    diagram = iomap.input
    diagram isa ProcessDiagram || return nothing
    node = try_evaluate_reference(diagram, reference)
    node === nothing && return nothing
    graph = iomap.output
    # The node type of the content the path lands on: every node of a built
    # path carries one, and the last is no exception. It is the *content's*
    # reference node type, not its concrete Julia type (`@document` makes an
    # R-prefixed reactive struct per document type).
    nt = get_reference_node_type(node)
    for (index, vertex) in enumerate(graph.vertices)
        vertex.content === node &&
            return @reference ::GraphGraph.vertices::CellVector[index]::GraphVertex.content::nt
    end
    nothing
end

function map_reference_backward(p::ProcessDiagramToGraph, iomap, reference)
    reference === nothing && return nothing
    diagram = iomap.input
    @reference_case reference begin
        ∅ => @reference ::ProcessDiagram
        ::GraphGraph.vertices[index].content => _node_reference(diagram, index)
        __ => nothing
    end
end

# The reference naming the node drawn in box `index`, rooted at the diagram.
# `search_references` is what finds where a node sits in the tree — the walk is
# the same one `process_nodes` does, and asking for it here keeps this stage
# from maintaining a second path vocabulary.
function _node_reference(diagram, index)
    diagram isa ProcessDiagram || return nothing
    model = diagram.model
    model isa ProcessModel || return nothing
    flowchart = _build_flowchart(model)
    (index < 1 || index > length(flowchart.vertices)) && return nothing
    node = flowchart.vertices[index].content
    # A terminal is picture-only: there is no document node to select.
    node isa ProcessTerminal && return nothing
    found = search_references(model, x -> x === node)
    isempty(found) && return nothing
    @reference ::ProcessDiagram.model::ProcessModel.^(found[1])
end
