# Fragment of `DocumentModule` — the `@document` codegen.
#
# The macro is a parse followed by the `_emit_` functions of this file. It reads
# the struct definition into a `CellStructPlan` (the struct layer's parse), appends
# the `selection` field every document must carry, and then each emitter makes one
# piece of the expansion from that plan. Rule Y — positional
# constructors filling a trailing run of defaults — is not document-specific and
# lives with the other constructor builders in the struct layer.

# The reactive default a bare `Foo(…)` wraps a raw value in: the untyped `Cell`.
const _REACTIVE_ANY = ReactiveCell{Any}

# ── The layout list ───────────────────────────────────────────────────────────
# `@document [C, M] struct Foo … end` says which layouts the schema emits, and its
# **first entry says what the bare name is**. `C` is the cell layout, `M` the
# mutable native struct, `I` the immutable native struct. The family and the four
# spelling aliases are never listed — the family is what two layouts share, and an
# alias is a `const` whose absence would only surprise.
#
# `DC` is the odd one: it emits nothing that `C` does not, and only binds the bare
# name to `DCFoo`, the default spelling. A field typed `Foo` is then concrete and
# inlines, which is what a value document stored by value in a config cell wants.
#
# The default is the cell layout and the mutable native struct, with the bare name
# on the cell layout.
const _DEFAULT_LAYOUTS = (:C, :M)
const _KNOWN_LAYOUTS   = (:C, :DC, :M, :I)

