# ═══════════════════════════════════════════════════════════════════════════
# example/Catalog.jl
#
# A *generated* catalog of `(document, projection)` pairs built from the
# hand-authored `atomic_documents` registry: for each atomic document, the
# catalog derives its trivial single-step projection, plus the composite
# projections that reach `:text` and `:graphics` when possible. Every entry is a
# plain `Example` under a hierarchical `domain/name/variant` name (the name
# doubles as the filter), marked `origin = :generated`, so it plugs straight into
# `test_printer` / `run_example`. See plan/pending/atomic-example-catalog.md.
#
# The *documents* are hand-authored (meaningful content, in each domain's
# `example/document/*.jl`); only the *projections* are discovered. Nothing is
# computed at load time — `catalog()` and the projection search run on demand,
# because the search *executes* projections on the documents.
# ═══════════════════════════════════════════════════════════════════════════

# ── The atomic-document registry (hand-authored; tier slices concatenated) ────────
"The hand-authored atomic documents the catalog builds on, every tier's slice concatenated."
atomic_documents() = AtomicDocument[visual_atomic_documents; domain_atomic_documents]

# ── Projection graph: edges = runnable whole-tree bridges (thunks for freshness) ──
# The only declared graph metadata — ~O(domains). Each is `RecursiveProjection`-wrapped
# so it is independently runnable via `print_document(bridge, doc)`. The text→graphics
# tail is named so the derivation can chain it onto any text-reaching sequence.
const _TEXT_TO_GRAPHICS = () -> ChainingProjection(
    WordWrapping(measure = truetype_measure_text),
    TextToGraphics(measure = truetype_measure_text))

const BRIDGES = Function[
    () -> RecursiveProjection(JsonToSyntax()),
    () -> RecursiveProjection(XmlToSyntax()),
    () -> RecursiveProjection(YamlToSyntax()),
    () -> RecursiveProjection(JuliaToSyntax()),
    () -> RecursiveProjection(MarkdownToSyntax()),
    () -> RecursiveProjection(MathToSyntax()),
    () -> RecursiveProjection(BookToSyntax()),
    () -> RecursiveProjection(FileSystemToSyntax()),
    () -> RecursiveProjection(SqlToSyntax()),
    () -> RecursiveProjection(SyntaxToText()),
    # text → graphics: WordWrapping + TextToGraphics, measured with the headless
    # `truetype_measure_text` (the same default `run_example` uses). Output is an
    # `CRGraphicsCanvas` (<: GraphicsDocument), so `:graphics` entries render via `run_example`.
    _TEXT_TO_GRAPHICS,
]

# (input type, bridge index) → output instance | nothing. Bridges (esp. the slow ones)
# run at most once per input type. Output type depends only on input type.
const _STEP_CACHE = Dict{Tuple{DataType,Int},Any}()

# Run-and-inspect one edge: apply bridge `i` to `doc`; return the projected output, or
# `nothing` if it does not apply (any error) or is a no-op (same output type).
function _step(i::Int, doc)
    key = (typeof(doc), i)
    get!(_STEP_CACHE, key) do
        try
            o = unwrap_cell(print_document(BRIDGES[i](), doc).output)
            typeof(o) === typeof(doc) ? nothing : o
        catch
            nothing
        end
    end
end

_terminal_of(@nospecialize T) = !(T isa Type) ? :abstract :
    T <: TextDocument     ? :text :
    T <: GraphicsDocument ? :graphics :
    T <: SyntaxDocument   ? :syntax : :abstract

is_text(@nospecialize T)     = T isa Type && T <: TextDocument
is_graphics(@nospecialize T) = T isa Type && T <: GraphicsDocument
is_syntax(@nospecialize T)   = T isa Type && T <: SyntaxDocument

# All-shortest-paths BFS from `start` to the first frontier where `reached(T)` holds.
# Returns each path as an ordered vector of bridge thunks (empty ⇒ already there).
function path_sequences(start, reached)
    T0 = typeof(start)
    reached(T0) && return [Function[]]
    inst  = Dict{DataType,Any}(T0 => start)
    dist  = Dict{DataType,Int}(T0 => 0)
    preds = Dict{DataType,Vector{Tuple{DataType,Int}}}()
    queue = DataType[T0]; goal = nothing
    while !isempty(queue)
        T = popfirst!(queue)
        goal !== nothing && dist[T] >= goal && continue          # never expand past minimal depth
        for i in eachindex(BRIDGES)
            out = _step(i, inst[T]); out === nothing && continue
            Tp = typeof(out); d = dist[T] + 1
            if !haskey(dist, Tp)                                 # first discovery of Tp
                dist[Tp] = d; inst[Tp] = out; preds[Tp] = [(T, i)]
                reached(Tp) ? (goal = d) : push!(queue, Tp)
            elseif dist[Tp] == d                                 # another equally-short path
                push!(preds[Tp], (T, i))
            end
        end
    end
    goal === nothing && return Vector{Function}[]
    seqs = Vector{Function}[]
    for (Tp, d) in dist
        (d == goal && reached(Tp)) || continue
        append!(seqs, _chains_to(Tp, T0, preds))
    end
    seqs
