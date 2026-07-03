"""
    TooltipDocumentModule

`TooltipSource` — a transparent wrapper Document used to mark a sub-tree
of the input as a potential tooltip anchor. It carries the tooltip's
content document, plus the style and id that the eventual tooltip
`WindowDocument` should have.

`TooltipSource` is *not* the tooltip — the tooltip is the
`WindowDocument` that gets added to `ScreenDocument.windows` once the
`TooltipDecoratorProjection` reader emits an `OpenWindowOperation` and
the `WindowManagingProjection` reader applies it. The source just sits in
the input tree and gives the decorator something to dispatch on.
"""
module TooltipDocumentModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference

export TooltipSource, ITooltipSource

"""
    TooltipSource(; child, content, style=:tooltip, id)

A transparent wrapper around `child`. The printer side of
`TooltipDecoratorProjection` projects this as if the source weren't
there (output is what `child` projects to). The reader side watches
events arriving at this node and emits `OpenWindowOperation` /
`CloseWindowOperation` carrying `content`, `style`, and `id`.

# Fields

- `child::Document` — the node being decorated. Projected like any
  other document.
- `content::Document` — the document to render inside the tooltip
  window. Carried into `OpenWindowOperation.content`.
- `style::Symbol` — forwarded to the eventual `WindowDocument.style`.
- `id::Symbol` — backend window id; must be unique within the screen.
"""
@document struct TooltipSource
    child::Document
    content::Document
    style::Symbol = :tooltip
    id::Symbol
    selection::Reference = nothing
end

end # module