"""
    _take_layout_list(args) -> (layouts::Tuple{Vararg{Symbol}}, rest)

Pull the layout list out of a `@document` argument list, wherever it sits, and
return it with the remaining arguments for [`parse_cell_struct_macro_arguments`](@ref).
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
    end
    # One schema has one native struct, because `get_document_native_type` gives one
    # answer. A schema that wanted both would have to say which one that is.
    (:M in codes && :I in codes) &&
        error("@document: a schema declares `M` or `I`, not both. They are two " *
              "spellings of one native layout, and `get_document_native_type` names one.")
    # `DC` asks for the cell layout too — it only moves the bare name inside it.
    (:C in codes || :DC in codes) ||
        error("@document: a layout list must include `C` or `DC` for now. A schema with " *
              "no cell layout has no aliases, no auto-wrapping constructor and no " *
              "shadow, and nothing asks for one yet.")
    # Every path below asks "is the cell layout emitted" as `:C in layouts`, so a
    # list that said `DC` carries both: the layout, and the binding in first place.
    codes = :DC in codes && !(:C in codes) ? [codes..., :C] : codes
    (Tuple(codes), args[[j for j in eachindex(args) if j != i]])
end

# The NAME of a declared field type, for asking a seam keyed on `Val{name}`:
# `:Vector` for both `Vector{T}` and a bare `Vector`, and `nothing` for anything
# that does not name a type. `is_collection_field_type` asks only about a bare
# symbol; a substitution has to see through the `:curly` too, because the whole
# point is a field written `params::Vector{NedParam}`.
_declared_type_name(t::Symbol) = t
_declared_type_name(t::Expr) =
    (t.head === :curly && t.args[1] isa Symbol) ? t.args[1] : nothing
_declared_type_name(::Any) = nothing

# What the CELL layout holds for a field, which is the declared type unless a
# collection registered a reactive counterpart for it — see
# `get_cell_layout_field_type`. The NATIVE layout never asks, so it keeps the plain
# type the programmer wrote.
function _cell_value_types(plan)
    map(get_cell_struct_value_types(plan)) do vt
        name = _declared_type_name(vt)
        substitute = name === nothing ? nothing : get_cell_layout_field_type(Val(name))
        substitute === nothing && return vt
        # `Vector{X}` keeps its element type: the cell layout holds `CellVector{X}`.
        vt isa Expr && vt.head === :curly ? Expr(:curly, substitute, vt.args[2:end]...) :
                                            substitute
    end
end

# Whether a field whose cell layout holds `vt` is a list field: its type names a
# collection that registered itself with `is_collection_field_type`.
function _is_list_field_type(vt)
    vt isa Type && return _is_list_type(vt)
    # A substituted `Vector{X}` is `CellVector{X}` with the type object at its head.
    vt isa Expr && vt.head === :curly && vt.args[1] isa Type && return _is_list_type(vt.args[1])
    name = _declared_type_name(vt)
    name !== nothing && is_collection_field_type(Val(name))
end

# Whether the declared type `T` names a registered collection, at run time.
_is_list_type(T) = (T isa DataType || T isa UnionAll) && is_collection_field_type(Val(nameof(T)))

# A plain vector that goes into a list field becomes the list of the field, so the
# cell layout holds one form of a list (`CellVector{X}` for `Vector{X}`).
_wrap_list_value(list_type, value) = value isa AbstractVector ? list_type(value) : value

# The setter's form: the list type comes from the declared type of the field.
function _wrap_list_write(document, name::Symbol, value)
    value isa AbstractVector || return value
    declared_type = find_declared_field_type(typeof(document), name)
    declared_type === nothing && return value
    _wrap_list_value_of(declared_type, value)
end

# The form of an operation, which knows the declared type of its slot.
_wrap_list_value_of(declared_type, value) =
    value isa AbstractVector && _is_list_type(declared_type) ? declared_type(value) : value

# A kind constructor of a variant (`ICFoo`, `MCFoo`) holds the list in its own kind:
# a plain vector becomes the list of the field, copied into cells of the kind `K`.
_wrap_list_value_of_kind(K, list_type, value) =
    value isa AbstractVector ? copy_document(K, list_type(value)) : value

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
    # The programmer's OWN type parameters come first, then one cell parameter per
    # field. A layout restores the struct the programmer would have written, so
    # `struct Foo{A}` has to stay `Foo{A, …}` and not become `Foo{A}{…}`.
    plan.definition.args[2] = Expr(:(<:),
        Expr(:curly, plan.name, plan.parameters...,
             [Expr(:(<:), C, AbstractCell) for C in Cs]...),
        plan.supertype)
    plan.definition
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
function _emit_autowrap_ctor(plan, arg_names; default = ReactiveCell)
    n = length(plan.field_names)
    # Per-field default kind and value type. `def_types[i]` is the cell type a raw
    # value in field i defaults to; `default` is the struct-level default (from a
    # leading macro kind) for any field that does not name its own kind — the injected
    # `selection` field is such a field, so it follows `default` too. With no leading
    # kind (`default = ReactiveCell`) and nothing annotated these are all
    # `ReactiveCell{Any}` and every path below reduces to the plain untyped-cell codegen.
    kinds     = get_cell_struct_field_kinds(plan; default = default)
    vts       = get_cell_struct_value_types(plan)
    def_types = Any[build_cell_struct_field_type(kinds[i], vts[i]) for i in 1:n]
    # A plain vector for a reactive list field becomes the list of the field.
    list_types = _cell_value_types(plan)
    raw_value(i) = kinds[i] === ReactiveCell && _is_list_field_type(list_types[i]) ?
        :($(_wrap_list_value)($(list_types[i]), $(arg_names[i]))) : arg_names[i]
    raw_wrap(i) = :($(def_types[i])($(raw_value(i))))
    rc_any   = fill(_REACTIVE_ANY, n)
    # A parameter binds from the argument that `find_cell_struct_parameter_slots`
    # gives, and the inferring outer constructor below is emitted. A schema with a
    # parameter that binds from no argument gets only the explicit `Foo{A}(…)`.
    names = get_cell_struct_parameter_names(plan)
    slots = find_cell_struct_parameter_slots(plan)
    inferrable = !isempty(names) && slots !== nothing
    # All args are `ReactiveCell{Any}`, so every value type IS `Any` — a constant,
    # which is what keeps this path free of a runtime `apply_type`.
    # With explicit parameters the three paths all splice the parameter NAMES; the
    # inferring outer form computes them once and delegates here.
    up = Any[names...]
    up_rc = up_raw = up_mixed = up
    all_rc   = mapreduce(a -> :($a isa $(_REACTIVE_ANY)), (x, y) -> :($x && $y), arg_names)
    any_cell = mapreduce(a -> :($a isa $(AbstractCell)),   (x, y) -> :($x || $y), arg_names)
    wrapped    = [gensym(f) for f in plan.field_names]
    wrap_stmts = [:($(wrapped[i]) = $(arg_names[i]) isa $(AbstractCell) ?
                        $(arg_names[i]) : $(raw_wrap(i)))
                  for i in 1:n]
    # The mouse target, the last field that `@document` adds, takes only a cell or
    # `nothing`: a collection document with element sugar, `Foo(items::Document...)`,
    # would otherwise lose a call with one element for each field to this
    # constructor. A `nothing` becomes a cell of the field's default kind when every
    # other argument is a `ReactiveCell{Any}`, so a call that passes the fields a
    # document had without it stays on the fast path.
    target = n > 0 && plan.field_names[end] === :mouse_target
    params = Any[arg_names...]
    target && (params[end] = :($(arg_names[end])::Union{Nothing, $(AbstractCell)}))
    others_rc = n > 1 ? mapreduce(a -> :($a isa $(_REACTIVE_ANY)), (x, y) -> :($x && $y),
                                  arg_names[1:(n - 1)]) : true
    fill_target = target ?
        :($(arg_names[n]) === nothing && $others_rc &&
          ($(arg_names[n]) = $(raw_wrap(n)))) :
        nothing
    # The head carries the programmer's parameters when there are any, so `new{…}`
    # can name them; a schema with none gets the plain head `Foo(args…)`.
    head = isempty(names) ? :($(plan.name)($(params...))) :
           Expr(:where, :($(Expr(:curly, plan.name, names...))($(params...))),
                plan.parameters...)
    # Each path hands the new document to the check of the declared types.
    check = _check_constructed_document
    body = quote
        $fill_target
        if $all_rc
            return $check($(Expr(:call, Expr(:curly, :new, up_rc..., rc_any...), arg_names...)))
        elseif !($any_cell)
            return $check($(Expr(:call, Expr(:curly, :new, up_raw..., def_types...),
                                 [raw_wrap(i) for i in 1:n]...)))
        end
        $(wrap_stmts...)
        $check($(Expr(:call, Expr(:curly, :new, up_mixed..., [:(typeof($w)) for w in wrapped]...),
                      wrapped...)))
    end
    # `Expr(:function, …)` and not `:(function $head … end)`: the parser will not
    # take an interpolated signature.
    inner = Expr(:function, head, body)
    # `Foo(raw…)` for a schema whose every parameter is some field's declared type:
    # bind each from its argument, then hand over to the explicit form.
    bound = inferrable ?
        [:($(get_cell_struct_argument_type)($(arg_names[i]))) for i in slots] : Any[]
    outer = inferrable ?
        :($(plan.name)($(params...)) =
              $(Expr(:curly, plan.name, bound...))($(arg_names...))) :
        nothing
    (inner, outer)
end

"""
    _emit_accessors(plan) -> (getprop, setprop)

