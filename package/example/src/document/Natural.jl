# A heterogeneous document for the natural projection: a CellVector combinator
# holding a mix of domain documents (JSON, Math, Text, XML). It exercises
# NaturalToGraphics across several domains *and* through a collection combinator
# in a single example, which is exactly the cross-domain nesting the natural
# projection exists to handle.
function make_natural_document_example()
    CellVector(Cell[
        Cell(make_json_document_example()),
        Cell(make_math_document_example()),
        Cell(make_text_document_example()),
        Cell(make_xml_document_example()),
    ])
end
