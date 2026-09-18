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
import ..OperationModule: evaluate_operation, reroot_operation, operation_reference, retarget_operation, make_inverse_operation

export PrimitiveDocument, ReplaceRangeOperation, ReplaceNumberRangeOperation, ReplaceStringRangeOperation
export ObjectField, get_object_field_value, get_object_field_name


include("PrimitiveDocument.jl")
include("ObjectField.jl")

end # module
