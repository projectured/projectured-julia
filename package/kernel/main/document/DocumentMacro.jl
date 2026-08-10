# Fragment of `DocumentModule` — the `@document` codegen.
#
# The macro is a parse followed by six emitters. It reads the struct definition
# into a `CellStructPlan` (the cell layer's shared parse), appends the `selection`
# field every document must carry, and then each emitter below is a pure function
# of that plan producing one piece of the expansion. Rule Y — positional
# constructors filling a trailing run of defaults — is not document-specific and
# lives with the other constructor builders in the cell layer.

# The reactive default a bare `Foo(…)` wraps a raw value in: the untyped `Cell`.
const _REACTIVE_ANY = ReactiveCell{Any}

# ── The layout list ───────────────────────────────────────────────────────────
# `@document [C, M] struct Foo … end` says which layouts the schema emits. A code
# names a layout and nothing else: `C` the cell layout, `M` the mutable native
# struct, `I` the immutable native struct. The family and the four spelling
# aliases are never listed — the family is what two layouts share, and an alias is
# a `const` whose absence would only surprise.
#
# The default is every layout that exists today, so a declaration that says
# nothing emits what it always did.
const _DEFAULT_LAYOUTS = (:C, :M)
const _KNOWN_LAYOUTS   = (:C, :M, :I)

"""
    _take_layout_list(args) -> (layouts::Tuple{Vararg{Symbol}}, rest)

Pull the layout list out of a `@document` argument list, wherever it sits, and
return it with the remaining arguments for [`cell_struct_macro_default`](@ref).
The canonical order writes the field-kind marker first
(`@document ImmutableCell [C] struct …`), but a list is recognised in any leading
position, so no spelling of it is rejected.
"""
function _take_layout_list(args)
    i = findfirst(a -> a isa Expr && a.head === :vect, args)
    i === nothing && return (_DEFAULT_LAYOUTS, args)
    codes = args[i].args
    all(c -> c isa Symbol, codes) ||
        error("@document: a layout list holds layout codes, one of $(join(_KNOWN_LAYOUTS, ", "))")
    for c in codes
        c in _KNOWN_LAYOUTS ||
            error("@document: `$c` is not a layout code. Use one of $(join(_KNOWN_LAYOUTS, ", ")).")
        c === :I &&
            error("@document: the immutable native layout `I` is not emitted yet, " *
                  "because nothing asks for one. Add it when a caller does.")
    end
    :C in codes ||
        error("@document: a layout list must include `C` for now. A schema with no cell " *
              "layout has no aliases, no auto-wrapping constructor and no shadow, and " *
              "nothing asks for one yet.")
    (Tuple(codes), args[[j for j in eachindex(args) if j != i]])
end

# The default cell TYPE a field wraps a raw value in, from its declared kind. Reactive
# keeps the untyped `ReactiveCell{Any}` (loose bound); immutable/mutable use
# the typed cell so it inlines — the same typed cells the `IFoo`/`MFoo` aliases build.
_default_cell_type(kind, vt) =
    kind === :immutable ? Expr(:curly, ImmutableCell, vt) :
    kind === :mutable   ? Expr(:curly, MutableCell,  vt) :
    _REACTIVE_ANY

# Per-field cell type parameters: `C1, C2, …`.
_cell_params(plan) = [Symbol("C", i) for i in 1:length(plan.field_names)]

"""
    _emit_stem!(plan) -> Expr

The kind-parameterized immutable struct: `Foo{C1<:AbstractCell, …} <: Super`, one
cell type-parameter per field. Rewrites the plan's body and header in place and
returns the struct definition.

Bounds are deliberately loose (`<: AbstractCell`, not `<: AbstractCell{T}`):
`AbstractCell{T}` is invariant, and machinery freely creates untyped `Cell(x)`
cells stored in typed fields, which strict bounds would reject. Declared field
types are enforced by the kind constructors, not the type system.
"""
function _emit_stem!(plan)
    Cs = _cell_params(plan)
    retype_cell_struct_fields!(plan, Cs)
    # The cell types are spliced as *objects* (not names), so callers need no
    # extra imports.
    plan.structdef.args[2] = Expr(:(<:),
        Expr(:curly, plan.name, [Expr(:(<:), C, AbstractCell) for C in Cs]...),
        plan.supertype)
    plan.structdef
end

