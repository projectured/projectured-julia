# Fragment of `DocumentModule` — the `Document` abstract supertype. Introduces
# the type; the `@document` codegen that declares most concrete documents lives
# in the sibling `DocumentMacro.jl` fragment, and the value protocol every
# document reuses in `DocumentCopy.jl` / `DocumentSync.jl`.

"""
    Document

Abstract base type for all document types. Most concrete documents are
declared with the [`@document`](@ref) macro (in the sibling
[`DocumentMacro.jl`](DocumentMacro.jl) fragment), which wraps fields in
reactive `Cell`s and generates the shared value protocol; a hand-written struct
may also subtype `Document` directly.
"""
abstract type Document end
