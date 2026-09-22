"""
    ProjecturedReflection

A bounded shadow of a large or live Julia object: the `UnsyncedDocument`
marker, the sync policies that implement the kernel's `sync_document!` seam,
the reflected node tree, and what draws it.

`ReflectionToWidget` reads a reflected node and writes a widget, so it belongs
here and not in the widget package — a projection belongs to the package of what
it reads, the way `SyntaxToText` is `ProjecturedSyntax`'s.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedReflection

using ProjecturedCollection
using ProjecturedKernel
using ProjecturedWidget

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const FeedModule = ProjecturedKernel.FeedModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const CollectionModule = ProjecturedCollection.CollectionModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const WidgetModule = ProjecturedWidget.WidgetModule

include("../../../source/reflection/ReflectionModule.jl")

end # module ProjecturedReflection
