# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/SelectionEnumeration.jl
#
# Umbrella-level extensions of the ground-truth selection enumerators. The
# generic document walk (`_walk_document`, `collect_text_selections`,
# `collect_tree_selections`) lives in ProjecturedBaseTest; this file adds the
# pieces that need higher-layer vocabulary until they migrate to their own
# test packages (plan/pending/test-package-split.md):
#   * `collect_json_tree_selections` — domain (phase 3).
# ═══════════════════════════════════════════════════════════════════════════

# ── JSON whole-element enumeration ────────────────────────────────────────
#
# The JSON document is NOT a native syntax tree: JsonToSyntax projects it to one,
# decomposing each object entry into a pair node [key leaf, value subtree]. So the
# Alt+arrow-reachable whole-element set is: the root (∅); for every object entry
# its pair node (`.entries[i]`), key leaf (`.entries[i].key`) and value subtree
# (`.entries[i].value`, recursed); every array element (`.elements[i]`, recursed).
# Scalars (string / number / bool / null) expose no children. Walk exactly that
# decomposition so the path strings match navigation output.

function _json_collect!(node, path, results)
    push!(results, path)                          # the whole element at this node
    if node isa Projectured.JsonObject
        for i in 1:length(node.entries)
            entry = node.entries[i]
            epath = append_reference(path, FieldReference("entries"), ElementReference(i))
            push!(results, epath)                                          # the entry pair node
            push!(results, append_reference(epath, FieldReference("key"))) # the key leaf
            _json_collect!(getfield(entry, :value)[],
                           append_reference(epath, FieldReference("value")), results)
        end
    elseif node isa Projectured.JsonArray
        for i in 1:length(node.elements)
            _json_collect!(node.elements[i],
                           append_reference(path, FieldReference("elements"), ElementReference(i)),
                           results)
        end
    end
    results
end

"""
    collect_json_tree_selections(document::JsonDocument) -> Vector{ReferencePath}

Every Alt+arrow-reachable whole-element selection in a JSON document: the root
(∅), each object entry (`.entries[i]`) with its key (`.entries[i].key`) and value
(`.entries[i].value`), each array element (`.elements[i]`), recursing into every
value / element subtree. Mirrors JsonToSyntax's entry pair-node decomposition, so
the path strings match navigation output.
"""
collect_json_tree_selections(document) =
    _json_collect!(document, EmptyReferencePath(), ReferencePath[])
