"""
    ProjecturedPdf

The PDF backend. It exports the graphics domain as a vector PDF and needs no
third-party package, so the umbrella still aggregates it. It is a peer of
`ProjecturedSdl`, `ProjecturedWeb` and `ProjecturedConsole`, which is what a
concrete backend is.

The submodules below are aliased so this package's source file keeps its
relative `..XxxModule` references.
"""
module ProjecturedPdf

using ProjecturedKernel
using ProjecturedGraphics
using ProjecturedStyle

const CellModule = ProjecturedKernel.CellModule
const IoMapModule = ProjecturedKernel.IoMapModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule

include("../../../source/pdf/Pdf.jl")

end # module ProjecturedPdf