"""
    _emit_autowrap_ctor(plan, arg_names) -> Expr

The auto-wrapping inner constructor — the **only** inner constructor. Raw values
wrap in `ReactiveCell{Any}` (the untyped `Cell`), so the bare name keeps
the untyped-cell semantics; cells of any kind pass through as-is, which is how the
kind constructors and `copy_document` build every other kind.

`new{…}` needs the cell types as parameters, and computing them via `typeof` is a
runtime `apply_type` per construction (~2.5× build cost, measured on the JSON
bench). Two fast paths with *constant* parameters cover the dominant cases: all
args already `ReactiveCell{Any}` (machinery reconstruction, cell-sharing ctors,
same-kind `copy_document`) and no arg a cell at all (parsers, bulk building). Only
genuinely mixed / typed-cell construction pays the generic path.
"""
function _emit_autowrap_ctor(plan, arg_names; default::Symbol = :reactive)
    n = length(plan.field_names)
    # Per-field default kind and value type. `def_types[i]` is the cell type a raw
    # value in field i defaults to; `default` is the struct-level default (from a
    # leading macro kind) for any field that does not name its own kind — the injected
    # `selection` field is such a field, so it follows `default` too. With no leading
    # kind (`default = :reactive`) and nothing annotated these are all `ReactiveCell{Any}`
    # and every path below reduces to the plain untyped-cell codegen.
    kinds     = cell_struct_field_kinds(plan; default = default)
    vts       = cell_struct_value_types(plan)
    def_types = Any[_default_cell_type(kinds[i], vts[i]) for i in 1:n]
    raw_wrap(i) = kinds[i] === :reactive ? :($(_REACTIVE_ANY)($(arg_names[i]))) :
                                           :($(def_types[i])($(arg_names[i])))
    rc_any   = fill(_REACTIVE_ANY, n)
    all_rc   = mapreduce(a -> :($a isa $(_REACTIVE_ANY)), (x, y) -> :($x && $y), arg_names)
    any_cell = mapreduce(a -> :($a isa $(AbstractCell)),   (x, y) -> :($x || $y), arg_names)
    wrapped    = [gensym(f) for f in plan.field_names]
    wrap_stmts = [:($(wrapped[i]) = $(arg_names[i]) isa $(AbstractCell) ?
                        $(arg_names[i]) : $(raw_wrap(i)))
                  for i in 1:n]
    :(function $(plan.name)($(arg_names...))
        if $all_rc
            return $(Expr(:call, Expr(:curly, :new, rc_any...), arg_names...))
        elseif !($any_cell)
            return $(Expr(:call, Expr(:curly, :new, def_types...),
                          [raw_wrap(i) for i in 1:n]...))
        end
        $(wrap_stmts...)
        $(Expr(:call, Expr(:curly, :new, [:(typeof($w)) for w in wrapped]...), wrapped...))
    end)
end

"""
    _emit_accessors(plan) -> (getprop, setprop)

Transparent property access. Uniform across every kind — which cell a field holds
decides the behaviour, so the accessors need no kind dispatch of their own.
"""
_emit_accessors(plan) = (
    :(Base.getproperty(obj::$(plan.name), name::Symbol) = getfield(obj, name)[]),
    :(Base.setproperty!(obj::$(plan.name), name::Symbol, val) =
        (getfield(obj, name)[] = val)),
)

