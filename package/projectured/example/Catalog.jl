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
    () -> RecursiveProjection(SyntaxToText()),
    # text → graphics: WordWrapping + TextToGraphics, measured with the headless
    # `truetype_measure_text` (the same default `run_example` uses). Output is an
    # `RGraphicsCanvas` (<: GraphicsDocument), so `:graphics` entries render via `run_example`.
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
function _text_sequence(@nospecialize(D), doc)
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

    syn = _single_step(D, doc, :syntax)
    syn === nothing || push!(out, variant(:syntax, () -> syn()))

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