Transparent property access. Uniform across every kind — which cell a field holds
decides the behaviour, so the accessors need no kind dispatch of their own.

The read of the field named `selection` passes what the cell holds through
[`unwrap_selection`](@ref), so a [`SelectionDocument`](@ref) there answers its
reference while it is live and `nothing` once it is dormant. The read of every
other field answers what the cell holds and makes no call for the selection.
That call dispatches at run time, because a field of the reactive kind holds
`Any`, and the test of the name is one comparison of two symbols.
"""
_emit_accessors(plan) = (
    :(Base.getproperty(obj::$(plan.name), name::Symbol) =
        name === :selection ? $(unwrap_selection)(getfield(obj, name)[]) :
                              getfield(obj, name)[]),
    :(Base.setproperty!(obj::$(plan.name), name::Symbol, val) =
        (getfield(obj, name)[] =
             $(_check_declared_write)(obj, name, $(_wrap_list_write)(obj, name, val)))),
)

"""
    _emit_kind_aliases(plan, arg_names) -> Vector

The spelling aliases `RCFoo` / `ICFoo` / `MCFoo` / `DCFoo`, the value-accepting
typed constructors `ICFoo(…)` / `MCFoo(…)`, and the `_declared_value_types` method
`copy_document(K, …)` reads a field's declared type from.

A spelling is one concrete parameter list of the **cell** layout. Each name
abbreviates a phrase, adjective first — `MCFoo` is the mutable cell `Foo` — and
the `C` says the variant keeps its fields in cells. That is what tells a spelling
from a layout: `MCFoo` is an immutable struct holding one `MutableCell` box per
field, while `MFoo`, the mutable native layout, is a single mutable object with
its fields inline.

