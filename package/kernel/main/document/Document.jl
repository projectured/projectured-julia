# Fragment of `DocumentModule` — the shared machinery every concrete document
# reuses: the generic `Base.show`, the `@document` macro, and the value
# protocol (`copy_document`, `sync_document!`). The `@forward*` family lives
# in the sibling `Forward.jl` fragment. The `Document` abstract type comes
# from `Interface.jl`, which `DocumentModule.jl` includes first so it is
# already in scope here. `@document` generates its own kind-parameterized stem
# below; the generic transparent-Cell struct codegen it builds on
# (`cell_struct_kw_params`, `cell_struct_kwctor`, `@cell_struct`) lives in the
# cell layer — see `cell/CellStruct.jl`.

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
nested documents do not explode. The `selection` field, present on every
document, is omitted as noise.

This is a generic debug aid only. The *semantic* rendering of a document
(source syntax, etc.) is produced by the projection pipeline, not by `show`.
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

"""
    @document struct T [<: Super] ... end

Annotate a Document struct whose fields are transparent cells. The programmer
writes real value types; the macro generates the **kind-parameterized stem**
(see plan/pending/cell-kind-documents.md):

1. **Immutable parametric struct** (same name) — one cell type-parameter per
   field (`Foo{C1<:AbstractCell, …}`), so the *cell kind* in the fields decides
   the behavior: reactive, mutable, or immutable. Bounds are deliberately loose
   (`<: AbstractCell`, not `<: AbstractCell{T}`): `AbstractCell{T}` is invariant,
   and machinery freely creates untyped `Cell(x)` cells (deferred selection
   cells, `bound(…)` template markers stored in typed fields), which strict
   bounds would reject. Declared field types are enforced by the kind ctors, not
   the type system. `getproperty`/`setproperty!` read/write through the cells
   uniformly for every kind.

2. **Auto-wrapping constructor** (bare name) — `Foo(args…)` accepts raw values
   or cells; a raw value is wrapped in `ReactiveCell{Any}` (exactly the historic
   `Cell`), so the bare name builds the **reactive kind** with unchanged
   semantics. Passing cells (of any kind, even mixed) stores them as-is.

3. **Kind aliases** — `RFoo` (all fields `ReactiveCell{Any}`, what the bare ctor
   builds), `IFoo` (`ImmutableCell{declared-type}`), `MFoo`
   (`MutableCell{declared-type}`), plus value-accepting ctors `IFoo(args…)` /
   `MFoo(args…)` that wrap raw values in their kind's typed cells. Convert a
   whole subtree between kinds with [`copy_document`](@ref)`(K, doc)`.

Fields may carry `@kwdef`-style defaults (`field::T = value`). When at least one
default is present, the macro also generates:

4. **Keyword constructors** for `Foo`, `IFoo` and `MFoo` — fields with a default
   are optional keywords, fields without one are required keywords.

5. **Positional default constructors** (Rule Y, bare name only) — the positional
   analog of `@kwdef`: for a trailing run of defaulted fields, ctors `Foo(f₁..f_k)`
   that fill the omitted suffix with its defaults. Emitted only when ≥1 leading
   field is required (so the zero-arg form never shadows the keyword ctor);
   fully-defaulted structs get none.

6. **Single-`CellVector` constructors** (Rule C, bare name only) — when exactly
   one field is a `CellVector`, a positional ctor accepts that slot as an
   `AbstractVector` and wraps it per-element via `CellVector(items)`, filling any
   trailing defaults. This holds whether the sibling fields are **required**
   (`Foo(callee, [args])`) or all default (`Foo([a, b])`, plus the variadic
   `Foo(a, b)` when the collection is the sole content). Elements are typed
   `Document` (the universal base), so a collection may hold children of any
   domain, even a mix of domains.

Since the stem is immutable, a node's field *cells* can never be swapped after
construction (`setfield!` is gone); all mutation flows through the cells, and
construction-time cell sharing replaces retargeting (see ProjectionTemplate's
`_with_selection`).
"""
macro document(structdef)
    structdef.head === :struct || error("@document expects a struct definition")
    # Default the supertype to `Document` unless one is written explicitly, so
    # `@document struct Foo … end` means `struct Foo <: Document … end`. A domain
    # abstract supertype (`<: JsonDocument`, …) or any explicit `<: …` always
    # wins. The injected `:Document` resolves in the caller's scope (the result
    # is `esc`'d) — same mechanic as `@iomap`/`IoMap`.
    name_expr = structdef.args[2]
    if !(name_expr isa Expr && name_expr.head === :(<:))
        name_expr = Expr(:(<:), name_expr, :Document)
        structdef.args[2] = name_expr
    end
    struct_name = name_expr.args[1]
    supertype_expr = name_expr.args[2]
    body = structdef.args[3]

    # ── Collect original field info; retype each field with its own parameter ──
    original_fields = Tuple{Symbol, Any}[]  # (name, original_type_or_nothing)
    cell_fields = Symbol[]
    defaults = Pair{Symbol, Any}[]  # field => default-value expr (declaration order)
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            push!(original_fields, (ex, nothing))
            body.args[i] = :($(ex)::$(Symbol("C", length(cell_fields))))
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            push!(original_fields, (ex.args[1], ex.args[2]))
            ex.args[2] = Symbol("C", length(cell_fields))
        elseif ex isa Expr && ex.head === :(=) && length(ex.args) == 2
            # `name = v` / `name::T = v` — @kwdef-style default. Strip the default
            # out of the struct body and remember it for the keyword ctor; the
            # declared type still feeds the typed kind aliases and ctors.
            lhs = ex.args[1]
            if lhs isa Symbol
                fname, ftype = lhs, nothing
            else
                fname, ftype = lhs.args[1], lhs.args[2]
            end
            push!(cell_fields, fname)
            push!(original_fields, (fname, ftype))
            push!(defaults, fname => ex.args[2])
            body.args[i] = :($(fname)::$(Symbol("C", length(cell_fields))))
        end
    end
    isempty(cell_fields) && return esc(structdef)

    n = length(cell_fields)
    Cs = [Symbol("C", i) for i in 1:n]
    field_names = [f[1] for f in original_fields]
    # Declared value types as exprs (Any when untyped); resolve in caller scope.
    Tvals = Any[t === nothing ? :Any : t for (_, t) in original_fields]

    # Parametric header: `Foo{C1<:AbstractCell, …} <: Super`. The cell types are
    # spliced as *objects* (not names), so callers need no extra imports.
    structdef.args[2] = Expr(:(<:),
        Expr(:curly, struct_name, [Expr(:(<:), C, AbstractCell) for C in Cs]...),
        supertype_expr)

    # ── Auto-wrapping inner constructor (the ONLY inner constructor) ──────────
    # Raw values wrap in `ReactiveCell{Any}` — the historic untyped `Cell`, so the
    # bare name keeps today's semantics exactly (template markers, `nothing`
    # defaults, shared wider-typed cells all keep working). Cells pass through,
    # which is also how the kind ctors and `copy_document` construct every other
    # kind. Hand-written convenience ctors stay outer and call `Foo(values…)` as
    # before.
    #
    # `new{…}` needs the cell types as parameters; computing them via `typeof` is
    # a runtime `apply_type` per construction (~2.5× build cost, measured on the
    # JSON bench). Two fast paths with *constant* parameters cover the dominant
    # cases: all args already `ReactiveCell{Any}` (machinery reconstruction,
    # cell-sharing ctors, same-kind `copy_document`) and no arg a cell at all
    # (parsers, bulk building). Only genuinely mixed/typed-cell construction
    # (kind ctors, `copy_document(K, …)`) pays the generic path.
    arg_names = [gensym(f) for f in field_names]
    rc_any = fill(ReactiveCell{Any}, n)
    all_rc  = mapreduce(a -> :($a isa $(ReactiveCell{Any})), (x, y) -> :($x && $y), arg_names)
    any_cell = mapreduce(a -> :($a isa $(AbstractCell)), (x, y) -> :($x || $y), arg_names)
    wrap_stmts = Any[]
    wrapped = Symbol[]
    for (i, a) in enumerate(arg_names)
        w = gensym(field_names[i])
        push!(wrapped, w)
        push!(wrap_stmts, :($w = $a isa $(AbstractCell) ? $a : $(ReactiveCell{Any})($a)))
    end
    push!(body.args, :(function $(struct_name)($(arg_names...))
        if $all_rc
            return $(Expr(:call, Expr(:curly, :new, rc_any...), arg_names...))
        elseif !($any_cell)
            return $(Expr(:call, Expr(:curly, :new, rc_any...),
                          [:($(ReactiveCell{Any})($a)) for a in arg_names]...))
        end
        $(wrap_stmts...)
        $(Expr(:call, Expr(:curly, :new, [:(typeof($w)) for w in wrapped]...), wrapped...))
    end))

    # ── Uniform accessors: kind dispatch happens in the cell ──────────────────
    getprop = :(Base.getproperty(obj::$(struct_name), name::Symbol) = getfield(obj, name)[])
    setprop = :(Base.setproperty!(obj::$(struct_name), name::Symbol, val) =
        (getfield(obj, name)[] = val))

    # ── Kind aliases + typed kind ctors ───────────────────────────────────────
    r_name, i_name, m_name = (Symbol(p, struct_name) for p in ("R", "I", "M"))
    r_alias = Expr(:const, Expr(:(=), r_name,
        Expr(:curly, struct_name, fill(ReactiveCell{Any}, n)...)))
    i_alias = Expr(:const, Expr(:(=), i_name,
        Expr(:curly, struct_name, [Expr(:curly, ImmutableCell, T) for T in Tvals]...)))
    m_alias = Expr(:const, Expr(:(=), m_name,
        Expr(:curly, struct_name, [Expr(:curly, MutableCell, T) for T in Tvals]...)))

    kind_ctor(kname, K) = :($(kname)($(arg_names...)) =
        $(Expr(:call, struct_name,
            [:($a isa $(AbstractCell) ? $a : $(Expr(:curly, K, Tvals[i]))($a))
             for (i, a) in enumerate(arg_names)]...)))
    i_ctor = kind_ctor(i_name, ImmutableCell)
    m_ctor = kind_ctor(m_name, MutableCell)

    # Declared value types, for `copy_document(K, …)`'s typed I/M targets. The
    # method is added through the function object's singleton type — a spliced
    # object is not a valid method-definition *name*, but `(::typeof(f))(…)` is.
    dvt = :((::typeof($(_declared_value_types)))(::Type{<:$(struct_name)}) = ($(Tvals...),))

    # ── Keyword constructors (only when ≥1 default is declared) ────────
    # Forward into the positional ctors of the bare `Foo` and the typed kind
    # ctors `IFoo`/`MFoo`, so defaults are available on any kind. Fields without
    # a default become required keywords, à la `Base.@kwdef`.
    extra = Any[]
    if !isempty(defaults)
        default_map = Dict(defaults)
        kw_params = cell_struct_kw_params(field_names, default_map)
        push!(extra, cell_struct_kwctor(struct_name, field_names, kw_params))
        push!(extra, cell_struct_kwctor(i_name, field_names, kw_params))
        push!(extra, cell_struct_kwctor(m_name, field_names, kw_params))

        # ── Rule Y: positional ctors that omit a trailing run of defaulted
        #    fields (the positional analog of `@kwdef`). Generated only when at
        #    least one leading field is required (`req ≥ 1`), so we never emit a
        #    zero-arg form colliding with the keyword ctor's `Foo()`; fully
        #    defaulted structs are left to their keyword / hand-written ctors.
        #    Bare (reactive) name only — the kind aliases keep full-arity + kw. ──
        trailing = 0
        for (fname, _) in Iterators.reverse(original_fields)
            haskey(default_map, fname) || break
            trailing += 1
        end
        req = n - trailing

        # Position of the sole `CellVector` field (0 if there isn't exactly one).
        # When a positional ctor's kept prefix includes it, Rule Y passes that slot
        # *raw* — but the auto-wrapping inner ctor would then store `Cell(vector)`
        # (a Cell wrapping a plain Vector) instead of a `CellVector`. So alongside
        # the raw form we emit a variant whose CellVector slot is typed
        # `::AbstractVector` and wrapped via `CellVector(...)` — Rule C, generalized
        # to non-defaulted siblings (`Foo(callee, [args])`). The two coexist: the
        # `::AbstractVector` variant is more specific for a `Vector` arg, while a
        # real `CellVector` (which is `<: Document`, not `<: AbstractVector`) falls
        # through to the raw form. Element type is `Document` (the universal base),
        # so a collection may hold children of any domain.
        cv_fields = [fname for (fname, ftype) in original_fields if ftype === :CellVector]
        p = length(cv_fields) == 1 ? findfirst(==(cv_fields[1]), field_names) : 0

        if req ≥ 1
            for k in req:(n-1)
                kept   = field_names[1:k]
                filled = Any[default_map[field_names[j]] for j in (k+1):n]
                push!(extra, :($(struct_name)($(kept...)) =
                    $(Expr(:call, struct_name, kept..., filled...))))
                if 1 ≤ p ≤ k                       # kept prefix contains the CellVector
                    params   = Any[j == p ? :($(field_names[p])::AbstractVector) : field_names[j] for j in 1:k]
                    callargs = Any[j == p ? :(CellVector($(field_names[p])))     : field_names[j] for j in 1:k]
                    push!(extra, :($(struct_name)($(params...)) =
                        $(Expr(:call, struct_name, callargs..., filled...))))
                end
            end
        end

        # ── Rule C tail: element-accepting sugar for a struct backed by exactly
        #    one `CellVector` whose every *other* field defaults. The bracketed
        #    `Foo(items::AbstractVector)` "fill everything" form is only needed when
        #    Rule Y did not run (`req == 0`, i.e. the CellVector itself defaults) —
        #    otherwise the loop above already emitted the arity-`k` bracketed ctor.
        #    The variadic `Foo(a, b, c)` sugar never collides, so it is always
        #    emitted here. Both are Cell-based `Foo` only. `AbstractVector` (not
        #    `Vector`) stays less specific than any hand-written `Foo(::Vector{…})`;
        #    `Document...` doesn't clash with typed-variadic sugar like
        #    `Foo(::Pair...)` and loses to a more specific `Foo(::SomeDoc...)`.
        if p ≥ 1 &&
           all(haskey(default_map, f) for (f, ft) in original_fields if ft !== :CellVector)
            cvf = field_names[p]
            if req == 0
                cargs = Any[f === cvf ? :(CellVector(items)) : default_map[f] for f in field_names]
                push!(extra, :($(struct_name)(items::AbstractVector) =
                    $(Expr(:call, struct_name, cargs...))))
            end
            push!(extra, :($(struct_name)(items::Document...) =
                $(struct_name)(collect(items))))
        end
    end

    # The stem and its kind aliases are all generated API, so the macro exports
    # them itself. A module re-exporting any of these names explicitly (e.g. the
    # bare name in a domain's `export` line) is a harmless duplicate.
    type_exports = Expr(:export, struct_name, r_name, i_name, m_name)

    # The stem stays an **immutable** struct: all mutation flows through the
    # cells (`setproperty!` writes cell *contents*); a field's cell object can
    # never be swapped after construction — sharing is established at
    # construction time instead.
    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop,
                     r_alias, i_alias, m_alias, type_exports,
                     i_ctor, m_ctor, dvt, extra...))
