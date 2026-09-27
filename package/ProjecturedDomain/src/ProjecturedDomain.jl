"""
    ProjecturedDomain

What a document domain is: the empty, insertion and reference documents,
the `@domain` macro, and the reflection-based insertion completion. The
twenty source domains are its consumers, not its namesakes.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedDomain

using ProjecturedKernel
using ProjecturedSerialization

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const SelectionModule = ProjecturedKernel.SelectionModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const OperationModule = ProjecturedKernel.OperationModule
const SerializationModule = ProjecturedSerialization.SerializationModule

include("../../../source/domain/DomainModule.jl")

end # module ProjecturedDomain