"""
    _emit_kind_aliases(plan, arg_names) -> Vector

The kind aliases `RFoo` / `IFoo` / `MFoo` / `DFoo`, the value-accepting typed
constructors `IFoo(…)` / `MFoo(…)`, and the `_declared_value_types` method
`copy_document(K, …)` reads a field's declared type from.

`DFoo` is the concrete type the **bare** constructor builds (the per-field default
combination); `RFoo` / `IFoo` / `MFoo` wrap every field in one kind's *typed* cells,
so a fully-conforming node inhabits its alias.
"""
function _emit_kind_aliases(plan, arg_names; default::Symbol = :reactive)
    n     = length(plan.field_names)
    Tvals = cell_struct_value_types(plan)
    kinds = cell_struct_field_kinds(plan; default = default)
    r_name, i_name, m_name, d_name = (Symbol(p, plan.name) for p in ("R", "I", "M", "D"))

    alias(nm, params) = Expr(:const, Expr(:(=), nm, Expr(:curly, plan.name, params...)))
    # `DFoo` names the concrete **default combination** the bare `Foo(raw…)` ctor
    # builds — each field in its default kind (`ReactiveCell{Any}`, or the struct
    # default from a leading macro kind). For a value-document (immutable default,
    # `selection::ImmutableCell{Nothing}`) it is isbits, so `ImmutableCell{DFoo}`
    # inlines. `RFoo`/`IFoo`/`MFoo` instead force one kind across every field.
    aliases = [
        alias(r_name, fill(_REACTIVE_ANY, n)),
        alias(i_name, [Expr(:curly, ImmutableCell, T) for T in Tvals]),
        alias(m_name, [Expr(:curly, MutableCell,  T) for T in Tvals]),
        alias(d_name, [_default_cell_type(kinds[i], Tvals[i]) for i in 1:n]),
    ]

    kind_ctor(kname, K) = :($(kname)($(arg_names...)) =
        $(Expr(:call, plan.name,
            [:($a isa $(AbstractCell) ? $a : $(Expr(:curly, K, Tvals[i]))($a))
             for (i, a) in enumerate(arg_names)]...)))

    # The `_declared_value_types` method is added through the function object's
    # singleton type: a spliced object is not a valid method-definition *name*,
    # but `(::typeof(f))(…)` is.
    dvt = :((::typeof($(_declared_value_types)))(::Type{<:$(plan.name)}) = ($(Tvals...),))

    # The stem and its kind aliases are all generated API, so the macro exports
    # them itself. A module re-exporting any of these names explicitly (e.g. the
    # bare name in a domain's `export` line) is a harmless duplicate.
    [aliases...,
     Expr(:export, plan.name, r_name, i_name, m_name, d_name),
     kind_ctor(i_name, ImmutableCell),
     kind_ctor(m_name, MutableCell),
     dvt]
end

"""
    _emit_keyword_ctors(plan) -> Vector

Keyword constructors for `Foo`, `IFoo` and `MFoo` — fields with a default are
optional keywords, fields without one required, à la `Base.@kwdef`.

Gated on the **programmer** having declared ≥1 default (the injected `selection`
does not count), or on the struct declaring no fields at all. A keyword
constructor is zero-*positional*, so it claims the `Foo(; …)` signature: gating it
this way leaves that signature to a struct that must hand-write one because it
does more than fill fields (back-linking a draft, coercing its arguments). A
struct with no fields of its own is the exception — it holds nothing but its
selection, so there is no hand-written constructor to protect and `Foo()` must
come from somewhere, which Rule Y cannot supply (`cell_struct_required_count == 0`).
"""
function _emit_keyword_ctors(plan)
    (plan.n_programmer_defaults > 0 || plan.n_declared == 0) || return Any[]
    kw_params = cell_struct_kw_params(plan.field_names, plan.defaults)
    [cell_struct_kwctor(Symbol(p, plan.name), plan.field_names, kw_params)
     for p in ("", "I", "M")]
end

# The single collection field's position, or 0 when there is not exactly one. A
# field's declared type opts in through `is_collection_field_type(::Val{name})`,
# which the type registers from its own package — so this macro names no concrete
# collection type. See `_emit_collection_ctors`.
function _collection_slot(plan)
    hits = findall(t -> t isa Symbol && is_collection_field_type(Val(t)), plan.field_types)
    length(hits) == 1 ? hits[1] : 0
end

"""
    _emit_collection_ctor_at(plan, k) -> Vector

**Rule C**, the part that accompanies Rule Y: the arity-`k` constructor whose
collection slot is typed `::AbstractVector` and wrapped via that slot's declared
type.

Rule Y passes a kept collection slot through *raw*, and the auto-wrapping inner
constructor would then store `Cell(vector)` — a cell wrapping a plain `Vector` —
instead of the collection. Hence this companion. The two coexist: the
`::AbstractVector` variant is more specific for a `Vector` argument, while a real
collection value (a `Document`, not an `AbstractVector`) falls through to the raw
form. Emitted only for an arity whose kept prefix actually reaches the collection
slot; it is passed to `cell_struct_positional_ctors` as its `each_arity` hook,
which is what ties it to Rule Y's own `cell_struct_required_count ≥ 1` gate.
"""
function _emit_collection_ctor_at(plan, k)
    p = _collection_slot(plan)
    (1 ≤ p ≤ k) || return ()
    n = length(plan.field_names)
    fields, defaults = plan.field_names, plan.defaults
    filled   = Any[defaults[fields[j]] for j in (k + 1):n]
    params   = Any[j == p ? :($(fields[p])::AbstractVector)         : fields[j] for j in 1:k]
    callargs = Any[j == p ? :($(plan.field_types[p])($(fields[p]))) : fields[j] for j in 1:k]
    (:($(plan.name)($(params...)) = $(Expr(:call, plan.name, callargs..., filled...))),)
