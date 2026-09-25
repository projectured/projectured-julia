"""
    ProjecturedHelp

What the Help menu of a window opens: the list of the document types, the list
of the projections, the page about the program, and their syntax printers.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedHelp

using ProjecturedDomain
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DomainModule = ProjecturedDomain.DomainModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const NaturalModule = ProjecturedNatural.NaturalModule
const SerializationModule = ProjecturedSerialization.SerializationModule

include("../../../source/help/HelpModule.jl")

end # module ProjecturedHelp
