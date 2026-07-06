# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/SelectionEnumeration.jl
#
# Ground-truth enumeration of the possible selections in a document, derived
# directly from the document tree (not from navigation). The navigation suites
# (TextNavigationTest.jl, SyntaxTreeNavigationTest.jl) compare these against the
# states their BFS actually reaches.
#
# collect_text_selections(document) -> Vector{ReferencePath}
#   Every text caret: for each navigable String leaf of length n, the cursors
#   {0}…{n} (PositionReference). Numeric leaves are skipped (phase 1).
#
# collect_tree_selections(document; is_node) -> Vector{ReferencePath}
#   Every whole-element (∅) selection: the path terminating at each node for
#   which `is_node` holds. The root is EmptyReferencePath() (∅).
#
#   What counts as a *structural* node is domain-specific (it is defined by the
#   projection to syntax, not by the raw input struct): a CellVector container
#   (`.children`, `.entries`) and a leaf's text-holder fields (`.open`, `.value`,
#   …) carry a `selection` field but are NOT reached by Alt+arrow tree
#   navigation. Callers therefore pass a domain predicate; the syntax suite uses
#   `n -> n isa SyntaxDocument`, which reproduces exactly the navigation-reached
#   set for a native syntax tree. The default predicate (any node with a
#   `:selection` field) is for REPL convenience only.
#
# Both share `_walk_document`, which descends using ONLY the two moves the
# canonical selection machinery uses (set_selection! / evaluate_reference):
#   * FieldReference  → getfield, unwrapping a Cell
#   * ElementReference → document[i] (CellVector indexing)
# so the generated path strings are identical to what read_intent returns.
# (The generic collect_references walker is deliberately NOT reused: it descends
# into a CellVector's internal `elements` field and so yields non-canonical
# paths like `.elements.elements[i]` instead of `.elements[i]`.)
# ═══════════════════════════════════════════════════════════════════════════

# A text leaf is a node a caret sits *directly* on (its path ends in `{k}`):
# either a raw String, or a `TextString` (which has no `length`/`getindex`, so
# `set_selection!` stops at it and stores `{k}` relative to it — the cursor path
# is `.value{k}`, NOT `.value.content{k}`). `_text_leaf_length` returns the
# character count, or `nothing` if the value is not a text leaf.
_text_leaf_length(v::AbstractString) = length(v)
function _text_leaf_length(v::Projectured.TextString)
    c = v.content
    length(c isa Cell ? c[] : c)
end
_text_leaf_length(::Any) = nothing

# Walk `node` (reached at `path`), invoking:
#   on_node(node, path)           — once per visited node (closure filters)
#   on_text(field_path, charcount)— once per text leaf reached via a field
# `seen` guards against cycles by objectid.
function _walk_document(node, path, on_node, on_text, seen::Set{UInt64})
    node === nothing && return
    oid = objectid(node)
    oid in seen && return
    push!(seen, oid)

    on_node(node, path)

    if node isa CellVector
        # Sequence container: descend by element, matching `.f[i]`.
        for i in 1:length(node)
            child = node[i]                       # CellVector getindex unwraps the Cell
            _walk_document(child, append_reference(path, ElementReference(i)),
                           on_node, on_text, seen)
        end
        return
    end

    # Record struct: descend each field (a Cell or a direct sub-document).
    T = typeof(node)
    isstructtype(T) || return
    for fname in fieldnames(T)
        fname === :selection && continue
        fv = getfield(node, fname)
        v  = fv isa Cell ? fv[] : fv
        v === nothing && continue
        v isa Union{Number, Bool, Symbol, ReferencePath} && continue
        field_path = append_reference(path, FieldReference(string(fname)))
        n = _text_leaf_length(v)
        if n !== nothing
            on_text(field_path, n)               # caret sits directly on this field
        elseif v isa CellVector || hasproperty(v, :selection)
            _walk_document(v, field_path, on_node, on_text, seen)
        end
    end
end

# `collect_text_selections` / `collect_tree_selections` extend the open
# generics declared beside the navigation drivers in ProjecturedKernelTest.
"""
    collect_text_selections(document) -> Vector{ReferencePath}

Every navigable text caret in `document`: for each String leaf of length `n`,
the cursors `{0}…{n}` (PositionReference). Numeric leaves are skipped (phase 1).
Candidates are filtered through the document-aware `is_valid_reference`.
"""
function collect_text_selections(document)
    results = ReferencePath[]
    on_node = (_n, _p) -> nothing
    on_text = (field_path, charcount) -> begin
        for k in 0:charcount
            push!(results, append_reference(field_path, PositionReference(k)))
        end
    end
    _walk_document(document, EmptyReferencePath(), on_node, on_text, Set{UInt64}())
    # No is_valid_reference filter: a caret terminates with `{k}` on the text
    # leaf, and the document-aware validator rejects that step whenever the leaf
    # is a TextString (no length/getindex) — yet such carets are real, navigable
    # selections. The walker only emits paths to leaves it actually reached, so
    # every result is well-formed by construction.
    results
end

"""
    collect_tree_selections(document; is_node = n -> hasproperty(n, :selection))
        -> Vector{ReferencePath}

Every whole-element (∅) selection in `document`: the path terminating at each
node for which `is_node` holds. The root yields `EmptyReferencePath()` (∅).
Candidates are filtered through the document-aware `is_valid_reference`.

`is_node` selects which nodes are *structurally* selectable; this is
domain-specific (see the file header). The default — any node carrying a
`selection` field — over-includes containers and text-holders, so suites pass a
domain predicate (the syntax suite uses `n -> n isa SyntaxDocument`).
"""
function collect_tree_selections(document; is_node = n -> hasproperty(n, :selection))
    results = ReferencePath[]
    on_node = (n, path) -> is_node(n) && push!(results, path)
    on_text = (_p, _n) -> nothing
    _walk_document(document, EmptyReferencePath(), on_node, on_text, Set{UInt64}())
    filter!(p -> is_valid_reference(document, p), results)
    results
end

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
