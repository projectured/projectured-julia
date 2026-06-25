"""
    DocumentModule

Contract for all document types. Every concrete document must subtype
Document and carry a selection::Reference holding the ReferencePath relative
to that node. This shared contract is what allows set_selection! to
propagate a path generically without knowing the concrete type.
"""
module DocumentModule

import ..DocumentApiModule: Document
import ..ReactiveModule: Cell

export Document, selection, @document, @forward

"""
    selection(doc::Document)

Return the current selection value of a document.
"""
selection(doc::Document) = doc.selection

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

Annotate a Document struct whose fields should be transparent reactive Cells.
The programmer writes real value types; the macro generates:

1. **Cell-based struct** (same name) — all fields become `::Cell`, with
   `getproperty`/`setproperty!` reading/writing through Cells transparently.
   An auto-wrapping inner constructor accepts either raw values or Cells.

2. **Immutable struct** (`I` prefix) — original field types preserved, no
   Cell indirection, standard Julia field access.

3. **Conversion constructors** — `IFoo(foo::Foo)` snapshots cells into an
   immutable value; `Foo(ifoo::IFoo)` hydrates back into reactive Cells.

Fields may carry `@kwdef`-style defaults (`field::T = value`). When at least one
default is present, the macro also generates:

4. **Keyword constructors** for both `Foo` and `IFoo` — fields with a default are
   optional keywords, fields without one are required keywords.

5. **Positional default constructors** (Rule Y) — the positional analog of
   `@kwdef`: for a trailing run of defaulted fields, ctors `Foo(f₁..f_k)` that fill
   the omitted suffix with its defaults. Emitted only when ≥1 leading field is
   required (so the zero-arg form never shadows the keyword ctor); fully-defaulted
   structs get none.

6. **Single-`CellVector` constructors** (Rule C) — when exactly one field is a
   `CellVector` and every other field has a default, `Foo([a, b])` and the variadic
   `Foo(a, b)` wrap the elements per-element via `CellVector(items)` and fill the
   rest. Elements are typed `Document` (the universal base), so a collection may
   hold children of any domain (mixed JSON / text / widget …).
