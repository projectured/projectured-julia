# Fragment of `DocumentModule` — the default behaviours every document inherits
# unless it overrides them: the two walk-steering traits (`is_element_collection`
# / `is_walk_opaque`, declared in `DocumentInterface.jl`) and the depth-limited
# debug `show`. The trait defaults keep the walk from ever naming a concrete
# collection type — a document opts into a shape by overriding one, and the walk
# reads the shape off the trait, so it sits below every collection it descends.

is_element_collection(value) = false
is_walk_opaque(value) = false

"""
Maximum nesting depth printed by the generic document `show` before child
documents are abbreviated to `…`. Bounds debug output for deeply nested trees.
"""
const DOCUMENT_SHOW_MAX_DEPTH = 3

"""
    show(io::IO, x::Document)

Default depth-limited debug rendering for documents. Prints constructor-style
`TypeName(field, field, …)`, reading each field through `getproperty` so the
underlying reactive `Cell`s are unwrapped. Recursion is bounded by the
`:document_depth` IOContext key (see [`DOCUMENT_SHOW_MAX_DEPTH`]) so deeply
nested documents do not explode. A field named `selection`, when present, is
skipped as noise. A debug aid only: a domain that wants a *presentable* rendering
writes a projection, not a `show` method.
"""
function Base.show(io::IO, x::Document)
    depth = get(io, :document_depth, 0)
    print(io, nameof(typeof(x)), "(")
    if depth ≥ DOCUMENT_SHOW_MAX_DEPTH
        print(io, "…")
    else
        inner = IOContext(io, :document_depth => depth + 1)
        first = true
        for f in fieldnames(typeof(x))
            f === :selection && continue
            first || print(io, ", ")
            show(inner, getproperty(x, f))
            first = false
        end
    end
    print(io, ")")
end
