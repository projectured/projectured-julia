"""
    ProjecturedPrimitive

The scalar documents — `PrimitiveBool`, `PrimitiveNumber`,
`PrimitiveString` and `PrimitiveInsertion` — with the two range operations
that edit them. The reader half of the pair lives in
`ProjecturedProjection`, which depends on this package.

`ObjectField` sits here too. It is domain-neutral like the scalars, and it is
placed in the lowest package both `ProjecturedWidget` and `ProjecturedSyntax`
already depend on, so its two projections can reach it.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedPrimitive

using ProjecturedKernel
using ProjecturedSerialization

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const SelectionModule = ProjecturedKernel.SelectionModule
const OperationModule = ProjecturedKernel.OperationModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SerializationModule = ProjecturedSerialization.SerializationModule

include("../../../source/primitive/PrimitiveModule.jl")

end # module ProjecturedPrimitive
