# Fragment of `ClipboardModule`.
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

# A clipboard wraps a whole window and is transparent on the screen, so anything
# that reads the tree rather than the picture must be able to look past it. The
# contract of `get_wrapped_document` names this case by name.
get_wrapped_document(slice::ClipboardSlice) = get_wrapped_document(slice.content)
get_wrapped_document(collection::ClipboardCollection) =
    get_wrapped_document(collection.content)