end

"""
    _emit_collection_ctors(plan) -> Vector

**Rule C**'s tail: the element sugar for a struct whose *every other* field
defaults — the bracketed `Foo([a, b])` and the variadic `Foo(a, b)`.

The bracketed "fill everything" form is emitted only when Rule Y did **not** run
(`cell_struct_required_count == 0`, i.e. the collection itself defaults); otherwise
[`_emit_collection_ctor_at`](@ref) already produced that exact signature alongside
the arity-`k` Rule Y form, and emitting it again would silently redefine it. The
variadic never collides, so it is always emitted. Elements are typed `Document`
(the universal base), so a collection may hold children of any domain, even a mix.

The collection field is identified by `is_collection_field_type(::Val{name})` on
its declared type's symbol, and wrapped by calling that same declared type — so a
collection type opts in from its own package and this macro names none.
"""
function _emit_collection_ctors(plan)
    p = _collection_slot(plan)
    p ≥ 1 || return Any[]
    fields, defaults = plan.field_names, plan.defaults
    # Element sugar applies only when every field *other than* the collection defaults.
    all(haskey(defaults, f) for (i, f) in enumerate(fields) if i != p) || return Any[]

    ctors = Any[]
    if cell_struct_required_count(plan) == 0
        cargs = Any[i == p ? :($(plan.field_types[p])(items)) : defaults[f]
                    for (i, f) in enumerate(fields)]
        push!(ctors, :($(plan.name)(items::AbstractVector) =
            $(Expr(:call, plan.name, cargs...))))
    end
    # `AbstractVector` (not `Vector`) stays less specific than any hand-written
    # `Foo(::Vector{…})`; `Document...` doesn't clash with typed-variadic sugar
    # like `Foo(::Pair...)` and loses to a more specific `Foo(::SomeDoc...)`.
    push!(ctors, :($(plan.name)(items::Document...) = $(plan.name)(collect(items))))
    ctors
end

"""
    _emit_native_mutable(plan, family, native) -> Expr

The **mutable-layout** struct: a real `mutable struct native <: family` whose
fields hold the declared **value** types *directly* — no `MutableCell` box — so an
all-mutable document (`MFoo`) is byte-for-byte a plain `mutable struct`
(`getproperty`/`setproperty!` are the default `getfield`/`setfield!`). The value
types resolve here exactly as they already do in the `IFoo` / `MFoo` aliases, so
this introduces no new forward reference.
"""
function _emit_native_mutable(plan, family, native)
    vts = cell_struct_value_types(plan)
    fields = Any[:($(plan.field_names[i])::$(vts[i])) for i in eachindex(plan.field_names)]
    Expr(:struct, true, Expr(:(<:), native, family), Expr(:block, fields...))
end