`DCFoo` is the concrete type the **bare** constructor builds from raw values (the
per-field default combination); `RCFoo` / `ICFoo` / `MCFoo` wrap every field in one
kind's cells, so a fully-conforming node inhabits its alias.
"""
function _emit_kind_aliases(plan, arg_names; schema::Symbol = plan.name,
                            default = ReactiveCell)
    n     = length(plan.field_names)
    names = get_cell_struct_parameter_names(plan)
    # The CELL layout's value types, with any registered substitution applied.
    Tvals = _cell_value_types(plan)
    kinds = get_cell_struct_field_kinds(plan; default = default)
    # A spelling is named from the **schema**, not from the cell layout's own type
    # name. The two differ when the bare name was bound elsewhere, and a spelling
    # of `Foo` must stay `RCFoo` rather than becoming `CRCFoo`.
    r_name, i_name, m_name, d_name = (Symbol(p, schema) for p in ("RC", "IC", "MC", "DC"))

    # `const DCFoo = Foo{…}` becomes `const DCFoo{A} = Foo{A, …}` when the
    # programmer declared parameters: the cell parameters of a parametric stem
    # mention `A`, so the alias cannot close over it.
    alias(nm, cellparams) = Expr(:const, Expr(:(=),
        isempty(names) ? nm : Expr(:curly, nm, plan.parameters...),
        Expr(:curly, plan.name, names..., cellparams...)))
    # `DCFoo` names the concrete **default combination** the bare `Foo(raw…)` ctor
    # builds — each field in its default kind (`ReactiveCell{Any}`, or the struct
    # default from a leading macro kind). For a value-document (immutable default,
    # `selection::ImmutableCell{Nothing}`) it is isbits, so `ImmutableCell{DCFoo}`
    # inlines. `RCFoo`/`ICFoo`/`MCFoo` instead force one kind across every field.
    aliases = [
        alias(r_name, fill(_REACTIVE_ANY, n)),
        alias(i_name, [Expr(:curly, ImmutableCell, T) for T in Tvals]),
        alias(m_name, [Expr(:curly, MutableCell,  T) for T in Tvals]),
        alias(d_name, [build_cell_struct_field_type(kinds[i], Tvals[i]) for i in 1:n]),
    ]

    # A kind constructor names the DECLARED field types, and those mention the
    # programmer's parameters when the schema has any (`EventHeap{A}`). A
    # parameter is not inferable from an untyped argument, so the head carries it
    # and the body names it, exactly as the bare constructor above does:
    # `ICFoo{A}(raw…)`. A schema with no parameter gets the plain `ICFoo(raw…)`.
    kind_value(K, i, a) = _is_list_field_type(Tvals[i]) ?
        :($(_wrap_list_value_of_kind)($K, $(Tvals[i]), $a)) : a
    kind_ctor(kname, K) = Expr(:(=),
        isempty(names) ? :($(kname)($(arg_names...))) :
            Expr(:where, :($(Expr(:curly, kname, names...))($(arg_names...))),
                 plan.parameters...),
        Expr(:call, isempty(names) ? plan.name :
                    Expr(:curly, plan.name, names...),
            [:($a isa $(AbstractCell) ? $a : $(Expr(:curly, K, Tvals[i]))($(kind_value(K, i, a))))
             for (i, a) in enumerate(arg_names)]...))
    # A kind constructor also takes every field but the mouse target, which it
    # fills with `nothing`, as the bare name does: a caller that passes every
    # field a document has besides it keeps working.
    target = n > 0 && plan.field_names[n] === :mouse_target
    kept = arg_names[1:(n - 1)]
    kind_short(kname) = Expr(:(=),
        isempty(names) ? :($(kname)($(kept...))) :
            Expr(:where, :($(Expr(:curly, kname, names...))($(kept...))),
                 plan.parameters...),
        Expr(:call, isempty(names) ? kname : Expr(:curly, kname, names...),
             kept..., :nothing))
    shorts = target ? Any[kind_short(i_name), kind_short(m_name)] : Any[]

    # The `_declared_value_types` method is added through the function object's
    # singleton type: a spliced object is not a valid method-definition *name*,
    # but `(::typeof(f))(…)` is.
    #
    # The types it answers with mention the programmer's parameters when the
    # schema has any, so the method takes them from the type it is asked about:
    # `Type{<:Foo{A}} where {A}`. A copy asks with the parameters of its source.
    # A caller that asks about the bare name names no parameter, matches no method
    # here, and gets the default `nothing`. The types are not knowable without the
    # parameters, and saying so is what the default means.
    dvt = isempty(names) ?
        :((::typeof($(_declared_value_types)))(::Type{<:$(plan.name)}) = ($(Tvals...),)) :
        Expr(:(=),
             Expr(:where,
                  :((::typeof($(_declared_value_types)))(
                        ::Type{<:$(Expr(:curly, plan.name, names...))})),
                  plan.parameters...),
             Expr(:tuple, Tvals...))

    # The cell layout and its spelling aliases are all generated API, so the macro
    # exports them itself. A module re-exporting any of these names explicitly (e.g.
    # the bare name in a domain's `export` line) is a harmless duplicate.
    [aliases...,
     Expr(:export, plan.name, r_name, i_name, m_name, d_name),
     kind_ctor(i_name, ImmutableCell),
     kind_ctor(m_name, MutableCell),
     shorts...,
     dvt]
end

"""
    _emit_keyword_ctors(plan) -> Vector

Keyword constructors for `Foo`, `ICFoo` and `MCFoo` — fields with a default are
optional keywords, fields without one required, à la `Base.@kwdef`. The names must
match the spelling aliases [`_emit_kind_aliases`](@ref) emits, or a keyword call on
an alias finds no method.

