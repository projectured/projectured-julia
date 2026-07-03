# ═══════════════════════════════════════════════════════════════════════════
# example/src/Catalog.jl
#
# A *generated* catalog of `(document, projection)` pairs — `Example`s that are
# discovered from the code rather than hand-authored, and serve double duty as
# test fixtures and runnable examples. See plan/pending/discovered-example-catalog.md.
#
# Nothing here is computed at load time (no `const` catalog): `catalog()` and the
# graph search run on demand, because the search *executes* projections.
# ═══════════════════════════════════════════════════════════════════════════

# ── Reflection: declared field types via the @document `I`-companion ─────────────
# `@document Foo` erases the runtime struct's field types to `Cell`, but generates an
# immutable `IFoo` whose fields keep the *declared* types. That companion is our handle
# for what each field minimally needs. (Phase 1 replaces this with a generated
# `document_field_types` accessor + container element-type annotations.)
_icompanion_name(::Type{T}) where {T} = Symbol(:I, nameof(T))
_has_icompanion(::Type{T}) where {T} = isdefined(parentmodule(T), _icompanion_name(T))
_icompanion(::Type{T}) where {T} = getfield(parentmodule(T), _icompanion_name(T))
# The `I`-companion's fields are `ImmutableCell{T}` (the immutable cell kind); unwrap
# to the declared element type `T` the instantiator/leaf-check actually need. Document
# types are *abstract umbrellas* (`JsonNull`) over reactive/immutable kinds (`RJsonNull`
# / `IJsonNull`), so we key on `<: Document`, never on `isconcretetype`.
_uncell(ft) = (ft isa DataType && ft <: AbstractCell && !isempty(ft.parameters)) ? ft.parameters[1] : ft
_declared_field_types(::Type{T}) where {T} = Any[_uncell(ft) for ft in fieldtypes(_icompanion(T))]

_unwrap(o) = o isa AbstractCell ? o[] : o

# A leaf document has no field that holds another document (a `CellVector` counts —
# it is `<: Document`). Node documents need a `recursion` argument to project their
# children, so they are left to the reachability graph and the AtomicFixture tier.
_holds_document(ft) = (ft isa Type && ft <: Document) ||
                      (ft isa Union && any(_holds_document, Base.uniontypes(ft)))

function is_leaf_document(::Type{T}) where {T<:Document}
    _has_icompanion(T) || return true
    !any(_holds_document, _declared_field_types(T))
end

# ── Minimal instantiation ────────────────────────────────────────────────────────
# The smallest valid instance of a document type. Fully-defaulted structs construct
# with no args; otherwise build each declared field minimally and call the positional
# (auto-wrapping) constructor. Containers come out *empty* in Phase 0.
const _UNIT_DOCUMENT = JsonNull   # minimal concrete stand-in for an abstract child field

function minimal(::Type{T}) where {T<:Document}
    try
        return T()                                  # all-defaulted fast path (incl. empty containers)
    catch
    end
    _has_icompanion(T) || return T()                # no companion → let the ctor error speak
    T((_minimal_field(ft) for ft in _declared_field_types(T))...)
end

function _minimal_field(@nospecialize ft)
    ft === Any && return nothing
    if ft isa Union                                  # prefer a buildable non-Nothing member
        for m in Base.uniontypes(ft)
            m === Nothing && continue
            v = try _minimal_field(m) catch; missing end
            v === missing || return v
        end
        return nothing
    end
    ft isa Type || return nothing
    ft <: Bool           && return false             # (Bool <: Integer, so test it first)
    ft <: Integer        && return 0
    ft <: Real           && return 0
    ft <: AbstractString && return ""
    ft <: CellVector     && return CellVector()       # empty container (Phase 0)
    Nothing <: ft        && return nothing            # e.g. `selection::Reference`
    ft <: Document       && return minimal(isconcretetype(ft) ? ft : _UNIT_DOCUMENT)
    try ft() catch; nothing end
end

# ── Projection graph: edges = runnable whole-tree bridges (thunks for freshness) ──
# The only declared graph metadata — ~O(domains). Each is `RecursiveProjection`-wrapped
# so it is independently runnable via `print_document(bridge, doc)` (mirrors the proven
# `_JSON_TO_TEXT` chains in WorkbenchAssistant.jl). The graphics bridge is deferred:
# `TextToGraphics` needs a native `measure` function.
const BRIDGES = Function[
    () -> RecursiveProjection(JsonToSyntax()),
    () -> RecursiveProjection(XmlToSyntax()),
    () -> RecursiveProjection(YamlToSyntax()),
    () -> RecursiveProjection(JuliaToSyntax()),
    () -> RecursiveProjection(MarkdownToSyntax()),
    () -> RecursiveProjection(SyntaxToText()),
]

# (input type, bridge index) → output instance | nothing. Bridges (esp. the slow ones)
# run at most once per input type. Output type depends only on input type.
const _STEP_CACHE = Dict{Tuple{DataType,Int},Any}()

