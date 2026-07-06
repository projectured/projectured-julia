# ═══════════════════════════════════════════════════════════════════════════
# domain-test/src/Fixtures.jl
#
# Local domain fixtures, mirrored from `ProjecturedExample` (which this
# package must not depend on — the example package sits above the whole
# runtime stack). Per plan/pending/test-package-split.md, low test packages
# build small local fixture documents/projections inline until the examples
# themselves are split per package; these copies are byte-for-byte the example
# factories, so the split becomes a no-op swap later.
# ═══════════════════════════════════════════════════════════════════════════

function make_json_document_example()
    JsonObject(
        "name"    => JsonString("Alice"),
        "age"     => JsonNumber(30),
        "active"  => JsonBool(true),
        "address" => JsonObject(
            "street" => JsonString("123 Main St"),
            "city"   => JsonString("Wonderland"),
            "zip"    => JsonString("12345"),
        ),
        "scores"  => JsonArray(
            JsonNumber(95),
            JsonNumber(87),
            JsonNumber(100),
        ),
        "tags"    => JsonArray(
            JsonString("admin"),
            JsonString("editor"),
            JsonString("reviewer"),
        ),
        "meta"    => JsonObject(
            "created" => JsonString("2025-01-15"),
            "version" => JsonNumber(2),
            "draft"   => JsonBool(false),
        ),
        "placeholder" => JsonInsertion(),
    )
end

# The full JSON → Syntax → Text → Graphics pipeline.
function make_graphics_image_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# Console variant: the same pipeline but **without** the trailing
# `TextToGraphics` step. It stops at the Text domain (`SyntaxToText` output, a
# `TextText`), which the `ConsoleBackend` renders to the terminal directly —
# colors and all. No `measure` is needed because no graphics layout happens.
#
# `EnvelopeUnwrappingProjection` wraps the chain so the editor's `EventEnvelope`
# gesture is stripped to its inner event before the readers see it; this
# pipeline has no screen/window layer to supply that seam.
function make_json_console_projection_example()
    EnvelopeUnwrappingProjection(
        ChainingProjection(
            RecursiveProjection(JsonToSyntax()),
            RecursiveProjection(SyntaxToText()),
            # Bake the selection into the spans as inverse video so the dumb
            # console renderer shows it (no separate cursor/highlight layer).
            SelectionInverting(),
        )
    )
end

# Table fixtures build a `WidgetTable` (the single table abstraction) whose
# cells are domain documents recursed by the projection. The first variant
# uses JSON cells; the second uses Primitive / Math cells.

function make_table_document_example()
    WidgetTable(Point2D(40, 40),
        # column headers
        Any[JsonString("Name"), JsonString("Age"), JsonString("City")],
        # row headers (none)
        Any[],
        # body rows (each a vector of document cells)
        Any[
            Any[JsonString("Jennifer"), JsonNumber(30), JsonString("New York")],
            Any[JsonString("Bob"),      JsonNumber(25), JsonString("Springfield")],
            Any[JsonString("Carol"),    JsonNumber(42), JsonString("Metropolis")],
        ],
        3;                       # column_count
        padding=16)
end

function make_math_table_document_example()
    WidgetTable(Point2D(40, 40),
        # column headers
        Any[PrimitiveString("A"), PrimitiveString("B"), PrimitiveString("C")],
        # row headers
        Any[PrimitiveString("1"), PrimitiveString("2"), PrimitiveString("3")],
        # body rows
        Any[
            # row 1: plain numbers
            Any[PrimitiveNumber(10), PrimitiveNumber(20), PrimitiveNumber(30)],
            # row 2: math formulas
            Any[MathBinaryOperation(:+, MathVariable("A"), MathVariable("B")),
                MathBinaryOperation(:*, PrimitiveNumber(2), MathVariable("B")),
                MathBinaryOperation(:-, MathVariable("C"), PrimitiveNumber(5))],
            # row 3: more formulas
            Any[MathBinaryOperation(:/, MathVariable("A"), PrimitiveNumber(2)),
                MathBinaryOperation(:/, MathParenthesized(MathBinaryOperation(:+, MathVariable("A"), MathVariable("C"))), PrimitiveNumber(2)),
                MathBinaryOperation(:*, PrimitiveNumber(3), MathParenthesized(MathBinaryOperation(:+, MathVariable("A"), MathVariable("B"))))],
        ],
        3;
        padding=16)
end

# The table renderer delegates positioning to a GridLayout and recurses each
# cell document through the projection — `NaturalToGraphics` with the sans
# font the workbench/table chrome uses.
make_table_projection_example(; measure=truetype_measure_text) =
    NaturalToGraphics(measure=measure, font=font_ubuntu_regular_20)

make_math_table_projection_example(; measure=truetype_measure_text) =
    NaturalToGraphics(measure=measure, font=font_ubuntu_regular_20)

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

    GraphGraph(
        [v_table, v_json, v_xml],
        [
            GraphEdge(v_table, v_json;  directed=true, label=JsonString("uses")),
            GraphEdge(v_json,  v_xml;   directed=true),
            GraphEdge(v_table, v_xml;   directed=false),
        ],
    )
end

# Json + Xml united under one type-dispatching recursion, for the mixed graph
# vertices above.
function JsonXmlToSyntax()
    RecursiveProjection(TypeDispatchingProjection(
        JsonNull        => JsonNullToSyntaxLeaf(),
        JsonBool        => JsonBoolToSyntaxLeaf(),
        JsonNumber      => JsonNumberToSyntaxLeaf(),
        JsonString      => JsonStringToSyntaxLeaf(),
        JsonArray       => JsonArrayToSyntaxNode(),
        JsonObject      => JsonObjectToSyntaxNode(),
        JsonInsertion   => JsonInsertionToSyntaxLeaf(),
        JsonObjectEntry => CopyingProjection(),
        Vector{Cell}    => CopyingProjection(),
        XmlText         => XmlTextToSyntaxLeaf(),
        XmlElement      => XmlElementToSyntaxNode(),
    ))
end

function make_mixed_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        JsonXmlToSyntax(),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The graph projection: GraphGraph → GraphLayout → GraphicsCanvas, with each
# vertex's content rendered by a per-domain sub-pipeline (the "recursion").
# Defaults to the pure-Julia FallbackLayoutEngine.
function make_graph_projection_example(; measure=truetype_measure_text,
                                       engine=FallbackLayoutEngine(),
                                       content=nothing)
    # A vertex's content can be any domain. Dispatch on the root content type to a
    # complete per-domain pipeline to GraphicsCanvas: tables render directly via
    # TableToGraphics; Json/Xml go through Syntax → Text → Graphics.
    if content === nothing
        content = TypeDispatchingProjection(
            WidgetTable => make_table_projection_example(measure=measure),
            Any         => make_mixed_projection_example(measure=measure),
        )
    end

    graph_stages = ChainingProjection(
        GraphGraphToGraphLayout(engine),
        GraphLayoutToGraphicsCanvas(),
    )

    NestingProjection(graph_stages; recursion=content)
end