Gated on the **programmer** having declared ≥1 default (the injected `selection`
does not count), or on the struct declaring no fields at all. A keyword
constructor is zero-*positional*, so it claims the `Foo(; …)` signature: gating it
this way leaves that signature to a struct that must hand-write one because it
does more than fill fields (back-linking a draft, coercing its arguments). A
struct with no fields of its own is the exception — it holds nothing but its
selection, so there is no hand-written constructor to protect and `Foo()` must
come from somewhere, which Rule Y cannot supply (`get_cell_struct_required_count == 0`).
"""
function _emit_keyword_ctors(plan; schema::Symbol = plan.name)
    _has_keyword_ctors(plan) || return Any[]
    kw_params = build_cell_struct_keyword_parameters(plan.field_names, plan.defaults)
    # The unprefixed one goes on the cell layout's own type name, not on the bare
    # name. When the bare name is bound to a spelling it reaches this method through
    # the forwarding constructor, and when it is bound to the native layout that
    # layout has a keyword constructor of its own.
    names = [plan.name, Symbol("IC", schema), Symbol("MC", schema)]
    [build_cell_struct_keyword_constructor(nm, plan.field_names; parameters = kw_params)
     for nm in names]
end

# Whether the schema of `plan` gets keyword constructors: the gate that
# `_emit_keyword_ctors` describes.
_has_keyword_ctors(plan) = plan.programmer_default_count > 0 || plan.declared_field_count == 0

# The single collection field's position, or 0 when there is not exactly one. A
# field's declared type opts in through `is_collection_field_type(::Val{name})`,
# which the type registers from its own package — so this macro names no concrete
# collection type. See `_emit_collection_ctors`.
function _collection_slot(plan)
    hits = findall(plan.field_types) do t
        name = _declared_type_name(t)
        name !== nothing && is_collection_field_type(Val(name))
    end
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
slot; it is passed to `build_cell_struct_positional_constructors` as its
`each_arity` hook, which is what ties it to Rule Y's own
`get_cell_struct_required_count ≥ 1` gate.
"""
function _emit_collection_ctor_at(plan, k)
    p = _collection_slot(plan)
    (1 ≤ p ≤ k) || return ()
    n = length(plan.field_names)
    fields, defaults = plan.field_names, plan.defaults
    filled   = Any[defaults[fields[j]] for j in (k + 1):n]
    params   = Any[j == p ? :($(fields[p])::AbstractVector)         : fields[j] for j in 1:k]
    callargs = Any[j == p ? :($(plan.field_types[p])($(fields[p]))) : fields[j] for j in 1:k]
    # Named the way Rule Y names it: a parameter that no field's declared type
    # is takes its place at the call, and one that a field's type is comes from
    # the argument.
    needs_parameters = !isempty(plan.parameters) &&
                       find_cell_struct_parameter_slots(plan) === nothing
    named    = needs_parameters ?
               Expr(:curly, plan.name, get_cell_struct_parameter_names(plan)...) :
               plan.name
    head     = needs_parameters ?
               Expr(:where, :($(named)($(params...))), plan.parameters...) :
               :($(plan.name)($(params...)))
    (Expr(:(=), head, Expr(:block, Expr(:call, named, callargs..., filled...))),)
end

"""
    _emit_mouse_target_ctor(plan) -> Vector

The constructor without the mouse target, for a document whose every field has a
default: `Foo(a, …, selection)` fills the mouse target with `nothing`. Rule Y
makes this arity for a document with a required field; a document with none has
no positional constructor but the full one, and a call that passes every field it
has besides the mouse target must work too.
"""
function _emit_mouse_target_ctor(plan)
    n = length(plan.field_names)
    (n > 0 && plan.field_names[n] === :mouse_target) || return Any[]
    get_cell_struct_required_count(plan) == 0 || return Any[]
    kept = plan.field_names[1:(n - 1)]
    needs_parameters = !isempty(plan.parameters) &&
                       find_cell_struct_parameter_slots(plan) === nothing
    named = needs_parameters ?
            Expr(:curly, plan.name, get_cell_struct_parameter_names(plan)...) :
            plan.name
    head = needs_parameters ?
           Expr(:where, :($(named)($(kept...))), plan.parameters...) :
           :($(plan.name)($(kept...)))
    Any[Expr(:(=), head, Expr(:block, Expr(:call, named, kept..., :nothing)))]
end

"""
    _emit_collection_ctors(plan) -> Vector

**Rule C**'s tail: the element sugar for a struct whose *every other* field
defaults — the bracketed `Foo([a, b])` and the variadic `Foo(a, b)`.

The bracketed "fill everything" form is emitted only when Rule Y did **not** run
(`get_cell_struct_required_count == 0`, i.e. the collection itself defaults); otherwise
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
    if get_cell_struct_required_count(plan) == 0
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
    _emit_native(plan, family, native; mutable) -> Expr

The **native-layout** struct: a real `struct native <: family` whose fields hold
the declared **value** types *directly* — no cell box — so a native document is
byte-for-byte a plain struct (`getproperty`/`setproperty!` are the default
`getfield`/`setfield!`). The value types resolve here exactly as they already do
in the `ICFoo` / `MCFoo` aliases, so this introduces no new forward reference.

`mutable` picks the layout: `MFoo` is a `mutable struct` and `IFoo` is an
immutable one. The immutable layout is what a value on a hot path wants, because
a `mutable struct` is never isbits, however small its fields are.
"""
function _emit_native(plan, family, native; mutable::Bool)
    vts = get_cell_struct_value_types(plan)
    fields = Any[:($(plan.field_names[i])::$(vts[i])) for i in eachindex(plan.field_names)]
    # The native layout IS the programmer's struct, so it carries the programmer's
    # parameters and nothing else — no cell parameters, because it holds no cells.
    # The family stays unparameterized, so `MFoo{A} <: AFoo` and every signature
    # written against the family keeps working.
    head = isempty(plan.parameters) ? native : Expr(:curly, native, plan.parameters...)
    Expr(:struct, mutable, Expr(:(<:), head, family), Expr(:block, fields...))
end