"""
macro document(structdef)
    structdef.head === :struct || error("@document expects a struct definition")
    # Default the supertype to `Document` unless one is written explicitly, so
    # `@document struct Foo … end` means `struct Foo <: Document … end`. A domain
    # abstract supertype (`<: JsonDocument`, …) or any explicit `<: …` always
    # wins. Normalizing `name_expr` to always carry a `<:` here also feeds the
    # I-struct supertype logic below. The injected `:Document` resolves in the
    # caller's scope (the result is `esc`'d) — same mechanic as `@iomap`/`IoMap`.
    name_expr = structdef.args[2]
    if !(name_expr isa Expr && name_expr.head === :(<:))
        name_expr = Expr(:(<:), name_expr, :Document)
        structdef.args[2] = name_expr
    end
    struct_name = name_expr.args[1]
    body = structdef.args[3]

    # ── Collect original field info and replace types with Cell ────────
    original_fields = Tuple{Symbol, Any}[]  # (name, original_type_or_nothing)
    cell_fields = Symbol[]
    defaults = Pair{Symbol, Any}[]  # field => default-value expr (declaration order)
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            push!(original_fields, (ex, nothing))
            body.args[i] = :($(ex)::Cell)
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            push!(original_fields, (ex.args[1], ex.args[2]))
            ex.args[2] = :Cell
        elseif ex isa Expr && ex.head === :(=) && length(ex.args) == 2
            # `name = v` / `name::T = v` — @kwdef-style default. Strip the default
            # out of the (plain) struct body and remember it for the keyword ctor;
            # the original declared type still feeds the immutable I-struct.
            lhs = ex.args[1]
            if lhs isa Symbol
                fname, ftype = lhs, nothing
            else
                fname, ftype = lhs.args[1], lhs.args[2]
            end
            push!(cell_fields, fname)
            push!(original_fields, (fname, ftype))
            push!(defaults, fname => ex.args[2])
            body.args[i] = :($(fname)::Cell)
        end
    end
    isempty(cell_fields) && return esc(structdef)

    cell_set = Set(cell_fields)

    # ── Auto-wrapping inner constructor ───────────────────────────────
    # The ONLY inner constructor; hand-written convenience constructors
    # remain as outer constructors and just call T(plain_values...).
    if !isempty(original_fields)
        arg_names = [gensym(f[1]) for f in original_fields]
        new_args = map(enumerate(original_fields)) do (i, (fname, _ftype))
            a = arg_names[i]
            fname in cell_set ? :($a isa Cell ? $a : Cell($a)) : a
        end
        ctor = :(function $(struct_name)($(arg_names...))
            $(Expr(:call, :new, new_args...))
        end)
        push!(body.args, ctor)
    end

    # ── getproperty: read through Cell ────────────────────────────────
    get_body = :(getfield(obj, name))
    for fname in reverse(cell_fields)
        get_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[]),
                        get_body)
    end
    getprop = :(function Base.getproperty(obj::$(struct_name), name::Symbol)
        $get_body
    end)

    # ── setproperty!: write through Cell ──────────────────────────────
    set_body = :(setfield!(obj, name, val))
    for fname in reverse(cell_fields)
        set_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[] = val),
                        set_body)
    end
    setprop = :(function Base.setproperty!(obj::$(struct_name), name::Symbol, val)
        $set_body
    end)

    # ── I-prefixed immutable struct ───────────────────────────────────
    i_name = Symbol("I", struct_name)
    i_fields = [typ === nothing ? fname : :($fname::$typ) for (fname, typ) in original_fields]
    i_supertype = name_expr.args[2]   # always present: normalized at the top
    i_name_expr = Expr(:(<:), i_name, i_supertype)
    i_struct = Expr(:struct, false, i_name_expr, Expr(:block, i_fields...))

    # Snapshot constructor: IFoo(foo::Foo) — reads all cells via getproperty
    snap_args = [:(obj.$(fname)) for (fname, _) in original_fields]
    snapshot = :($(i_name)(obj::$(struct_name)) = $(Expr(:call, i_name, snap_args...)))

    # Hydrate constructor: Foo(ifoo::IFoo) — auto-wrapping constructor handles Cell wrapping
    hyd_args = [:(obj.$(fname)) for (fname, _) in original_fields]
    hydrate = :($(struct_name)(obj::$(i_name)) = $(Expr(:call, struct_name, hyd_args...)))

    # ── Keyword constructors (only when ≥1 default is declared) ────────
    # Forward into the positional ctors of both the Cell-based `Foo` and the
    # immutable `IFoo`, so defaults are available on either. Fields without a
    # default become required keywords, à la `Base.@kwdef`.
    extra = Any[]
    if !isempty(defaults)
        default_map = Dict(defaults)
        kw_params = map(original_fields) do (fname, _)
            haskey(default_map, fname) ? Expr(:kw, fname, default_map[fname]) : fname
        end
        field_names = [fname for (fname, _) in original_fields]
        push!(extra, :(function $(struct_name)(; $(kw_params...))
            $(Expr(:call, struct_name, field_names...))
        end))
        push!(extra, :(function $(i_name)(; $(kw_params...))
            $(Expr(:call, i_name, field_names...))
        end))

        # ── Rule Y: positional ctors that omit a trailing run of defaulted
        #    fields (the positional analog of `@kwdef`). Generated only when at
        #    least one leading field is required (`req ≥ 1`), so we never emit a
        #    zero-arg form colliding with the keyword ctor's `Foo()`; fully
        #    defaulted structs are left to their keyword / hand-written ctors. ──
        n = length(original_fields)
        trailing = 0
        for (fname, _) in Iterators.reverse(original_fields)
            haskey(default_map, fname) || break
            trailing += 1
        end
        req = n - trailing
        if req ≥ 1
            for k in req:(n-1)
                kept   = field_names[1:k]
                filled = Any[default_map[field_names[j]] for j in (k+1):n]
                push!(extra, :($(struct_name)($(kept...)) =
                    $(Expr(:call, struct_name, kept..., filled...))))
                push!(extra, :($(i_name)($(kept...)) =
                    $(Expr(:call, i_name, kept..., filled...))))
            end
        end

        # ── Rule C: when the struct is backed by exactly one `CellVector` field
        #    and every other field has a default, accept the elements directly and
        #    wrap them per-element via `CellVector(items)` (CollectionModule already
        #    defines `CellVector(::AbstractVector)`). Two element-accepting forms,
        #    both Cell-based `Foo` only:
        #
        #      Foo(items::AbstractVector)   # bracketed: Foo([a, b, c])
        #      Foo(items::Document...)      # variadic:  Foo(a, b, c)
        #
        #    The element type is `Document` (the universal base), not the struct's
        #    own domain — a collection may hold children of any domain (mixed JSON /
        #    text / widget …). That choice also makes both forms safe:
        #      • `AbstractVector` (not `Vector`) stays strictly less specific than
        #        any hand-written `Foo(::Vector{…})`, so it never redefines one.
        #      • `Document...` doesn't clash with typed-variadic sugar like
        #        `JsonObject(::Pair...)` (a `Pair` is not a `Document`), and a more
        #        specific hand-written `Foo(::SomeDoc...)` always wins over it.
        #      • At arity == field-count it beats the all-fields inner ctor (whose
        #        non-element fields — `collapsed::Bool`, `selection::Reference`, … —
        #        are not `Document`s, so a genuine inner call never matches it).
        cv_fields = [fname for (fname, ftype) in original_fields if ftype === :CellVector]
        if length(cv_fields) == 1 &&
           all(haskey(default_map, f) for (f, ft) in original_fields if ft !== :CellVector)
            cvf   = cv_fields[1]
            cargs = Any[f === cvf ? :(CellVector(items)) : default_map[f] for f in field_names]
            push!(extra, :($(struct_name)(items::AbstractVector) =
                $(Expr(:call, struct_name, cargs...))))
            push!(extra, :($(struct_name)(items::Document...) =
                $(struct_name)(collect(items))))
        end
    end

    # The Cell-based variant is a **mutable** struct: every field is a `Cell`, so
    # mutating field *contents* already worked via `setproperty!`, but making the
    # struct itself mutable additionally allows swapping a field's Cell object
    # (`setfield!`) — needed to keep/replace Cell identity. The immutable snapshot
    # is the I-prefixed variant above.
    structdef.args[1] = true

    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop,
                     i_struct, snapshot, hydrate, extra...))
end

"""
    @forward T field [f₁, f₂, …]

Generate delegating methods that forward each listed function on `T` to the
value of `T`'s `field`. For example

    @forward JsonArray elements [Base.length, Base.getindex]

emits

    Base.length(x::JsonArray, args...; kw...)   = Base.length(x.elements, args...; kw...)
    Base.getindex(x::JsonArray, args...; kw...)  = Base.getindex(x.elements, args...; kw...)

so a wrapper type can expose its field's protocol (e.g. a `CellVector`'s vector
interface) without hand-writing one method per function. The field is read
through `getproperty`, so it sees the unwrapped value of a `@document` Cell
field.
"""
macro forward(T, field, fns)
    (fns isa Expr && fns.head === :vect) ||
        error("@forward: third argument must be a vector literal of functions, e.g. [Base.length, Base.size]")
    fieldsym = QuoteNode(field)
    defs = map(fns.args) do f
        :($(esc(f))(x::$(esc(T)), args...; kw...) =
              $(esc(f))(Base.getproperty(x, $fieldsym), args...; kw...))
    end
    Expr(:block, defs...)
end

end # module
