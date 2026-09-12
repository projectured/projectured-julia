# Fragment of `ReferenceModule` — the **surface grammar** shared by the two reference
# DSLs. `@reference` / `@reference_step` (`ReferenceBuilder.jl`) and `@reference_case`
# (`ReferenceCase.jl`) accept the same path syntax; this fragment parses it once, into
# one step AST, and each DSL *lowers* that AST its own way — the builder to constructor
# calls, the matcher to match branches.
#
# The AST holds **raw Julia expressions** in every leaf slot. That is what makes one
# parser enough: the builder escapes those expressions at codegen, and the matcher runs
# them through its own value-pattern parser (`_parse_value`, a pure function of the
# expression) at lowering time. Parse the shape once; interpret the leaves per side.
#
# The grammar deliberately accepts a little more than either DSL can lower — `name...`
# is meaningless to the builder, `^(e)` mid-path is meaningless to the matcher. Each
# lowerer rejects the nodes it cannot use, with a message naming the DSL. This keeps the
# grammar one thing rather than two nearly-identical things that drift.
#
# The step vocabulary this produces lives in `ReferenceStep.jl`; the reference-step seams the
# extension steps dispatch through are declared in `ReferenceInterface.jl`.

# ── The shared step AST ───────────────────────────────────────────────────

abstract type RefStep end

"`a.b`, or a bare symbol in path position — a field whose name is a literal."
struct RefField <: RefStep
    name::String
end

"`.field(e)` — a field whose name is the runtime value of `e`."
struct RefFieldExpr <: RefStep
    expr
end

"`xs[i]` — a single element (1-based)."
struct RefIndex <: RefStep
    expr
end

"`xs{k}` — a zero-width cursor position (0-based)."
struct RefPosition <: RefStep
    expr
end

"""
`xs[i, j]` and `xs{s:e}` — a run of a sequence.

`numbering` says which bracket wrote the step, and so how its two numbers read:

  * `:element` — `xs[i, j]`, the elements `i` through `j`, 1-based and
    inclusive. `xs[2, 2]` names what `xs[2]` names.
  * `:gap` — `xs{s:e}`, the gaps `s` and `e` between elements, 0-based, and so
    the run between them. `xs{1:3}` names the second and third elements.

**The bracket says the numbering**, which is the one rule the whole grammar
follows: `[…]` counts elements from 1, and `{…}` counts gaps from 0. A lowerer
converts an `:element` range into the step's own numbering, the way
`ElementReferenceStep` converts `xs[i]`.
"""
struct RefRange <: RefStep
    startexpr
    stopexpr
    numbering::Symbol
end

"""
`::T` — a type step. Always carries a bare `Symbol`.

Whether it *asserts* or *binds* is a lowering choice, not a parse one: `@reference`
splices `T`'s runtime type value, while `@reference_case` reads a capitalized `::T` as an
assertion and a lowercase `::t` as a binder for the node's folded `type` field.
"""
struct RefType <: RefStep
    expr
end

"`^(e)` and `base.^(e)` — splice a runtime path/step into the chain."
struct RefSplice <: RefStep
    expr
end

"`name...` — bind the entire remaining tail. Pattern-only; the builder rejects it."
struct RefTailBind <: RefStep
    name::Symbol
end

"An argument of a `.name(args...)` extension step that is an ordinary value expression."
struct RefArgValue
    expr
end

"""
An argument of a `.name(args...)` extension step that the step declares to be a
**subpath** (via the `get_reference_step_subpath_args` seam). The raw expression is kept: the two
DSLs disagree on what a bare symbol means here — a field to the builder, a whole-path
bind to the matcher — so each applies its own subpath rule at lowering time.
"""
struct RefArgSubPath
    expr
end

"""
`.name(args...)` — an extension step whose type is owned by a higher package and reached
through the `build_reference_step` / `match_reference_step` seams. The parser names no step type it
does not own; it only asks `get_reference_step_subpath_args` which argument positions are subpaths.
"""
struct RefExtension <: RefStep
    name::Symbol
    args::Vector{Any}   # RefArgValue | RefArgSubPath
end

# ── The grammar ───────────────────────────────────────────────────────────
#
# Rootless path forms:
#   address.city
#   items[i].name
#   xs{k}  /  xs{s:e}
#   config.field(fname)
#   rendered.name(args...)   — extension steps registered by higher packages
#   x::T                     — a type step after `x`
#   ^(expr) / base.^(expr)   — splice a runtime path
#   name...                  — bind the remaining tail (patterns only)
#
# Top-level bare symbols in path position are literal field names. Inside `[]`, `{}`,
# `field(...)`, and extension calls, the arguments stay raw Julia expressions — each DSL
# decides what they mean.

"""
    parse_reference_path(ex) -> Vector{RefStep}

Parse a rootless path expression into the shared step AST (left = outermost).
"""
function parse_reference_path(ex)
    steps = RefStep[]
    _parse_ref_path!(steps, ex)
    return steps