end

_chains_to(T, T0, preds) = T === T0 ? [Function[]] :
    [ [pre; BRIDGES[i]] for (P, i) in preds[T] for pre in _chains_to(P, T0, preds) ]

_compile(seq::AbstractVector) = isempty(seq) ? IdentityProjection() :
    length(seq) == 1 ? seq[1]() : ChainingProjection((mk() for mk in seq)...)

"All minimal composite projections from `start` to `reached`."
paths(start, reached) = [_compile(seq) for seq in path_sequences(start, reached)]

"One minimal composite projection from `start` to `reached`, or `nothing` if unreachable."
projection_to(start, reached) =
    (ss = path_sequences(start, reached); isempty(ss) ? nothing : _compile(ss[1]))

# ── The trivial single-step projection ────────────────────────────────────────────
# The most trivial single-step projection applicable to document type `D` whose output
# lands in domain `want` (:syntax / :text / :graphics). Leaf stages are macro-generated
# (`@projection_template`), so they live in the `print_document` method table, not in
# source — scan it, run each zero-arg candidate on `doc`, and keep those that genuinely
# transform `doc` into `want`. Deterministic: prefers the lexicographically-first name.
function _single_step(@nospecialize(D), doc, want::Symbol)
    matches = Type[]
    for m in methods(print_document)
        length(m.sig.parameters) == 5 || continue
        projT = m.sig.parameters[2]; docT = m.sig.parameters[4]
        (projT isa Type && docT isa Type)             || continue
        (docT <: Document && docT !== Document)       || continue
        (projT <: Projection && projT !== Projection) || continue
        D <: docT || continue
        local proj; try proj = projT() catch; continue end       # zero-arg stages only
        local out;  try out = unwrap_cell(print_document(proj, doc).output) catch; continue end
        (typeof(out) !== D && _terminal_of(typeof(out)) === want) || continue
        push!(matches, projT)
    end
    isempty(matches) ? nothing : sort!(matches; by = T -> String(nameof(T)))[1]
end

# A projection *sequence* (thunks; compile with `_compile`) reaching `:text` — a direct
# single-step (e.g. primitives, whose `Primitive*ToText*` skips syntax), else the
# whole-tree bridge BFS. `nothing` when text is unreachable from `D`.
#
# A document already AT the text level (a `TextDocument`) is its own `:text` variant:
# the empty sequence compiles to `IdentityProjection`. The BFS below would otherwise
# discard it — `path_sequences` returns the already-there empty path and the
# `!isempty` filter drops it — leaving a text atom with no text (hence no graphics)
# variant. The `:graphics` sequence then chains `_TEXT_TO_GRAPHICS` onto this empty
# base, yielding the default text projection.
function _text_sequence(@nospecialize(D), doc)
    is_text(D) && return Function[]
    t = _single_step(D, doc, :text)
    t === nothing || return Function[() -> t()]
    seqs = filter(!isempty, path_sequences(doc, is_text))
    isempty(seqs) ? nothing : first(seqs)
end

# A projection sequence reaching `:graphics` — a direct single-step (rare), else the text
# sequence chained with the text→graphics tail (graphics only ever arrives via text, so
# reachable exactly when text is). `nothing` when text (hence graphics) is unreachable.
function _graphics_sequence(@nospecialize(D), doc, text_seq)
    g = _single_step(D, doc, :graphics)
    g === nothing || return Function[() -> g()]
    text_seq === nothing ? nothing : Function[text_seq...; _TEXT_TO_GRAPHICS]
end

# ── Names, domain, runnability ──────────────────────────────────────────────────────
# The hierarchical `domain/name/variant` name doubles as the filter path; `catalog_domain`
# reads the domain level straight back off it.
catalog_domain(ex::Example) = Symbol(first(split(ex.name, '/')))
runnable(ex::Example) = ex.terminal in (:text, :graphics)   # graphics→screen/web, text→console

