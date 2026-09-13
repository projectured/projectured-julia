"""
    ProjecturedStyle

The pure value types every visual thing shares: colour, font, geometry,
image, stroke and styled text, plus the TrueType parser that measures text
without a backend.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedStyle

using ProjecturedKernel

const DocumentModule = ProjecturedKernel.DocumentModule
const CellModule = ProjecturedKernel.CellModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("../../../source/style/Color.jl")

end # module ProjecturedStyle
