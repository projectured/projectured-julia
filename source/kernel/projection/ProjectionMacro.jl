# Fragment of `ProjectionModule` — `@projection`, the codegen that declares a
# projection type.

"""
    @projection struct T [<: Super] ... end

Annotate a Projection struct whose `::Cell` fields should be transparent.
`obj.field` reads the Cell value, `obj.field = val` writes to it;
raw Cells remain accessible via `getfield(obj, :field)`.

Fields may carry `@kwdef`-style defaults (`field::T = value`). When at least one
default is present, a keyword constructor is also generated — fields with a
default are optional keywords, fields without one are required keywords —
forwarding into the positional auto-wrapping constructor.

The macro exports the type it declares, the way `@document` does. A projection
type is the public name of the rule it holds, so the module that declares it
needs no `export` line of its own.

This is `@cell_struct` (the struct layer's transparent-Cell struct codegen) plus
one default: a struct without an explicit supertype gets `<: Projection`. The
injected `:Projection` resolves in the caller's scope (the result is `esc`'d)
— same mechanic as `@iomap`/`IoMap`.

A projection's parameter cells are what make its `print_document` reactive: an
operation writes a parameter cell (e.g. `FocusingProjection`'s `part`), and the
computed cells the returned IoMap wired from it re-derive — the change propagating
through that same IoMap without a re-print. Wire the IoMap's `output` and child
IoMaps as computed cells reading the parameters/input; a plain struct is fine only
for a projection with no reactive parameters (see `@iomap`).
"""
macro projection(args...)
    default, structdef = parse_cell_struct_macro_arguments(args)
    structdef.head === :struct || error("@projection expects a struct definition")
    name_expr = structdef.args[2]
    if !(name_expr isa Expr && name_expr.head === :(<:))
        structdef.args[2] = Expr(:(<:), name_expr, :Projection)
    end
    # A projection type is the public name of the rule it holds, so the macro
    # exports it — the same rule `@document` follows for a document type. A
    # module that also names it on an `export` line is a harmless duplicate.
    name = structdef.args[2].args[1]
    name isa Expr && name.head === :curly && (name = name.args[1])
    return esc(Expr(:block,
                    build_cell_struct_exprs(structdef; default = default),
                    Expr(:export, name)))
end
