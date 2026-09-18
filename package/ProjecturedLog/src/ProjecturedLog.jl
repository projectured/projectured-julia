"""
    ProjecturedLog

What the program said: the log document, the Julia logger that captures into
it, and its syntax printer.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedLog

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DomainModule = ProjecturedDomain.DomainModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const NaturalModule = ProjecturedNatural.NaturalModule

include("../../../source/log/MessageLogModule.jl")

end # module ProjecturedLog
