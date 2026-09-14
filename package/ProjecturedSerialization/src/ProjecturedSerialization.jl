"""
    ProjecturedSerialization

Persistence. Exact binary serialization, where a `Cell` serializes as its
value alone and the reactive graph is pruned at every cell boundary, and the
natural-format file project: every node marked as a file document becomes its
own text file.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedSerialization

using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const OperationModule = ProjecturedKernel.OperationModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("../../../source/serialization/SerializationModule.jl")

end # module ProjecturedSerialization
