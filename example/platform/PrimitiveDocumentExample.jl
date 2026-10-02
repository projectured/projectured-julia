function make_primitive_string_document_example()
    PrimitiveString("Hello, world")
end

function make_primitive_number_document_example()
    PrimitiveNumber(42)
end

function make_primitive_bool_document_example()
    PrimitiveBool(true)
end

# A type-in limited to a number, with a text that is no number yet, on the way to
# `-.5`. No single insert or delete makes it a number, so every key of a sweep
# that types one character is an edit of its text; a key that makes a number
# replaces the type-in, which `test_primitive_type_in` covers.
function make_primitive_insertion_document_example()
    PrimitiveInsertion(; value = "-.", allowed_types = (PrimitiveNumber,))
end
