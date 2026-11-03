# Fragment of `ReferenceModule` — the two searches of the documents: one answers
# the matching nodes, or each node with its place, and one answers the places as
# references. Both run the one walk of the document layer, `walk_document`, along a
# `DocumentWalk`. With `paths = true` the walk names a match by the chain of steps
# that reached it, and this file turns a chain into a `Reference`; the walk itself
# knows nothing of references.

# The `Reference` of a chain of steps that `walk_document(…; paths = true)`
# answers: `()` for the root, and `parent => step` below it. Read from the deepest
# step back to the root.
function _make_location_reference(location)
    path = EmptyReference()
    while location isa Pair
        step = location.second
        head = step isa Int ? ElementReferenceStep(step) :
                              FieldReferenceStep(string(step))
        path = ConcreteReference(head, path)
        location = location.first
    end
    path
end

# What a path answers when it does not read back to a node.
struct _UnreadPath end

# The places of the matches of a walk of `root` along `walk`, each as
# `make(node, reference)` in a vector of `T`. The reference records the type of each
# node it stands on, from `root`, and comes after `prefix`, the place of `root`. A
# match whose path does not read back to a node is left out, and the limits of the
# answer count it.
function _search_places(make, ::Type{T}, root, predicate, walk::DocumentWalk, prefix::Reference;
                        keywords...) where {T}
    locations = walk_document(walk, root, predicate; paths = true, keywords...)
    places = T[]
    unreadable_count = 0
    for location in locations
        path = _make_location_reference(location)
        node = try
            evaluate_reference(root, path)
        catch exception
            is_fault_exception(exception) || rethrow()
            _UnreadPath()
        end
        if node isa _UnreadPath
            unreadable_count += 1
            continue
        end
        typed = annotate_reference_types(root, path)
        push!(places, make(node, prefix isa EmptyReference ? typed : concat_references(prefix, typed)))
    end
    limits = locations.limits
    DocumentMatches(places, WalkLimits(limits.limit, limits.is_limit_reached, limits.maxdepth,
                                       limits.depth_stop_count, limits.background, limits.provisional_count,
                                       limits.maxvisits, limits.is_visit_limit_reached, unreadable_count))
end

"""
    search_documents(x, predicate; walk = DocumentWalk(), places = x isa ReferencedDocument,
                     limit = 100, maxdepth = 64, maxvisits = 100_000, raw = false,
                     background = false, enter_matches = true, on_error) -> DocumentMatches
    search_documents(x, query::Union{AbstractString,Regex}; …) -> DocumentMatches

Walk `x` along `walk` and answer the matching nodes. A `String` (a substring) or a
`Regex` matches leaf nodes by their string form, and a predicate matches any node.
By default the answer is **document-scoped**: a scalar match folds up to the
nearest enclosing `Document`, so every match is a node that a person can select;
pass `raw = true` for the exact matched value.

With `places = true` each match is a part, a `ReferencedDocument`: the node with its
place, the path to it from `x`. A search of the editor's document answers places in
the window, which a verb that needs a place takes as they are. A search of a part
answers places by default, each after the place of the part. A match whose path
does not read back to it is left out, and the answer counts it.

`walk` decides which nodes the search visits. The default visits each node once,
at the first path that reaches it, and does not enter the mouse target, the
selection, or a field that a document keeps out of a walk, such as the old
versions that undo keeps. Pass another `DocumentWalk` to search along another
route. To search the old versions, search the list of an undo buffer itself.

The search has three bounds, each with a default that keeps a search of a large
document small: at most `limit = 100` matches, no deeper than `maxdepth = 64`, and
at most `maxvisits = 100_000` nodes visited, or every node with `limit = nothing`.
It starts no background work, so a value that a task still computes is taken as it
is. The answer is a [`DocumentMatches`](@ref), a vector of the matches, whose first
line says which bound stopped the search and the keyword that lifts it:
`limit = nothing` finds every match, `maxvisits = nothing` visits every node, and
`background = true` waits for the values still to come. `is_search_complete`
answers whether no bound left a match out. `enter_matches` and `on_error` are
those of `walk_document`.

Use it to find the documents that hold a text, or that a test accepts, anywhere in a
document or in the window, and with `places = true` to act on them.

# Example

    matches_1 = search_documents(editor.document, "temperature"; places = true)
    get_parent(editor.document, matches_1[1])     # the document that holds the first match

See also `search_references`, `DocumentWalk` and `get_edited_document`.

For the assistant.
"""
function search_documents end