end

# ── Deep copy of document subtrees ─────────────────────────────────────────
# The Julia counterpart of Lisp's `deep-copy`, for anywhere a document subtree
# must be cloned independently of the original (copy/paste, version snapshots,
# a mutable-kind rebuild for a simulator, an immutable-kind snapshot for
# serialization, …). Unlike `Base.deepcopy` it understands the `@document`
# Cell-wrapped field convention, allocates **fresh** `Cell`s so the copy is
# independent of the original's reactive graph, and offers a two-arity surface:
#
#   copy_document(doc)     -> Document              # preserve every cell's kind
#   copy_document(K, doc)  -> Document              # rebuild every cell as kind K
#
# Both keep the source's selection; call `clear_selection!(copy)` afterward if
# a fresh cursor is required (the clipboard/version-snapshot pattern). The
# walk is generic over structure — struct fields (`fieldnames`), Vector
# elements, and per-slot cells inside a Vector are all traversed uniformly —
# so no concrete document type needs its own override.

"""
    copy_document(value)                     -> value
    copy_document(v::AbstractVector)         -> Vector
    copy_document(c::AbstractCell)           -> AbstractCell
    copy_document(doc::Document)             -> Document

Deep-copy `value`, allocating fresh `Cell`s and fresh containers so the result
shares no mutable state with the source. Cell kinds are preserved: each field
cell in a `@document` node is cloned as the same kind, and per-slot cells
inside a Vector are cloned as the same kind. Plain immutable leaves (strings,
numbers, symbols, reference paths) pass through unchanged. The source's
selection is kept — callers that want a reset call
[`clear_selection!`](@ref) on the returned document.
"""
copy_document(value) = value