# A document whose own gestures can change its type: a domain's insertion buffer (Enter
# commits it to a concrete node) or its nothing placeholder (Insert turns it into that
# insertion). A bare single-type leaf cannot reproject the swapped type — reprinting an
# `CRJuliaNothing` walk after `:insert` through `JuliaNothingToSyntaxLeaf` throws once the
# document has become a `JuliaInsertion` — so such an atom's syntax variant must use the
# domain's whole-tree dispatching projection instead (what its text/graphics variants
# already chain through). `domain_insertion(D)` names the domain's insertion for any of
# its documents; `nothing_document` names the matching placeholder.
#
# `D` here is the *reactive* document type — `@document` makes `CRJuliaNothing` an alias for
# `JuliaNothing{cell kinds…}`, a parameterization of the base `JuliaNothing` — while the
# domain traits return the base types. Compare with `<:`, not `===`, so the parameterized
# reactive type still matches (the insertion/nothing types are concrete leaves, so `<:`
# is exact — nothing else is a subtype).
function _self_modifying(@nospecialize D)
    ins = domain_insertion(D)
    ins === nothing && return false
    D <: ins || D <: nothing_document(ins)
end

# Does the trivial single-step syntax projection stand alone? Only if its output is a bare
# `SyntaxLeaf` — nothing to recurse into. A compound output (a `SyntaxNode` or wrapper) is
# built by projecting child documents through `print_child`, which a bare stage can't do
# (it carries no recursion → `print_document(nothing, …, child, …)` throws), so such an
# atom must go through the domain's dispatching projection. Dispatching is always a valid
# superset, so this only ever *widens* the choice; a genuine leaf keeps its isolated step.
function _single_step_leaf(projT, doc)
    out = try unwrap_cell(print_document(projT(), doc).output) catch; return false end
    out isa SyntaxLeaf
end

# ── Generator: up to three Examples per atomic document ─────────────────────────────
# `domain/name/syntax` (trivial single-step), `domain/name/text`, `domain/name/graphics`.
# Each is a plain `Example` (origin = :generated); variants that aren't reachable are
# skipped ("…and to graphics if possible"). Building an Example is cheap — the projection
# objects are constructed, not run; the slow pipeline runs only when a test/example prints.
function _atom_examples(ad::AtomicDocument)
    doc = ad.make_document()
    D   = typeof(doc)
    out = Example[]
    variant(term, mkproj) = Example("$(ad.domain)/$(ad.name)/$(term)",
                                    ad.make_document, mkproj;
                                    terminal = term, origin = :generated)

    # The syntax variant is the trivial single-step leaf — but only when that leaf can
    # stand alone. It cannot when the document is self-modifying (its own gestures swap its
    # type, which a single-type leaf can't reproject) or compound (its node projection
    # recurses into child documents, which the bare stage has no recursion for). Both take
    # the domain's whole-tree dispatching projection reaching :syntax instead (skipped if
    # the domain has no such bridge).
    syn = _single_step(D, doc, :syntax)
    if syn !== nothing && !_self_modifying(D) && _single_step_leaf(syn, doc)
        push!(out, variant(:syntax, () -> syn()))
    else
        syn_seqs = filter(!isempty, path_sequences(doc, is_syntax))
        isempty(syn_seqs) || push!(out, variant(:syntax, () -> _compile(first(syn_seqs))))
    end

    text_seq = _text_sequence(D, doc)
    text_seq === nothing || push!(out, variant(:text, () -> _compile(text_seq)))

    gfx_seq = _graphics_sequence(D, doc, text_seq)
    gfx_seq === nothing || push!(out, variant(:graphics, () -> _compile(gfx_seq)))

    out
end

"""
    catalog(; domain=nothing, document=nothing, terminal=nothing, only_runnable=false)

The generated catalog: for each hand-authored `AtomicDocument`, its trivial single-step
projection plus the composite projections reaching `:text` and `:graphics`, as plain
`Example`s under hierarchical `domain/name/variant` names. Filter by document `domain`,
document `name`, projection `terminal`, or `only_runnable` — the same three axes the name
path encodes. Every entry feeds `test_printer` / `run_example` unchanged.
"""
function catalog(; domain = nothing, document = nothing, terminal = nothing, only_runnable = false)
    cs = Example[]
    for ad in atomic_documents()
        (domain   === nothing || ad.domain === domain)   || continue
        (document === nothing || ad.name   === document) || continue
        for ex in _atom_examples(ad)
            (terminal === nothing || ex.terminal === terminal) || continue
            (!only_runnable || runnable(ex))                   || continue
            push!(cs, ex)
        end
    end
    cs
end
