# A heterogeneous document for the natural projection: a CellVector combinator
# holding a mix of domain documents (JSON data, Math, Julia code, Text prose,
# XML markup). It exercises NaturalToGraphics across several domains *and*
# through a collection combinator in one example — exactly the cross-domain
# nesting the natural projection exists to handle.
#
# The collection renders as a vertical stack of independent graphics blocks
# (CellVectorToVerticalLayout → VerticalLayoutToGraphicsCanvas), so each element
# is rendered in its *own* domain: the JSON/Math/Julia/XML elements as their
# syntax presentations and the Text element as wrapped prose.
function make_natural_document_example()
    CellVector(Cell[
        Cell(make_json_document_example()),
        Cell(make_math_document_example()),
        Cell(make_julia_document_example()),
        Cell(make_text_document_example()),
        Cell(make_xml_document_example()),
    ])
end