# Vector: struct-with-integer-fields. Recurse per element; a `Vector{Cell}`'s
# slot cells dispatch to the `AbstractCell` method and are cloned per-slot, so
# the caller-visible shape (per-slot cells vs. plain values) is preserved.
copy_document(v::AbstractVector) = [copy_document(x) for x in v]

# Cell: fresh cell of the same kind + declared value type, holding the copied
# inner value. Used by the Vector walk for slot cells; the Document walk
# handles struct-field cells directly so it can consult declared field types.
copy_document(c::AbstractCell) = _same_cell(c, copy_document(c[]))

function copy_document(doc::Document)
    T = typeof(doc)
    base = Base.typename(T).wrapper   # the UnionAll: its ctor accepts cells/values
    args = Any[]
    for nm in fieldnames(T)
        raw = getfield(doc, nm)
        if raw isa AbstractCell
            push!(args, _same_cell(raw, copy_document(raw[])))
        else
            push!(args, copy_document(raw))
        end
    end
    base(args...)
end

"""
    copy_document(K, value)                  -> value
    copy_document(K, v::AbstractVector)      -> Vector
    copy_document(K, c::AbstractCell)        -> K{…}
    copy_document(K, doc::Document)          -> Document

The kind-converting variant. Every cell in the copy is rebuilt as kind `K`
(`ReactiveCell` / `MutableCell` / `ImmutableCell`). Cell value types: the
reactive target uses `Any` (parity with the historic untyped `Cell`); the
mutable/immutable targets use each field's **declared** type when the value
conforms — so a fully-conforming node inhabits the `MFoo`/`IFoo` alias — and
fall back to the value's own type otherwise. The fallback is load-bearing:
the reactive kind stores every field as `Any`, so a nominally `StyleColor`
field may actually hold `nothing`; a typed `ImmutableCell{StyleColor}(nothing)`
would be unconstructable, so that field lands on `ImmutableCell{Nothing}`
instead (still type-stable, just off the alias). The source's selection is
kept.
"""
copy_document(::Type{<:AbstractCell}, value) = value

