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

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const SelectionModule = ProjecturedKernel.SelectionModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const OperationModule = ProjecturedKernel.OperationModule

include("DocumentCore.jl")
include("Domain.jl")

end # module ProjecturedDomain
