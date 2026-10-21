# A graph says what the pointer is on: for a vertex, how many edges leave it and
# arrive at it, and its label. The part under the pointer is the end of the mouse
# target of the graph; with no pointer, the end of its selection.

# The note that the graph answers to a dwell, or `nothing`.
function _gn_read_note(graph)
    operation = read_gesture(graph, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

# The path from `graph` to the vertex that `found` names, as the graph holds it among its
# vertices: an edge holds the same vertex as an end.
_gn_path(graph, found) = first(path for path in search_references(graph, node -> found(node))
                               if get_reference_steps(path)[1] == FieldReferenceStep("vertices"))

function test_graph_note()
@testset "a graph says the edges of the vertex under the pointer" begin
    paris = GraphVertex(PrimitiveString("Paris"))
    lyon = GraphVertex(PrimitiveString("Lyon"))
    nice = GraphVertex(PrimitiveString("Nice"))
    graph = GraphGraph([paris, lyon, nice], [GraphEdge(paris, lyon), GraphEdge(paris, nice), GraphEdge(lyon, nice)])
    @test _gn_read_note(graph) === nothing
    vertex_path = _gn_path(graph, node -> node === paris)
    replace_mouse_target!(graph, vertex_path)
    note = _gn_read_note(graph)
    @test note.facts == ["Edges out" => "2", "Edges in" => "0", "Label" => "Paris"]
    # The pointer rests in the text of the label: the note is about the vertex that holds it.
    replace_mouse_target!(graph, extend_reference(_gn_path(graph, node -> node === nice), FieldReferenceStep("content")))
    @test _gn_read_note(graph).facts == ["Edges out" => "0", "Edges in" => "2", "Label" => "Nice"]
    # With no pointer on the graph, the note is about the selected vertex.
    selected = GraphGraph([paris, lyon], [GraphEdge(paris, lyon)])
    replace_selection!(selected, _gn_path(selected, node -> node === lyon))
    @test _gn_read_note(selected).facts == ["Edges out" => "0", "Edges in" => "1", "Label" => "Lyon"]
end
end