"""
    @document [Kind] [[layouts]] struct T [<: Super] ... end

Annotate a Document struct whose fields are transparent cells. The programmer
writes real value types.

An optional **layout list** says which layouts the schema emits: `C` the cell
layout, `DC` the cell layout with the bare name on its default spelling, `M` the
mutable native struct, `I` the immutable native struct. A list holds `C` or `DC`,
and at most one of `M` and `I`. A code names a layout and nothing else —
the family and the four spelling aliases are never listed, because the family is
what two layouts share and an alias is a `const` whose absence would only
surprise. With no list, the macro emits `[C, M]`. The canonical order writes the
field-kind marker first, as in `@document ImmutableCell [C] struct …`.

The list's **first entry says what the bare name is**, and that is the whole of
what a schema declares about how it is used:

| First entry | `Foo` means | Fits |
| --- | --- | --- |
| `C`, the default | the cell layout, `Foo{C1, …}` | anything an editor holds |
| `DC` | `DCFoo`, the concrete default spelling | a value document stored by value in a config cell, where a `Foo`-typed field must inline |
| `M` | `MFoo`, the plain `mutable struct` | a schema whose primary object is the one a simulator mutates |
| `I` | `IFoo`, the plain immutable `struct` | a small value on a hot path, kept isbits |

`DC` emits nothing that `C` does not; it only moves the bare name one step in. The
coded name always works too: a `C` schema still gets `const ACFoo = Foo`, so
`ACFoo` names the cell layout in every schema whichever binding was chosen.

A package that wants the same list on every schema declares it once with
[`@document_preset`](@ref) and writes the preset's name instead.

Every document gets a
**`selection::Union{Nothing, Reference, SelectionDocument} = nothing`** field,
appended after the programmer's fields by the macro. A `Reference` says what is
selected inside this node, a `SelectionDocument` holds a reference and says whether
it is the live selection, and `nothing` says that nothing is selected. Julia has no
field inheritance, so the field must exist on every struct, and the macro writes it
so that no struct repeats it. A value document can declare `selection` itself to fix
its value type, as in `selection::Nothing`. An explicit `selection` must be the last
field, and it defaults to `nothing`. The field is always defaulted, so it falls
inside Rule Y's trailing run and a document's own fields keep the positional arity
they would have had without it.

The cell layout also gets a **`mouse_target::Union{Nothing, Reference} = nothing`**
field after `selection`: the path of the part under the pointer, view state as the
selection is (see `is_view_state_field`). The native layout and a document that
declares its own `selection`, a value document, have none. A call that passes
every field but the mouse target still works, and the full constructor takes only
a cell or `nothing` for it, so a call with one element for each field still
reaches the element sugar of a collection document.

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
   or cells; a raw value is wrapped in the default kind of its field. With no
   leading kind marker and no kind in the field type, that is `ReactiveCell{Any}`
   (exactly the untyped `Cell`), so the bare name builds the **reactive kind** with
   the plain untyped-cell semantics. Passing cells (of any kind, even mixed) stores
   them as-is.

3. **Spelling aliases** — `RCFoo` (all fields `ReactiveCell{Any}`), `ICFoo`
   (`ImmutableCell{declared-type}`), `MCFoo` (`MutableCell{declared-type}`) and
   `DCFoo` (each field in its default kind, which the bare constructor builds from
   raw values), plus value-accepting ctors `ICFoo(args…)` / `MCFoo(args…)` that
   wrap raw values in their kind's typed cells. Convert a whole subtree between
   kinds with [`copy_document`](@ref)`(K, doc)`.

Fields may carry `@kwdef`-style defaults (`field::T = value`). The injected
`selection` is always one, so Rule Y and Rule C below always apply; the keyword
constructors are the exception and need a default you declared yourself.

4. **Keyword constructors** for `Foo`, `ICFoo` and `MCFoo` — fields with a default
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

7. **The layout registry** — [`get_document_cell_type`](@ref) answers the stem and
   [`get_document_native_type`](@ref) answers the native struct, both keyed on
   the family so either takes any variant. A caller asks for a layout through these
   rather than by naming a type, which is what lets `copy_document` rebuild a source
   into the layout its target needs instead of the layout the source happened to
   have.

Since the stem is immutable, a node's field *cells* can never be swapped after
construction (`setfield!` throws); all mutation flows through the cells, and
construction-time cell sharing replaces field-level retargeting.
"""
macro document(args...)
    _document_expr(args)
end

# The whole expansion, as a function of the argument list. `@document_preset`
# calls it too, so a preset is the same expansion with a layout list prepended —
# not a macro that expands into another macro, which would put the caller's struct
# definition through a second round of hygiene.
# A kind marker may arrive **qualified** when another macro emits this one —
# `PacketModule.ImmutableCell` rather than `ImmutableCell`, because hygiene
# resolves a name the emitting macro wrote. The kind is a name, not a value, and
# the module part carries nothing, so it is normalised away. Without this a macro
# in another package cannot pass a kind at all: it can only write the name bare
# and hope it is in scope wherever its own callers sit.
_bare_kind(a) = (a isa Expr && a.head === :. && length(a.args) == 2 &&
                 a.args[2] isa QuoteNode && a.args[2].value isa Symbol) ?
                a.args[2].value : a

