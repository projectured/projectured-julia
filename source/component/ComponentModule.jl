"""
    ComponentModule

The component document domain. Components are higher-level UI building blocks
composed from widget primitives. While widgets provide atomic UI elements
(labels, text fields, scroll panes, split panes), components combine them
into reusable, behavioral units that deliver user-facing functionality.

Components sit between the widget layer and the application layer (workbench):

    Document (domain data) → Component (behavioral UI) → Widget (atomic UI) → Graphics → Screen

A component is meant to project to a widget tree via its own projection
(`ComponentToWidget` — not yet implemented, tracked in
`plan/pending/component-document.md`), and can be embedded anywhere a
Document is accepted — inside a WorkbenchEditor, inside another component,
or as a standalone top-level document.
"""
module ComponentModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule

export ComponentDocument


include("ComponentDocument.jl")

end # module
