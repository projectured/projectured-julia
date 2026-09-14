"""
    ProjecturedVersioning

The `VersionedObject` overlay document, its version criteria, and the
projection that selects one version and projects its value in place of the
wrapper.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedVersioning

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedPrimitive

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IntentModule = ProjecturedKernel.IntentModule
const OperationModule = ProjecturedKernel.OperationModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DomainModule = ProjecturedDomain.DomainModule
const SelectionModule = ProjecturedKernel.SelectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IoMapModule = ProjecturedKernel.IoMapModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule

include("../../../source/versioning/VersioningDocument.jl")

end # module ProjecturedVersioning