copy_document(K::Type{<:AbstractCell}, v::AbstractVector) =
    [copy_document(K, x) for x in v]

function copy_document(K::Type{<:AbstractCell}, c::AbstractCell)
    v = copy_document(K, c[])
    Tv = K === ReactiveCell ? Any : typeof(v)
    K{Tv}(v)
end

function copy_document(K::Type{<:AbstractCell}, doc::Document)
    T = typeof(doc)
    base = Base.typename(T).wrapper
    Ts = _declared_value_types(base)
    args = Any[]
    for (i, nm) in enumerate(fieldnames(T))
        raw = getfield(doc, nm)
        if raw isa AbstractCell
            v = copy_document(K, raw[])
            Tv = _kinded_value_type(K, Ts, i, v)
            push!(args, K{Tv}(v))
        else
            push!(args, copy_document(K, raw))
        end
    end
    base(args...)
end

# A fresh cell of the same kind and value type as `c`, holding `v`.
_same_cell(c::AbstractCell{T}, v) where {T} = _cell_kind_of(typeof(c)){T}(v)

_cell_kind_of(::Type{<:ReactiveCell})  = ReactiveCell
_cell_kind_of(::Type{<:MutableCell})   = MutableCell
_cell_kind_of(::Type{<:ImmutableCell}) = ImmutableCell