end

function _parse_ref_path!(steps::Vector{RefStep}, ex)
    if ex isa Symbol
        # Path-position symbol => literal field name.
        push!(steps, RefField(String(ex)))
        return steps

    elseif ex isa Expr && ex.head == :(::)
        # f::T — the steps of `f`, then the type step. A leading `::T` (no `f`) puts the
        # type step first and the rest of the chain after it.
        if length(ex.args) == 2
            _parse_ref_path!(steps, ex.args[1])
            _ref_type_suffix!(steps, ex.args[2])
        else
            _ref_leading_type!(steps, ex.args[1])
        end
        return steps

    elseif ex isa Expr && ex.head == :. && ex.args[2] isa QuoteNode
        # a.b
        _parse_ref_path!(steps, ex.args[1])
        push!(steps, RefField(String(ex.args[2].value)))
        return steps

    elseif ex isa Expr && ex.head == :ref
        # base[idx] — a single element (1-based), or base[i, j] — elements i through j
        if length(ex.args) == 2
            _parse_ref_path!(steps, ex.args[1])
            push!(steps, RefIndex(ex.args[2]))
        elseif length(ex.args) == 3
            _parse_ref_path!(steps, ex.args[1])
            push!(steps, RefRange(ex.args[2], ex.args[3], :element))
        else
            error("indexing supports 1 or 2 dimensions: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :curly
        # base{idx} — a cursor position (0-based), or base{s:e} — a range
        length(ex.args) == 2 || error("only one-dimensional position is supported: $ex")
        _parse_ref_path!(steps, ex.args[1])
        push!(steps, _ref_braces_step(ex.args[2]))
        return steps

    elseif ex isa Expr && ex.head == :call
        f = ex.args[1]

        if f == :(^)
            # ^(expr) at path position — splice
            length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
            push!(steps, RefSplice(ex.args[2]))
            return steps

        elseif f == :.^ && length(ex.args) == 3
            # `base.^(expr)` — Julia parses this as the binary broadcast `.^`; the DSLs
            # read it as "splice at the end of the chain".
            _parse_ref_path!(steps, ex.args[2])
            push!(steps, RefSplice(ex.args[3]))
            return steps

        elseif f isa Symbol
            # Top-level extension step `name(args...)` with no preceding path.
            push!(steps, _ref_extension_step(f, ex.args[2:end]))
            return steps

        elseif f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            _parse_ref_path!(steps, f.args[1])

            if opname == :field
                length(ex.args) == 2 || error(".field(name) expects exactly one argument: $ex")
                push!(steps, RefFieldExpr(ex.args[2]))
                return steps
            else
                # A mid-path extension step, dispatched through the seam.
                push!(steps, _ref_extension_step(opname, ex.args[2:end]))
                return steps
            end
        else
            error("unsupported call form: $ex")
        end

    elseif ex isa Expr && ex.head == :vect
        # [i] as a relative subpath — a single element (1-based), or [i, j] — elements i through j
        if length(ex.args) == 1
            push!(steps, RefIndex(ex.args[1]))
        elseif length(ex.args) == 2
            push!(steps, RefRange(ex.args[1], ex.args[2], :element))
        else
            error("subpath vector syntax supports 1 or 2 elements: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :braces
        # {i} or {s:e} as a relative subpath
        length(ex.args) == 1 || error("subpath braces syntax supports exactly one element, e.g. {0} or {0:k}: $ex")
        push!(steps, _ref_braces_step(ex.args[1]))
        return steps

    elseif ex isa Expr && ex.head == :...
        # path.name... — the prefix path, then bind the entire remaining tail to `name`.
        # The last step of the prefix must be a field step; its name becomes the variable.
        #
        # Example: [j].rest...  binds j to the index and rest to the tail.
        _parse_ref_path!(steps, ex.args[1])
        isempty(steps) && error("... suffix requires at least one preceding step: $ex")
        last_step = pop!(steps)
        name = if last_step isa RefField
            Symbol(last_step.name)
        elseif last_step isa RefFieldExpr && last_step.expr isa Symbol
            last_step.expr
        else
            error("... suffix only supported after a named field step, got $(typeof(last_step)): $ex")
        end
        push!(steps, RefTailBind(name))
        return steps

    else
        error("unsupported reference syntax: $ex")
    end
end

# Lower the inner expression of a `{...}` to either a position or a range step. Both
# count gaps between elements, from 0, which is what the brace bracket means.
function _ref_braces_step(inner)
    if inner isa Expr && inner.head == :call && length(inner.args) == 3 && inner.args[1] == :(:)
        return RefRange(inner.args[2], inner.args[3], :gap)
    end
    return RefPosition(inner)
end

# A `.name(args...)` / `name(args...)` extension step. Arguments the step declares as
# subpaths (via `get_reference_step_subpath_args`) are tagged as such and kept raw; the rest are
# ordinary value expressions. So the parser names no specific step type — `.proj`'s
# subpath argument is discovered through the seam, keeping the reference layer ignorant
# of the projection concept. A step that registers nothing takes only value arguments,
# which is what the seam answers here for every unregistered name.
get_reference_step_subpath_args(::Val) = ()

function _ref_extension_step(name::Symbol, args)
    subpaths = get_reference_step_subpath_args(Val(name))
    RefExtension(name, Any[(i in subpaths ? RefArgSubPath(a) : RefArgValue(a))
                           for (i, a) in enumerate(args)])
end

# Split a type-step base into its `RefType` and any trailing `.field` steps. A bare
# `Type` yields just the type; a `Type.a.b` chain (which Julia parses as `getfield` on
# the type value) is read as the type `Type` followed by field steps `.a`, `.b` — so a
# mid-path `::T.field` needs no parens.
function _ref_type_and_fields!(steps::Vector{RefStep}, base)
    fields = String[]
    cur = base
    while cur isa Expr && cur.head == :. && cur.args[2] isa QuoteNode
        pushfirst!(fields, String(cur.args[2].value))
        cur = cur.args[1]
    end
    cur isa Symbol ||
        error("type step must start with a type name: $base")
    push!(steps, RefType(cur))
    for f in fields
        push!(steps, RefField(f))
    end
end

# `x::T` type suffix: a bare `T` is the type step; `T{i}` / `T[i]` (which Julia parses as
# a parametric/indexed type) is the type `T` followed by a position/range/element step
# (`value::Leaf{s:e}` needs no parens); `T.field` is the type `T` followed by field steps
# (`entries[i]::Entry.key`).
function _ref_type_suffix!(steps::Vector{RefStep}, T)
    if T isa Expr && T.head == :curly
        _ref_type_and_fields!(steps, T.args[1])
        push!(steps, _ref_braces_step(T.args[2]))
    elseif T isa Expr && T.head == :ref
        _ref_type_and_fields!(steps, T.args[1])
        if length(T.args) == 2
            push!(steps, RefIndex(T.args[2]))
        elseif length(T.args) == 3
            push!(steps, RefRange(T.args[2], T.args[3], :element))
        else
            error("type suffix index supports 1 or 2 dimensions: $T")
        end
    else
        _ref_type_and_fields!(steps, T)
    end
end

# Leading `::X`: a bare symbol is just the type step; a chain like `Node.value{s:e}`
# (which Julia parses entirely under the `::`) is read as the type `Node` followed by the
# `.value{s:e}` steps — so no parens.
function _ref_leading_type!(steps::Vector{RefStep}, X)
    if X isa Symbol
        push!(steps, RefType(X))
    else
        n = length(steps)
        _parse_ref_path!(steps, X)
        root = steps[n + 1]
        root isa RefField ||
            error("leading ::T must start with a type name: $X")
        steps[n + 1] = RefType(Symbol(root.name))
    end
end

# ── The single-step grammar (`@reference_step`) ─────────────────────────────────────

"""
    parse_reference_step(ex) -> RefStep

Parse a one-step expression (the `@reference_step` grammar). Unlike [`parse_reference_path`](@ref),
a leading identifier in front of an operator (`xs[i]`, `xs{k}`, `c.name(...)`) is a
**placeholder** and is dropped; only a bare symbol (`value`) is taken as a field name.
"""
function parse_reference_step(ex)
    if ex isa Symbol
        return RefField(String(ex))
    elseif ex isa Expr && ex.head == :ref
        if length(ex.args) == 2
            return RefIndex(ex.args[2])
        elseif length(ex.args) == 3
            return RefRange(ex.args[2], ex.args[3], :element)
        else
            error("indexing supports 1 or 2 dimensions in @reference_step: $ex")
        end
    elseif ex isa Expr && ex.head == :curly
        length(ex.args) == 2 || error("only one-dimensional position is supported in @reference_step: $ex")
        return _ref_braces_step(ex.args[2])
    elseif ex isa Expr && ex.head == :vect
        if length(ex.args) == 1
            return RefIndex(ex.args[1])
        elseif length(ex.args) == 2
            return RefRange(ex.args[1], ex.args[2], :element)
        else
            error("vector syntax supports 1 or 2 elements in @reference_step: $ex")
        end
    elseif ex isa Expr && ex.head == :braces
        length(ex.args) == 1 || error("braces syntax supports exactly one element in @reference_step: $ex")
        return _ref_braces_step(ex.args[1])
    elseif ex isa Expr && ex.head == :call
        f = ex.args[1]
        if f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            if opname == :field
                length(ex.args) == 2 || error(".field(name) expects exactly one argument in @reference_step: $ex")
                return RefFieldExpr(ex.args[2])
            else
                # A `.name(...)` extension step, dispatched through the seam.
                return _ref_extension_step(opname, ex.args[2:end])
            end
        else
            error("unsupported call form in @reference_step: $ex")
        end
    else
        error("unsupported @reference_step syntax: $ex")
    end
end