"""
    @document [Kind] [[layouts]] struct T [<: Super] ... end

Annotate a Document struct whose fields are transparent cells. The programmer
writes real value types.

An optional **layout list** says which layouts the schema emits: `C` the cell
layout, `M` the mutable native struct. A code names a layout and nothing else —
the family and the four spelling aliases are never listed, because the family is
what two layouts share and an alias is a `const` whose absence would only
surprise. The default emits both, so a declaration that says nothing emits what it
always did. The canonical order writes the field-kind marker first, as in
`@document ImmutableCell [C] struct …`.

A package that wants the same list on every schema declares it once with
[`@document_preset`](@ref) and writes the preset's name instead.

Every document gets a **`selection::Union{Nothing, Reference} = nothing`** field, appended as its
last field by the macro — the programmer never writes it, and declaring it by hand
is an **error**. The field type is `Union{Nothing, Reference}`: a `Reference`
(what is selected inside this node) or `nothing` (nothing selected). Julia has no field inheritance, so the field
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
   the behavior: reactive, mutable, or immutable. `getproperty`/`setproperty!`
   read/write through the cells uniformly for every kind.

2. **Auto-wrapping constructor** (bare name) — `Foo(args…)` accepts raw values
   or cells; a raw value is wrapped in `ReactiveCell{Any}` (exactly the untyped
   `Cell`), so the bare name builds the **reactive kind** with the plain
   untyped-cell semantics. Passing cells (of any kind, even mixed) stores them as-is.

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
   when the struct declares no fields at all.

5. **Positional default constructors** (Rule Y, bare name only) — the positional
   analog of `@kwdef`: for a trailing run of defaulted fields, ctors `Foo(f₁..f_k)`
   that fill the omitted suffix with its defaults. Emitted only when ≥1 leading
   field is required (so the zero-arg form never shadows the keyword ctor);
   fully-defaulted structs get none.

6. **Single-collection constructors** (Rule C, bare name only) — when exactly one
   field's declared type opts into `is_collection_field_type`, a positional ctor
   accepts that slot as an `AbstractVector` and wraps it via that type, filling any
   trailing defaults. This holds whether the sibling fields are **required**
   (`Foo(callee, [args])`) or all default (`Foo([a, b])`, plus the variadic
   `Foo(a, b)` when the collection is the sole content).

7. **The layout registry** — [`document_cell_type`](@ref) answers the stem and
   [`document_native_type`](@ref) answers the native `mutable struct`, both keyed on
   the family so either takes any variant. A caller asks for a layout through these
   rather than by naming a type, which is what lets `copy_document` rebuild a source
   into the layout its target needs instead of the layout the source happened to
   have.

Since the stem is immutable, a node's field *cells* can never be swapped after
construction (`setfield!` is gone); all mutation flows through the cells, and
construction-time cell sharing replaces field-level retargeting.
"""
macro document(args...)
    _document_expr(args)
end

