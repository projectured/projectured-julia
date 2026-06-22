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

export Document, selection, @document

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
"""
macro document(structdef)
    structdef.head === :struct || error("@document expects a struct definition")
    name_expr = structdef.args[2]
    struct_name = name_expr isa Expr && name_expr.head === :(<:) ? name_expr.args[1] : name_expr
    body = structdef.args[3]

    # ── Collect original field info and replace types with Cell ────────
    original_fields = Tuple{Symbol, Any}[]  # (name, original_type_or_nothing)
    cell_fields = Symbol[]
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            push!(original_fields, (ex, nothing))
            body.args[i] = :($(ex)::Cell)
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            push!(original_fields, (ex.args[1], ex.args[2]))
            ex.args[2] = :Cell
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
    i_supertype = name_expr isa Expr && name_expr.head === :(<:) ? name_expr.args[2] : nothing
    i_name_expr = i_supertype !== nothing ? Expr(:(<:), i_name, i_supertype) : i_name
    i_struct = Expr(:struct, false, i_name_expr, Expr(:block, i_fields...))

    # Snapshot constructor: IFoo(foo::Foo) — reads all cells via getproperty
    snap_args = [:(obj.$(fname)) for (fname, _) in original_fields]
    snapshot = :($(i_name)(obj::$(struct_name)) = $(Expr(:call, i_name, snap_args...)))

    # Hydrate constructor: Foo(ifoo::IFoo) — auto-wrapping constructor handles Cell wrapping
    hyd_args = [:(obj.$(fname)) for (fname, _) in original_fields]
    hydrate = :($(struct_name)(obj::$(i_name)) = $(Expr(:call, struct_name, hyd_args...)))

    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop,
                     i_struct, snapshot, hydrate))
end

end # module
