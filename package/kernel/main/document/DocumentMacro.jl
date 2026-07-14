# Fragment of `DocumentModule` — the `@document` codegen: the macro that turns a
# field list into a kind-parameterized document type, its constructors, its
# transparent accessors, and its kind aliases. Builds on the transparent-Cell
# struct codegen from the cell layer (`cell_struct_kw_params`,
# `cell_struct_kwctor`) imported at the module head.

"""
    @document struct T [<: Super] ... end

Annotate a Document struct whose fields are transparent cells. The programmer
writes real value types.

Every document gets a **`selection::Reference = nothing`** field, appended as its
last field by the macro — the programmer never writes it, and declaring it by hand
is an **error**. `Reference` is a `ReferencePath` (what is selected inside this
node) or `nothing` (nothing selected). Julia has no field inheritance, so the field
must exist on every struct; making it the macro's job is what keeps it from being
repeated on all of them. It is appended last and always defaulted, so it falls
inside Rule Y's trailing run and a document's own fields keep the positional arity
they would have had without it.

A type that is *not* addressable content — a reference step, a clock, anything
that is never navigated into, selected inside, or projected — should not be a
document at all: declare it with [`@cell_struct`](@ref), which gives the same
transparent-cell fields with none of the document codegen.

From the declared fields the macro generates the **kind-parameterized stem**:

1. **Immutable parametric struct** (same name) — one cell type-parameter per
   field (`Foo{C1<:AbstractCell, …}`), so the *cell kind* in the fields decides
   the behavior: reactive, mutable, or immutable. Bounds are deliberately loose
   (`<: AbstractCell`, not `<: AbstractCell{T}`): `AbstractCell{T}` is invariant,
   and machinery freely creates untyped `Cell(x)` cells stored in typed fields,
   which strict bounds would reject. Declared field types are enforced by the
   kind ctors, not the type system. `getproperty`/`setproperty!` read/write
   through the cells uniformly for every kind.

2. **Auto-wrapping constructor** (bare name) — `Foo(args…)` accepts raw values
   or cells; a raw value is wrapped in `ReactiveCell{Any}` (exactly the historic
   `Cell`), so the bare name builds the **reactive kind** with unchanged
   semantics. Passing cells (of any kind, even mixed) stores them as-is.

3. **Kind aliases** — `RFoo` (all fields `ReactiveCell{Any}`, what the bare ctor
   builds), `IFoo` (`ImmutableCell{declared-type}`), `MFoo`
   (`MutableCell{declared-type}`), plus value-accepting ctors `IFoo(args…)` /
   `MFoo(args…)` that wrap raw values in their kind's typed cells. Convert a
   whole subtree between kinds with [`copy_document`](@ref)`(K, doc)`.

Fields may carry `@kwdef`-style defaults (`field::T = value`). The injected
`selection` is always one, so Rule Y and Rule C below always apply; the keyword
constructors are the exception and need a default you declared yourself.

4. **Keyword constructors** for `Foo`, `IFoo` and `MFoo` — fields with a default
   are optional keywords, fields without one are required keywords. Emitted only
   when **you** declared ≥1 default (the injected `selection` does not count), or
   when the struct declares no fields at all. A keyword constructor is
   zero-*positional*, so it claims the `Foo(; …)` signature: gating it this way
   leaves that signature to a struct that must hand-write one because it does more
   than fill fields (`WorkbenchAssistant` back-links its draft;
   `DatabaseCredentials` coerces its arguments). Declare a default on any field to
   opt in.

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
construction-time cell sharing replaces field-level retargeting.
"""
macro document(structdef)
    structdef.head === :struct || error("@document expects a struct definition")
    # Default the supertype to `Document` unless one is written explicitly, so
    # `@document struct Foo … end` means `struct Foo <: Document … end`. Any
    # explicit `<: SomeSuper` always wins. The injected `:Document` resolves in
    # the caller's scope (the result is `esc`'d).
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

    # ── Inject the selection field ────────────────────────────────────────────
    # Every document carries a selection — a `Reference` (a `ReferencePath`, or
    # `nothing` for no selection) naming what is selected *inside* that node.
    # Julia has no field inheritance, so the field has to be materialized on
    # every struct; the macro writes it so the programmer never repeats it.
    #
    # Appended **last**, and always defaulted, so it lands in the trailing run of
    # defaulted fields that Rule Y fills — a document's own fields keep the
    # positional arity they would have had without it.
    #
    # `Reference` is emitted as a **bare symbol**, not a spliced type object: it
    # is defined in the reference layer (layer 3), *above* this one (layer 2), so
    # this module cannot name the type. The expansion is `esc`'d, so the symbol
    # resolves in the caller's module — where it is always in scope, since a
    # module that declares documents necessarily uses the reference layer.
    # (`@cell_struct` emits its `Cell` type the same way, for the same reason.)
    #
    # The injected field is *not* a programmer default: it must not, by itself,
    # manufacture keyword constructors a struct never had. A struct whose fields
    # all lack defaults gets no `Foo(; …)` — leaving a hand-written keyword
    # constructor (one that needs to do more than fill fields, e.g. establish a
    # back-link) free to own that signature. Rule Y and Rule C *do* count it, since
    # filling a trailing default positionally is exactly their job — and that is
    # what retires the `Foo(a, b) = Foo(a, b, nothing)` boilerplate.
    #
    # Declaring it by hand is an error, not an override: a hand-written
    # `selection::Reference` (no default) is what used to suppress the keyword
    # constructors, and that workaround is precisely the bug this injection removes.
    any(f -> f[1] === :selection, original_fields) &&
        error("@document $(struct_name): `selection` is injected automatically — " *
              "remove the explicit field. A type that should not carry a selection " *
              "is not a document: declare it with `@cell_struct`.")
    programmer_defaults = length(defaults)
    declared_fields = length(cell_fields)
    push!(cell_fields, :selection)
    push!(original_fields, (:selection, :Reference))
    push!(defaults, :selection => :nothing)
    push!(body.args, :(selection::$(Symbol("C", length(cell_fields)))))

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
    # bare name keeps the untyped-cell semantics (bare `nothing` defaults and
    # shared wider-typed cells keep working). Cells pass through, which is how
    # the kind ctors and `copy_document` construct every other kind. Hand-written
    # convenience ctors stay outer and call `Foo(values…)` as before.
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

    # ── Keyword constructors (only when the *programmer* declared ≥1 default) ──
    # Forward into the positional ctors of the bare `Foo` and the typed kind
    # ctors `IFoo`/`MFoo`, so defaults are available on any kind. Fields without
    # a default become required keywords, à la `Base.@kwdef`.
    #
    # Gated on `programmer_defaults`, not on the injected `selection`: a keyword
    # constructor is zero-*positional*, so an auto-generated one would claim the
    # `Foo(; …)` signature and collide with any hand-written keyword constructor.
    # Structs that need one to do real work beyond filling fields (`WorkbenchAssistant`
    # back-links its draft; `WindowDocument` used to coerce its arguments) declare no
    # defaults, and so keep that signature to themselves. Declare a default on any
    # field to opt into the generated keyword constructors.
    #
    # A struct with no fields of its own (`JsonNull`, and every `@domain` placeholder)
    # is the exception: it holds nothing but its selection, so there is no
    # hand-written keyword constructor to protect and `Foo()` must come from
    # somewhere — Rule Y cannot supply it (`req == 0`).
    extra = Any[]
    if !isempty(defaults)
        default_map = Dict(defaults)
        kw_params = cell_struct_kw_params(field_names, default_map)
        if programmer_defaults > 0 || declared_fields == 0
            push!(extra, cell_struct_kwctor(struct_name, field_names, kw_params))
            push!(extra, cell_struct_kwctor(i_name, field_names, kw_params))
            push!(extra, cell_struct_kwctor(m_name, field_names, kw_params))
        end

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
