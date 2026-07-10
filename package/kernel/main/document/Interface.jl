# Fragment of `DocumentModule` — the `Document` abstract supertype. Introduces
# the type; the `@document` codegen and shared value protocol every concrete
# document reuses live in the sibling `Document.jl` fragment.

"""
    Document

Abstract base type for all document types. Most concrete documents are
declared with the [`@document`](@ref) macro (in the sibling
[`Document.jl`](Document.jl) fragment), which wraps fields in reactive `Cell`s
and generates the shared value protocol; a hand-written struct may also
subtype `Document` directly.
"""
abstract type Document end