function search_documents(x, predicate; walk::DocumentWalk = DocumentWalk(), places::Bool = false, keywords...)
    places || return walk_document(walk, x, predicate; keywords...)
    _search_places((node, reference) -> ReferencedDocument(node, reference), ReferencedDocument,
                   unwrap_cell(x), predicate, walk, EmptyReference(); keywords...)
end

search_documents(x, query::Union{AbstractString,Regex}; keywords...) =
    search_documents(x, make_string_predicate(query); keywords...)

"""
    search_references(x, predicate; walk = DocumentWalk(), limit = 100, maxdepth = 64,
                      maxvisits = 100_000, raw = false, background = false) -> DocumentMatches{Reference}
    search_references(x, query::Union{AbstractString,Regex}; …) -> DocumentMatches{Reference}

Walk `x` along `walk` and answer a `Reference` to every match: the places of
`search_documents(x, predicate; places = true)`, without their nodes. Pass a
predicate, or a `String` (substring) / `Regex` that matches leaf nodes by their
string form, e.g. `search_references(document, "Alice")` or
`search_references(document, r"TODO|FIXME")`. Cells are unwrapped transparently (no
path step); struct fields contribute a `FieldReferenceStep`, and array /
`CellVector` elements an `ElementReferenceStep`. A search of a part answers
references from the root of the part.

By default the paths are **document-scoped**: a match on a raw scalar folds to
the path of its nearest enclosing `Document`, so every returned path addresses a
selectable node. Pass `raw=true` to get the path to the **exact matched node**
instead (scalar leaves included).

The returned paths are **canonical at rest**: each node records the type of the
document node that it stands on (via [`annotate_reference_types`](@ref)), so results
are self-describing and can be checked again after an edit. `evaluate_reference`
checks those types; pass a result through `strip_reference_types` first if a
consumer needs the plain navigation-only path.

```julia
@document struct Note
    text::String
end

for reference in search_references(document, v -> v isa Note && occursin("TODO", v.text))
    note = evaluate_reference(document, reference)   # the matching Note
end
```

The default walk answers one path for each node, the first that reaches it. A node
that two places share, such as a note that stands at two places, has a path at each
place: `walk = DocumentWalk(; policy = :once_per_path)` answers every path, which
code that asks whether a node stands at one place needs. That walk visits a shared
part once for each path, so its cost grows with the sharing. The bounds, the walk
and the answer are those of [`search_documents`](@ref).

`x` need not be a document — the walk descends **any** object graph (structs,
arrays, dicts), not only document trees. Searching derived/intermediate state for
debugging is one such use; the debugging guide's "Searching the pipeline state"
covers it (those paths are for inspection only, not selectable).

Use it to find where in a document the matches are, as references that you can read, select or open.

# Example

    references_1 = search_references(document_1, "TODO")

See also `search_documents` and `evaluate_reference`.

For the assistant.
"""
function search_references end

search_references(x, predicate; walk::DocumentWalk = DocumentWalk(), keywords...) =
    _search_places((node, reference) -> reference, Reference, unwrap_cell(x), predicate, walk, EmptyReference();
                   keywords...)

search_references(x, query::Union{AbstractString,Regex}; keywords...) =
    search_references(x, make_string_predicate(query); keywords...)
