"""
    ProjecturedComponent

A named, reusable widget composition. The package imports no widget type.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedComponent

using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("../../../source/component/ComponentDocument.jl")

end # module ProjecturedComponent
