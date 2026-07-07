# ═══════════════════════════════════════════════════════════════════════════
# visual-test/document/SelectionEnumeration.jl
#
# The visual-layer extension of the ground-truth selection enumerators (the
# generic document walk lives in ProjecturedBaseTest).
# ═══════════════════════════════════════════════════════════════════════════

# A `TextString` is a text leaf: it has no `length`/`getindex`, so
# `set_selection!` stops at it and stores `{k}` relative to it — the cursor
# path is `.value{k}`, NOT `.value.content{k}`.
function _text_leaf_length(v::TextString)
    c = v.content
    length(c isa Cell ? c[] : c)
end
