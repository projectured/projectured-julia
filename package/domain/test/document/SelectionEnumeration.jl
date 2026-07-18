# ═══════════════════════════════════════════════════════════════════════════
# domain-test/document/SelectionEnumeration.jl
#
# The domain-layer extension of the ground-truth selection enumerators (the
# generic document walk lives in ProjecturedBaseTest): the projection-aware
# JSON whole-element enumerator used by the tree-navigation completeness
# suite.
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
    if node isa JsonObject
        for i in 1:length(node.entries)
            entry = node.entries[i]
            epath = extend_reference(path, FieldReferenceStep("entries"), ElementReferenceStep(i))
            push!(results, epath)                                          # the entry pair node
            push!(results, extend_reference(epath, FieldReferenceStep("key"))) # the key leaf
            _json_collect!(getfield(entry, :value)[],
                           extend_reference(epath, FieldReferenceStep("value")), results)
        end
    elseif node isa JsonArray
        for i in 1:length(node.elements)
            _json_collect!(node.elements[i],
                           extend_reference(path, FieldReferenceStep("elements"), ElementReferenceStep(i)),
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

# ── Example-typed tree-navigation overload ────────────────────────────────

# A structural tree node in the syntax domain is any SyntaxDocument — this
# excludes the CellVector child containers and the TextString delimiter / value
# holders, neither of which is an Alt+arrow tree-selection target.
_is_syntax_node(n) = n isa SyntaxDocument

# Pick the projection-aware enumerator for a document whose navigable tree is
# defined by its projection to syntax rather than by the raw input struct. Native
# syntax trees (and anything else) fall back to the `is_node` predicate by
# returning `nothing`. This lets `test_tree_navigation(json_example;
# check_reaches_all=true)` work without the caller naming the enumerator.
_default_tree_collector(::Any) = nothing
_default_tree_collector(::JsonDocument) = collect_json_tree_selections

function test_tree_navigation(example::Example; check_reaches_all=false, is_node=_is_syntax_node,
                              collect=nothing, seed_broken=nothing, broken=nothing, unreached_broken=nothing)
    collect === nothing && (collect = _default_tree_collector(example.document))
    test_tree_navigation(example.name, example.document, example.projection; check_reaches_all=check_reaches_all,
                         is_node=is_node, collect=collect,
                         seed_broken=seed_broken, broken=broken, unreached_broken=unreached_broken)
end