# The whole expansion, as a function of the argument list. `@document_preset`
# calls it too, so a preset is the same expansion with a layout list prepended —
# not a macro that expands into another macro, which would put the caller's struct
# definition through a second round of hygiene.
function _document_expr(args)
    layouts, rest = _take_layout_list(args)
    default, structdef = cell_struct_macro_default(rest)
    structdef.head === :struct || error("@document expects a struct definition")
    plan = cell_struct_plan(structdef)

    # Default the supertype to `Document` unless one is written explicitly, so
    # `@document struct Foo … end` means `struct Foo <: Document … end`. The
    # injected `:Document` resolves in the caller's scope (the result is `esc`'d).
    supertype = plan.supertype === nothing ? :Document : plan.supertype

    # ── Per-schema abstract family + native mutable layout (two-layout support) ──
    # `family` is an abstract type inserted between the stem and its supertype; the
    # stem and the native mutable struct both subtype it, so `document_family`
    # recognizes every variant of one schema as the same document even though the
    # two layouts share no type wrapper. Additive for now — the bare name is still
    # the stem, and existing `Foo`/`Foo{…}` dispatch and aliases are unchanged.
    family = Symbol("Abstract", plan.name)
    native = Symbol(plan.name, "Mut")

    # ── Inject the selection field ────────────────────────────────────────────
    # Every document carries a selection — `Union{Nothing, Reference}`, i.e. a
    # `Reference` (what is selected *inside* that node) or `nothing` for no
    # selection. Julia has no field inheritance, so the field has to be materialized
    # on every struct; the macro writes it so the programmer never repeats it.
    #
    # The type is emitted as the `Union{…}` expression, not a spliced type object:
    # `Reference` is defined in the reference layer, *above* this one, so this
    # module cannot name it directly. The expansion is `esc`'d, so `Reference`
    # resolves in the caller's module — where it is always in scope, since a module
    # that declares documents necessarily uses the reference layer.
    #
    # Declaring it by hand is normally unnecessary — the macro injects it. But a
    # **value-document** declares `selection` explicitly to control its *value type*,
    # which is the isbits pivot: `selection::ImmutableCell{Nothing}` is isbits and
    # non-selectable (a leaf value), while the injected `Union{Nothing, Reference}` form is selectable.
    # An explicit field must be declared **last** and defaults to `nothing` (added here
    # if omitted, so it does not count as a programmer default and leaves Rule Y / the
    # keyword ctors gated exactly as the injected field would).
    if :selection in plan.field_names
        findfirst(==(:selection), plan.field_names) == length(plan.field_names) ||
            error("@document $(plan.name): an explicit `selection` field must be declared last.")
        haskey(plan.defaults, :selection) || (plan.defaults[:selection] = :nothing)
    else
        add_cell_struct_field!(plan, :selection, :(Union{Nothing, Reference}), :nothing)
    end

    # The stem now subtypes `family` (which subtypes the real supertype), not the
    # supertype directly — transparent for existing `<: Super` dispatch (transitive).
    plan = CellStructPlan(plan.structdef, plan.name, family, plan.field_names,
                      plan.field_types, plan.field_slots, plan.defaults,
                      plan.n_declared, plan.n_programmer_defaults)

    # One gensym'd argument list, shared by the inner ctor and the kind ctors.
    arg_names = [gensym(f) for f in plan.field_names]

    # The layout registry, keyed on the family so either accessor takes any variant.
    # This is what lets a caller ask for a layout instead of naming one: before it,
    # the type name was the only way to reach a layout, and `copy_document` therefore
    # rebuilt whatever layout the source already had.
    family_method    = :((::typeof($document_family))(::Type{<:$family}) = $family)
    cell_type_method = :((::typeof($document_cell_type))(::Type{<:$family}) =
                             $(plan.name))

    # The mutable native layout, emitted only when the layout list asks for it. A
    # schema that leaves `M` out has no native type at all, and the default
    # `document_native_type` answers `nothing` for it — which is what a caller
    # reads to find out.
    #
    # Native-layout constructors target `FooMut`'s auto (all-args) ctor — the same
    # Rule Y positional-defaults + keyword forms the stem gets, but storing raw
    # values (no cell wrapping), so building the native variant is as ergonomic as
    # building the stem.
    native_parts = Any[]
    if :M in layouts
        push!(native_parts, _emit_native_mutable(plan, family, native))
        append!(native_parts, cell_struct_positional_ctors(plan, native))
        if plan.n_programmer_defaults > 0 || plan.n_declared == 0
            push!(native_parts, cell_struct_kwctor(native, plan.field_names,
                                cell_struct_kw_params(plan.field_names, plan.defaults)))
        end
        push!(native_parts, :((::typeof($document_native_type))(::Type{<:$family}) =
                                  $native))
        push!(native_parts, Expr(:export, native))
    end

    structdef = _emit_stem!(plan)
    push!(structdef.args[3].args, _emit_autowrap_ctor(plan, arg_names; default = default))
    getprop, setprop = _emit_accessors(plan)

    esc(Expr(:block,
             :(abstract type $family <: $supertype end),
             :(Base.@__doc__ $structdef),
             getprop, setprop,
             native_parts...,
             family_method, cell_type_method,
             Expr(:export, family),
             _emit_kind_aliases(plan, arg_names; default = default)...,
             _emit_keyword_ctors(plan)...,
             # Rule Y (the cell layer's, generic over any cell struct), each arity
             # followed by its Rule C companion; then Rule C's element-sugar tail.
             cell_struct_positional_ctors(plan, plan.name;
                                          each_arity = k -> _emit_collection_ctor_at(plan, k))...,
             _emit_collection_ctors(plan)...))
end

"""
    @document_preset name [layouts]

Define `@name` as [`@document`](@ref) with a fixed layout list. A package that
wants the same list on every schema declares the preset once and then writes the
preset's name, so a reader of any one file knows what a declaration emits.

```julia
@document_preset native_document [M, C]     # once, in the package root module

@native_document struct TicTocMessage1      # and then at every declaration
    name::String
end
```

The alternative was a module-level default that `@document` reads at expansion
time. It works, and it was rejected: two declarations that look the same would
expand differently, and the reader would have to find a file they were not looking
at. A preset costs one longer name at the call site and says what it does there.

A preset's own arguments are passed through, so a field-kind marker still works:
`@native_document ImmutableCell struct …`.
"""
macro document_preset(name::Symbol, layouts)
    # Validated here rather than at first use, so a typo in a preset is an error
    # where the preset is written.
    layouts isa Expr && layouts.head === :vect ||
        error("@document_preset: expected a layout list, as in `@document_preset name [M, C]`")
    _take_layout_list((layouts,))
    esc(Expr(:macro, Expr(:call, name, Expr(:..., :args)),
             :($(_document_expr)(($(QuoteNode(layouts)), args...)))))
end