# Run-and-inspect one edge: apply bridge `i` to `doc`; return the projected output, or
# `nothing` if it does not apply (any error) or is a no-op (same output type). No static
# domain table needed. Cheap: `doc` is minimal.
function _step(i::Int, doc)
    key = (typeof(doc), i)
    get!(_STEP_CACHE, key) do
        try
            o = _unwrap(print_document(BRIDGES[i](), doc).output)
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

# All-shortest-paths BFS from a minimal `start` to the first frontier where `reached(T)`
# holds. Returns each path as an ordered vector of bridge thunks (empty ⇒ already there).
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

"All minimal composite projections from a minimal `start` document to `reached`."
paths(start, reached) = [_compile(seq) for seq in path_sequences(start, reached)]

"One minimal composite projection from `start` to `reached`, or `nothing` if unreachable."
projection_to(start, reached) =
    (ss = path_sequences(start, reached); isempty(ss) ? nothing : _compile(ss[1]))

# ── Names & domain ────────────────────────────────────────────────────────────────
_snake(x) = lowercase(replace(String(nameof(x)), r"([a-z0-9])([A-Z])" => s"\1_\2"))
_domain(::Type{T}) where {T} = Symbol(lowercase(replace(String(nameof(parentmodule(T))), r"Module$" => "")))
catalog_domain(ex::Example) = _domain(typeof(ex.document))
runnable(ex::Example) = ex.terminal in (:text, :graphics)   # graphics→screen/web, text→console

# ── Generators ──────────────────────────────────────────────────────────────────
# Document umbrella types are cell-kind `UnionAll`s (`JsonNull = JsonNull{K} where K`),
# `<: Document` but NOT `DataType` — so we test `isa Type`, never `isa DataType`.
function _projectable_document_types()
    ts = Type[]
    for m in methods(print_document)
        length(m.sig.parameters) == 5 || continue               # (fn, p, recursion, doc, ctx)
        d = m.sig.parameters[4]
        d isa Type && d <: Document && d !== Document && d ∉ ts && push!(ts, d)
    end
    ts
end

_atomic_example(docT, projT, term) =
    Example("$(_snake(docT)) · $(_snake(projT))", () -> minimal(docT), () -> projT(); terminal = term)

# A. Discovered atomic stage pairs — leaf documents only (a node stage needs a
#    `recursion` arg; those are left to reachability + AtomicFixture). Fast; feeds the
#    domain-agnostic testers (printer/reader/repl).
function discover_atomic_pairs()
    examples = Example[]
    seen = Set{Tuple{Type,Type}}()
    for m in methods(print_document)
        length(m.sig.parameters) == 5 || continue
        projT = m.sig.parameters[2]; docT = m.sig.parameters[4]
        (projT isa Type && docT isa Type) || continue
        (docT <: Document && docT !== Document)       || continue   # cell-kind umbrella (UnionAll)
        (projT <: Projection && projT !== Projection) || continue
        (docT, projT) in seen && continue; push!(seen, (docT, projT))
        (_has_icompanion(docT) && is_leaf_document(docT)) || continue
        local doc, proj
        try doc = minimal(docT); proj = projT() catch; continue end   # zero-arg stages only
        term = try _terminal_of(typeof(_unwrap(print_document(proj, doc).output))) catch; :abstract end
        push!(examples, _atomic_example(docT, projT, term))
    end
    examples
end

_reach_example(docT, seq, term, name) =
    Example(name, () -> minimal(docT), () -> _compile(seq); terminal = term)

# B. Reachability cases — for each projectable document type, the minimal composite
#    projection(s) that reach a target domain a test/example needs. `:text` only for now
#    (graphics bridge deferred).
function reachability_examples()
    examples = Example[]
    for docT in _projectable_document_types()
        _has_icompanion(docT) || continue
        local start
        try start = minimal(docT) catch; continue end
        for (reached, term) in ((is_text, :text),)
            seqs = try path_sequences(start, reached) catch; Vector{Function}[] end
            seqs = filter(!isempty, seqs)                        # drop the "already in domain" empties
            for (k, seq) in enumerate(seqs)
                name = length(seqs) == 1 ? "$(_snake(docT)) → $(term)" : "$(_snake(docT)) → $(term) #$k"
                push!(examples, _reach_example(docT, seq, term, name))
            end
        end
    end
    examples
end

"""
    catalog(; domain=nothing, terminal=nothing, only_runnable=false) -> Vector{Example}

The generated catalog: discovered atomic stage pairs plus reachability (composite)
pairs, filterable by document `domain`, projection `terminal`, or `only_runnable`.
Every entry is a plain `Example`, so it feeds `test_printer`/`run_example` unchanged.
"""
function catalog(; domain = nothing, terminal = nothing, only_runnable = false)
    cs = Example[discover_atomic_pairs(); reachability_examples()]
    domain   === nothing || (cs = filter(c -> catalog_domain(c) === domain, cs))
    terminal === nothing || (cs = filter(c -> c.terminal === terminal, cs))
    only_runnable && (cs = filter(runnable, cs))
    cs
end
