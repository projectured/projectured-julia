# ──────────────────────────────────────────────────────────────────────────
# Folded in from ClipboardDocument.jl.
#
# Clipboard document types — a `ClipboardSlice` (content + slice reference) and
# a `ClipboardCollection` (content + sequence of elements).
# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type ClipboardDocument <: Document end

# ── ClipboardInsertion ─────────────────────────────────────────────────────

@document struct ClipboardInsertion <: ClipboardDocument
    value::Any = nothing
end

# ── ClipboardSlice ────────────────────────────────────────────────────────────

"""
Clipboard entry: `content` document + `slice` reference identifying the
copied portion.
"""
@document struct ClipboardSlice <: ClipboardDocument
    content::Document
    slice::Any = nothing
end

"""
Clipboard entry: `content` document + sequence of extracted `elements`.
"""
@document struct ClipboardCollection <: ClipboardDocument
    content::Document
    elements::CellVector = CellVector()
end