# Read a document's cell kind off its first Cell-backed field. Used internally
# by `sync_document!` to pick the right target kind for elements it rebuilds
# on the shadow side; hand-written documents with plain fields report
# `nothing`.
function _document_cell_kind(doc::Document)
    isempty(fieldnames(typeof(doc))) && return nothing
    c = getfield(doc, 1)
    c isa AbstractCell ? _cell_kind_of(typeof(c)) : nothing
end

# Declared field value types of a `@document` type, emitted by the macro; the
# fallback covers hand-written documents (the kind-variant then falls back to
# each source cell's own value type).
_declared_value_types(::Type) = nothing

# The value type for a kinded field cell: `Any` for the reactive kind (parity
# with the untyped `Cell`); otherwise the declared type when `v` conforms,
# else `v`'s own concrete type.
function _kinded_value_type(::Type{K}, Ts, i, v) where {K<:AbstractCell}
    K === ReactiveCell && return Any
    Ts === nothing && return typeof(v)
    Td = Ts[i]
    v isa Td ? Td : typeof(v)
end

_value_type(::AbstractCell{T}) where {T} = T

# ── Shadow sync ────────────────────────────────────────────────────────────
# The double-buffer pattern (plan/pending/cell-kind-documents.md, Phase 7): a
# simulator mutates a MutableCell-kind document freely (zero reactive overhead
# per event, no observable intermediate states), then at a pause point
# `sync_document!` diff-copies it into a shadow tree that feeds the projection
# pipeline. The two trees have the same field-for-field shape (generated from
# one `@document` declaration), which is what lets the sync be one generic walk.