function _document_expr(args)
    args = isempty(args) ? args :
           (map(_bare_kind, args[1:end-1])..., args[end])
    layouts, rest = _take_layout_list(args)
    default, structdef = parse_cell_struct_macro_arguments(rest)
    structdef.head === :struct || error("@document expects a struct definition")
    plan = make_cell_struct_plan(structdef)

    # Default the supertype to `Document` unless one is written explicitly, so
    # `@document struct Foo … end` means `struct Foo <: Document … end`. The
    # injected `:Document` resolves in the caller's scope (the result is `esc`'d).
    supertype = plan.supertype === nothing ? :Document : plan.supertype

    names = _get_schema_names(plan, layouts)
    injects_selection = :selection ∉ plan.field_names
    _add_selection_field!(plan)
    plan = _make_cell_layout_plan(plan, names)

    registry_parts = _emit_layout_registry(plan, names)
    native_parts = _emit_native_parts(plan, layouts, names)
    injects_selection && _add_mouse_target_field!(plan)
    # One gensym'd argument list, shared by the inner ctor and the kind ctors.
    arg_names = [gensym(f) for f in plan.field_names]
    binding_parts = _emit_bare_name_binding(names; has_keywords = _has_keyword_ctors(plan))

    structdef = _emit_stem!(plan)
    inner_ctor, outer_ctor = _emit_autowrap_ctor(plan, arg_names; default = default)
    push!(structdef.args[3].args, inner_ctor)
    outer_ctor_parts = outer_ctor === nothing ? Any[] : Any[outer_ctor]
    getprop, setprop = _emit_accessors(plan)

    esc(Expr(:block,
             :(abstract type $(names.family) <: $supertype end),
             :(Base.@__doc__ $structdef),
             outer_ctor_parts...,
             getprop, setprop,
             native_parts...,
             registry_parts...,
             Expr(:export, names.family),
             _emit_kind_aliases(plan, arg_names; schema = names.schema,
                                default = default)...,
             binding_parts...,
             _emit_keyword_ctors(plan; schema = names.schema)...,
             # Rule Y (the struct layer's, generic over any cell struct), each arity
             # followed by its Rule C companion; then Rule C's element-sugar tail.
             build_cell_struct_positional_constructors(plan, plan.name;
                 each_arity = k -> _emit_collection_ctor_at(plan, k))...,
             _emit_mouse_target_ctor(plan)...,
             _emit_collection_ctors(plan)...))
end

# ── The names of one schema ───────────────────────────────────────────────────
# `schema` is what the programmer wrote. Every coded name is built from it, so
# `AFoo`, `MFoo`, `ACFoo` and the four spellings mean the same thing in every
# schema.
#
# `family` is an abstract type inserted between the cell layout and the
# supertype the programmer wrote; every layout subtypes it, so `get_document_family`
# recognizes each variant of one schema as the same document even though the
# layouts share no type wrapper.
#
# One native struct per schema, and the layout list says which spelling it
# takes: `M` a mutable one, `I` an immutable one. Both carry the declared
# value types directly, so only mutability and the letter differ.
#
# The first entry of the layout list says what the bare name is. `C` leaves it
# on the cell layout, which is what it means with no list at all, so the struct
# keeps the programmer's own name and `show` still prints it. Any other binding
# moves the cell layout to `ACFoo` and makes the bare name a `const`.
function _get_schema_names(plan, layouts)
    schema = plan.name
    native_mutable = :I ∉ layouts
    binding = first(layouts)
    (schema = schema,
     family = Symbol("A", schema),
     native = Symbol(native_mutable ? "M" : "I", schema),
     native_mutable = native_mutable,
     default_spelling = Symbol("DC", schema),
     binding = binding,
     cell_name = binding === :C ? schema : Symbol("AC", schema))
end

# ── Inject the selection field ────────────────────────────────────────────────
# Every document carries a selection —
# `Union{Nothing, Reference, SelectionDocument}`: a `Reference` (what is selected
# *inside* that node), a `SelectionDocument` that holds a reference, or `nothing`
# for no selection. Julia has no field inheritance, so the field has to be
# materialized on every struct; the macro writes it so the programmer never
# repeats it.
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
# non-selectable (a leaf value), while the injected union is selectable.
# An explicit field must be declared **last** and defaults to `nothing` (added here
# if omitted, so it does not count as a programmer default and leaves Rule Y / the
# keyword ctors gated exactly as the injected field would).
function _add_selection_field!(plan)
    if :selection in plan.field_names
        findfirst(==(:selection), plan.field_names) == length(plan.field_names) ||
            error("@document $(plan.name): an explicit `selection` field must be " *
                  "declared last.")
        haskey(plan.defaults, :selection) || (plan.defaults[:selection] = :nothing)
    else
        # `SelectionDocument` is spliced as a type **object**, not as a name: it is
        # declared in this module, so no caller needs it in scope. `Reference` is
        # still a name, for the reason above.
        add_cell_struct_field!(plan, :selection;
                               type = :(Union{Nothing, Reference, $(SelectionDocument)}),
                               default = :nothing)
    end
    plan
end

