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

const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CellModule = ProjecturedKernel.CellModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("Color.jl")
include("Font.jl")
include("TrueType.jl")
include("Geometry.jl")
include("Image.jl")
include("StyleStroke.jl")
include("StyleText.jl")

end # module ProjecturedStyle
