# A heterogeneous document for the natural projection: a CellVector combinator
# holding a mix of domain documents (JSON, Math, Julia, XML). It exercises
# NaturalToGraphics across several domains *and* through a collection combinator
# in a single example — exactly the cross-domain nesting the natural projection
# exists to handle.
#
# These are all *syntax-producible* domains, so each element projects cleanly
# through the shared `natural_to_syntax` fabric into one syntax tree. (A raw
# `TextText` placed directly in a collection would instead reflect via the
# `Any`/`ObjectToSyntax` fallback — prose's clean path is the to-graphics
# `TextDocument` entry, e.g. as conversation-part content; see the limitation
# noted in the plan.)
function make_natural_document_example()
    CellVector(Cell[
        Cell(make_json_document_example()),
        Cell(make_math_document_example()),
        Cell(make_julia_document_example()),
        Cell(make_xml_document_example()),
    ])
end