# The plan of the cell layout. The cell layout subtypes `family` (which subtypes
# the real supertype), not the supertype directly — transparent for existing
# `<: Super` dispatch (transitive). It also takes `cell_name`, which is the
# programmer's own name unless the bare name was bound elsewhere. In the plan
# this answers, `plan.name` is the cell layout's *type* name, and `schema` is what
# coded names are built from.
_make_cell_layout_plan(plan, names) =
    CellStructPlan(plan.definition, names.cell_name, plan.parameters, names.family,
                   plan.field_names, plan.field_types, plan.field_slots,
                   plan.defaults, plan.declared_field_count,
                   plan.programmer_default_count)

# The layout registry, keyed on the family so either accessor takes any variant.
# A caller such as `copy_document` asks it for a layout and names no type.
function _emit_layout_registry(plan, names)
    family = names.family
    family_method    = :((::typeof($get_document_family))(::Type{<:$family}) = $family)
    cell_type_method = :((::typeof($get_document_cell_type))(::Type{<:$family}) =
                             $(plan.name))
    # The schema's own name, for a label. `nameof` would answer the coded name of
    # whichever layout it was handed, and a schema that bound its bare name
    # elsewhere would then read as its layout rather than as itself.
    schema_name_method = :((::typeof($get_document_schema_name))(::Type{<:$family}) =
                               $(QuoteNode(names.schema)))
    Any[family_method, cell_type_method, schema_name_method]
end

# The native layout, emitted only when the layout list asks for it. A schema
# that leaves both `M` and `I` out has no native type at all, and the default
# `get_document_native_type` answers `nothing` for it — which is what a caller
# reads to find out.
#
# Native-layout constructors target the native's auto (all-args) ctor — the
# same Rule Y positional-defaults + keyword forms the stem gets, but storing
# raw values (no cell wrapping), so building the native variant is as
# ergonomic as building the stem.
function _emit_native_parts(plan, layouts, names)
    native_parts = Any[]
    (:M in layouts || :I in layouts) || return native_parts
    native, family = names.native, names.family
    # When the list starts with `M` or `I`, the bare name is the native struct,
    # and a lookup of the bare name reaches the binding of that struct. So the
    # native struct takes the docstring too; the stem keeps it for `ACFoo`.
    native_def = _emit_native(plan, family, native; mutable = names.native_mutable)
    push!(native_parts, names.binding in (:M, :I) ? :(Base.@__doc__ $native_def) :
                                                    native_def)
    append!(native_parts, build_cell_struct_positional_constructors(plan, native))
    if _has_keyword_ctors(plan)
        parameters = build_cell_struct_keyword_parameters(plan.field_names, plan.defaults)
        push!(native_parts,
              build_cell_struct_keyword_constructor(native, plan.field_names; parameters))
    end
    push!(native_parts, :((::typeof($get_document_native_type))(::Type{<:$family}) =
                              $native))
    push!(native_parts, Expr(:export, native))
    native_parts
end

# ── Inject the mouse target field ─────────────────────────────────────────────
# A document that the editor holds carries the path of the part under the pointer
# as it carries its selection: `Union{Nothing, Reference}`, a `Reference` inside
# the node or `nothing` when the pointer is not in it. Only the cell layout has it,
# so it is added after the native layout is written: no pointer stands on a native
# object, which the editor shows through a projection whose output documents are
# cell layouts. A document that declares its own `selection`, a value document, has
# none, because a changing field would take its value storage away. It is the last
# field and defaults to `nothing`, so a call that passes the fields a document had
# without it still works (`_emit_autowrap_ctor`, `_emit_mouse_target_ctor`).
_add_mouse_target_field!(plan) =
    add_cell_struct_field!(plan, :mouse_target; type = :(Union{Nothing, Reference}),
                           default = :nothing)

# What the bare name points at, once every coded name exists. `C` needs no
# binding — the cell layout already carries the programmer's name — so it gets
# the coded alias instead, and both names work in every schema either way.
#
# A bare name bound to a **spelling** also needs a constructor. An inner
# constructor is defined on the parametric name alone, so a concrete
# parameterization has no method of its own: `DCFoo(1, "z")` is a `MethodError`
# without this. One catch-all covers Rule Y and Rule C, and the keyword form when
# the schema has one, and a domain's own `Foo(v::String)` stays more specific than
# it. The catch-all takes keywords only then, so `hasmethod` with keyword names
# answers what a call does: a `.pred` file reads a schema with no keyword form
# from its fields.
function _emit_bare_name_binding(names; has_keywords::Bool)
    schema, binding, cell_name = names.schema, names.binding, names.cell_name
    binding_parts = Any[]
    if binding === :C
        push!(binding_parts, Expr(:const, Expr(:(=), Symbol("AC", schema), cell_name)))
    else
        target = binding === :DC ? names.default_spelling : names.native
        push!(binding_parts, Expr(:const, Expr(:(=), schema, target)))
        binding === :DC && push!(binding_parts, has_keywords ?
            :((::Type{$target})(args...; kw...) = $cell_name(args...; kw...)) :
            :((::Type{$target})(args...) = $cell_name(args...)))
    end
    push!(binding_parts, Expr(:export, schema, Symbol("AC", schema)))
    binding_parts
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
