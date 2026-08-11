"""
    ProjecturedPrimitive

The scalar documents — `PrimitiveBool`, `PrimitiveNumber`,
`PrimitiveString` and `PrimitiveInsertion` — with the two range operations
that edit them. The reader half of the pair lives in
`ProjecturedProjection`, which depends on this package.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedPrimitive

using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const SelectionModule = ProjecturedKernel.SelectionModule
const OperationModule = ProjecturedKernel.OperationModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("Primitive.jl")

end # module ProjecturedPrimitive
