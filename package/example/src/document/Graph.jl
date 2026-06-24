# A small graph whose vertices are *different domains* — a Table, a Json object,
# and an Xml element — connected by directed edges, to demonstrate "a vertex can
# be anything." The vertices are held in the GraphGraph and referenced by the
# edges by identity.

function make_graph_document_example()
    # Vertex 1: a tiny table (2 columns: Name / Role).
    table = WidgetTable(Point2D(0, 0),
        Any[JsonString("Name"), JsonString("Role")],
        Any[],
        Any[
            Any[JsonString("Ada"), JsonString("Lead")],
        ],
        2;
        padding=8,
    )

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
