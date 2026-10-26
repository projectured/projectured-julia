# A small graph whose vertices are *different domains* — a Table, a Json object,
# and an Xml element — connected by directed edges, to demonstrate "a vertex can
# be anything." The vertices are held in the GraphGraph and referenced by the
# edges by identity.

function make_graph_document_example()
    # Vertex 1: a tiny table (2 columns: Name / Role).
    table = WidgetTable(;
        column_headers = Any[JsonString("Name"), JsonString("Role")],
        row_headers = Any[],
        cells = Any[
            Any[JsonString("Ada"), JsonString("Lead")],
        ])

    # Vertex 2: a small JSON object.
    json = JsonObject("id" => JsonNumber(42), "active" => JsonBool(true))

    # Vertex 3: a small XML element.
    xml = XmlElement("node",
        [XmlAttribute("kind", "service")],
        [XmlElement("name", [XmlText("auth")])])

    v_table = GraphVertex(table)
    v_json  = GraphVertex(json)
    v_xml   = GraphVertex(xml)

    graph = GraphGraph(
        [v_table, v_json, v_xml],
        [
            GraphEdge(v_table, v_json;  directed=true, label=JsonString("uses")),
            GraphEdge(v_json,  v_xml;   directed=true),
            GraphEdge(v_table, v_xml;   directed=false),
        ],
    )

    graph
end

"Atomic document for the catalog: the same three-vertex, cross-domain graph as `graph_example`."
make_graph_graph_document_example() = make_graph_document_example()

"Atomic document for the catalog: the placed layout of the three-vertex graph."
function make_graph_layout_document_example()
    graph = make_graph_document_example()
    v, e = graph.vertices[1], graph.edges[1]
    GraphLayout(; vertex_layouts = CellVector([VertexLayout(v, 0, 0, 120, 60)]),
                  edge_layouts   = CellVector([EdgeLayout(e)]))
end

# A line of text in the font of the widgets, which a person can edit.
_make_graph_text(text) = TextBlock(TextLine(TextString(text, StyleFont("Ubuntu", 13), color_default)))

# The services of a small shop and how they call each other: fifteen vertices, each
# the name of a service as a line of text, and directed edges, each with a label
# that says what the call does. It is large enough to show the zoom and the scroll
# of a graph view.
function make_graph_services_document_example()
    names = ["browser", "web", "api", "auth", "orders", "search", "payments", "inventory",
             "queue", "email", "analytics", "database", "index", "cache", "bank"]
    vertices = Dict(name => GraphVertex(_make_graph_text(name)) for name in names)
    calls = [("browser", "web", "loads"), ("web", "api", "calls"), ("api", "auth", "checks"),
             ("api", "orders", "calls"), ("api", "search", "queries"), ("api", "cache", "reads"),
             ("orders", "payments", "charges"), ("orders", "inventory", "reserves"),
             ("orders", "queue", "publishes"), ("orders", "database", "writes"),
             ("inventory", "database", "reads"), ("search", "index", "reads"),
             ("queue", "email", "delivers"), ("queue", "analytics", "delivers"),
             ("analytics", "database", "reads"), ("payments", "bank", "calls")]
    GraphGraph([vertices[name] for name in names],
               [GraphEdge(vertices[source], vertices[target]; directed = true, label = _make_graph_text(verb))
                for (source, target, verb) in calls])
end
