function make_primitive_string_document_example()
    document = PrimitiveString("Hello, world")
    set_selection!(document, @reference value{0})
    document
end
