"""
    PrimitiveModule

The primitive domain. Editable, domain-independent wrappers for boolean,
number, and string scalar values with selection and identity. Each value
is stored in a reactive Cell so changes are tracked.
"""
module PrimitiveModule

using ..CellModule
using ..DocumentModule
using ..OperationModule
using ..ReferenceModule
using ..SelectionModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: has_document_duplicate
import ..OperationModule: evaluate_operation, operation_reference, retarget_operation,
                          make_inverse_operation

export PrimitiveDocument, ReplaceRangeOperation, ReplaceNumberRangeOperation, ReplaceStringRangeOperation
export has_only_number_characters
export parse_primitive_document, get_primitive_text, find_primitive_document,
       find_exact_primitive_document, make_number_edit_operation, with_value_caret,
       make_incomplete_number_document, make_number_range_operation
export get_type_in_placeholder, make_empty_primitive_document, find_value_range, find_deletion_range,
       make_type_in_edit_operation, make_type_in_commit_operation, make_type_in_cancel_operation
export ObjectField, get_object_field_value, get_object_field_name


include("PrimitiveDocument.jl")
include("ObjectField.jl")


end # module