# Same document type ignoring cell kind (compare the UnionAll wrappers).
_same_wrapper(a, b) = Base.typename(typeof(a)).wrapper === Base.typename(typeof(b)).wrapper

"""
    sync_document!(shadow, source) -> shadow

Update the writable `shadow` document to match `source`, writing a shadow
cell **only when its value changed** — so the downstream graph sees a
*minimal* invalidation set, not a wholesale rebuild. `shadow` may be any
writable kind (`ReactiveCell` or `MutableCell`); `source` may be any kind.
Recurses structurally: a child document is synced in place when it is the
same type, else replaced by a fresh copy in the shadow's kind; a leaf field
is written only on `!isequal`. `CollectionModule` adds the `CellVector`
element reconciler.

The result is a consistent view of `source` after each sync; between syncs
the source is unobserved and pays nothing for observation.
"""
function sync_document!(shadow::Document, source::Document)
    _same_wrapper(shadow, source) ||
        error("sync_document!: type mismatch, $(typeof(shadow)) vs $(typeof(source))")
    K = _document_cell_kind(shadow)
    for nm in fieldnames(typeof(source))
        sv  = getproperty(source, nm)
        cur = getproperty(shadow, nm)
        if sv isa Document
            if cur isa Document && _same_wrapper(cur, sv)
                sync_document!(cur, sv)                       # recurse in place
            else
                setproperty!(shadow, nm, copy_document(K, sv)) # type changed ⇒ rebuild in shadow's kind
            end
        else
            isequal(cur, sv) || setproperty!(shadow, nm, sv)   # leaf: write iff changed
        end
    end
    shadow
end

# A source element rebuilt for the shadow's kind (a document is copied in that
# kind; a plain value passes through). Shared by the CellVector reconciler.
_shadow_elem(K, x) = x isa Document ? copy_document(K, x) : x
