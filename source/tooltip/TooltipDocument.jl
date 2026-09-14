# Fragment of `TooltipModule` — the tooltip document types: the source that
# carries a child and the content to show beside it.

@document struct TooltipSource
    child::Document
    content::Document
    style::Symbol = :tooltip
    id::Symbol
end
