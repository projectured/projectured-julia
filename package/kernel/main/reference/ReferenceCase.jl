# Fragment of `ReferenceModule` — the `@reference_case` pattern-matching DSL,
# the destructuring counterpart of the `@reference` construction DSL
# (`ReferenceBuilder.jl`). Both DSLs are siblings that share the reference-type
# vocabulary from `Reference.jl` and live in the same module, since they are
# only ever imported together.

"""
    when(pattern, condition)

Surface syntax helper recognized only inside `@reference_case`.

Example:
    @reference_case r begin
        when(items[i].name, i > 0) => ("later", i)
    end
"""
when(pattern, condition) = error("when() is only valid inside @reference_case")
prefix(path) = error("prefix() is only valid inside @reference_case")

# ------------------------------------------------------------
# Pattern representation
# ------------------------------------------------------------

abstract type PatValue end

struct PVWildcard <: PatValue end

struct PVBind <: PatValue
    name::Symbol
end

struct PVTypedBind <: PatValue
    name::Symbol
    ty
end

struct PVLiteral <: PatValue
    value
end

struct PVInterp <: PatValue
    expr
end

abstract type PatStep end

struct PSField <: PatStep
    namepat::PatValue   # matches FieldReference.name[] :: String
end

struct PSIndex <: PatStep
    idxpat::PatValue    # matches a single-element RangeReference; 1-based index = start + 1
end

struct PSPosition <: PatStep
    idxpat::PatValue    # matches a zero-width RangeReference (a cursor position); 0-based = start
end

struct PSRange <: PatStep
    startpat::PatValue
    stoppat::PatValue
end

# A `.name(patterns...)` DSL pattern whose step type is registered by dispatch
# on `dsl_match_step(::Val{name}, hex, argpats, rest_success, bound)`. Kernel-
# owned entries (`.point`, `.proj`) register in this file; higher packages
# register their own.
struct PSExtension <: PatStep
    name::Symbol
    argpats::Vector{Any}   # per-arg PatValue or Vector{PatStep} (subpath)
end

struct PSWholePathBind <: PatStep
    name::Symbol
end

# A type assertion in a pattern: `f::T` matches `f`'s steps, then asserts the
# folded `type` field of the node reached is a subtype of `T` (non-navigating).
# The assertion is optional — an unknown (`nothing`) node type still matches — so
# patterns that omit `::T`, and skeleton/skip-bound recursion tails, keep matching.
struct PSType <: PatStep
    typeexpr
end

struct PSPathInterp <: PatStep
    expr
end

# ------------------------------------------------------------
# Value-pattern parsing
# ------------------------------------------------------------

function _parse_value(ex)
    if ex === :_
        return PVWildcard()
    elseif ex isa Symbol
        return PVBind(ex)
    elseif ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        return PVInterp(ex.args[2])
    elseif ex isa Expr && ex.head == :(::) && ex.args[1] isa Symbol
        return PVTypedBind(ex.args[1], ex.args[2])
    elseif ex isa QuoteNode
        return PVLiteral(ex.value)
    elseif ex isa String || ex isa Int || ex isa Bool || ex isa Char
        return PVLiteral(ex)
    else
        # Fall back to interpolation for arbitrary expressions.
        return PVInterp(ex)
    end
end

# ------------------------------------------------------------
# Path parsing
#
# Rootless rules:
#   address.city
#   items[i].name
#   config.field(f)
#   cursor.point(x, y)
#   rendered.proj(p, [0])
#   rendered.proj(p, token[i])
#
# Top-level bare symbols in path position are literal field names.
# Bare symbols in value position (inside [] or field(...)) are binders.
# ------------------------------------------------------------

function _parse_path(ex)
    steps = PatStep[]
    _parse_path!(steps, ex)
    return steps
end

# Parse a relative path expression and append steps to `steps`.
function _parse_path!(steps::Vector{PatStep}, ex)
    if ex isa Symbol
        # Top-level / path-position symbol means a literal field step.
        push!(steps, PSField(PVLiteral(String(ex))))
        return steps

    elseif ex isa Expr && ex.head == :(::)
        # f::T — match f's steps then a TypeReference(T) checkpoint.
        # A leading `::T` (no `f`) matches the checkpoint then the rest of the chain.
        if length(ex.args) == 2
            _parse_path!(steps, ex.args[1])
            _pat_type_suffix!(steps, ex.args[2])
        else
            _pat_leading_type!(steps, ex.args[1])
        end
        return steps

    elseif ex isa Expr && ex.head == :. && ex.args[2] isa QuoteNode
        # a.b
        _parse_path!(steps, ex.args[1])
        push!(steps, PSField(PVLiteral(String(ex.args[2].value))))
        return steps

    elseif ex isa Expr && ex.head == :ref
        # base[idx] — ElementReference (1-based), or base[i, j] — RangeReference
        if length(ex.args) == 2
            _parse_path!(steps, ex.args[1])
            push!(steps, PSIndex(_parse_value(ex.args[2])))
        elseif length(ex.args) == 3
            _parse_path!(steps, ex.args[1])
            push!(steps, PSRange(_parse_value(ex.args[2]), _parse_value(ex.args[3])))
        else
            error("indexing patterns support 1 or 2 dimensions: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :curly
        # base{idx} — PositionReference (0-based), or base{s:e} — RangeReference
        length(ex.args) == 2 || error("only one-dimensional position patterns are supported: $ex")
        _parse_path!(steps, ex.args[1])
        push!(steps, _braces_pat(ex.args[2]))
        return steps

    elseif ex isa Expr && ex.head == :call
        f = ex.args[1]

        if f == :proj
            # Top-level: proj(projpat, subpath) — dispatched through the
            # extension seam.
            length(ex.args) == 3 || error("proj(projpat, outpath) expects exactly two arguments: $ex")
            push!(steps, PSExtension(:proj, Any[_parse_value(ex.args[2]), _parse_subpath(ex.args[3])]))
            return steps

        elseif f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            _parse_path!(steps, f.args[1])

            if opname == :field
                length(ex.args) == 2 || error(".field(...) expects exactly one argument")
                push!(steps, PSField(_parse_value(ex.args[2])))
                return steps

            elseif opname == :proj
                length(ex.args) == 3 || error(".proj(projpat, outpath) expects exactly two arguments")
                push!(steps, PSExtension(:proj, Any[_parse_value(ex.args[2]), _parse_subpath(ex.args[3])]))
                return steps

            else
                # Everything else is dispatched through the extension seam.
                push!(steps, PSExtension(opname, Any[_parse_value(a) for a in ex.args[2:end]]))
                return steps
            end
        elseif f == :(^)
            length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
            push!(steps, PSPathInterp(ex.args[2]))
            return steps

        else
            error("unsupported call form in path pattern: $ex")
        end

    elseif ex isa Expr && ex.head == :vect
        # [i] as a relative subpath — ElementReference (1-based), or [i, j] — RangeReference
        if length(ex.args) == 1
            push!(steps, PSIndex(_parse_value(ex.args[1])))
        elseif length(ex.args) == 2
            push!(steps, PSRange(_parse_value(ex.args[1]), _parse_value(ex.args[2])))
        else
            error("subpath vector syntax supports 1 or 2 elements: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :braces
        # {i} or {s:e} as a relative subpath
        length(ex.args) == 1 || error("subpath braces syntax supports exactly one element, e.g. {0} or {0:k}: $ex")
        push!(steps, _braces_pat(ex.args[1]))
        return steps

    elseif ex isa Expr && ex.head == :...
        # path.name... — match the prefix path and bind the entire remaining
        # tail to `name`.  The last step of the prefix must be a field step
        # whose name becomes the binding variable.
        #
        # Example: [j].rest...  binds j to the index and rest to the tail.
        _parse_path!(steps, ex.args[1])
        isempty(steps) && error("... suffix requires at least one preceding step: $ex")
        last_step = pop!(steps)
        name = if last_step isa PSField && last_step.namepat isa PVLiteral
            Symbol(last_step.namepat.value::String)
        elseif last_step isa PSField && last_step.namepat isa PVBind
            last_step.namepat.name
        else
            error("... suffix only supported after a named field step, got $(typeof(last_step)): $ex")
        end
        push!(steps, PSWholePathBind(name))
        return steps

    else
        error("unsupported path pattern syntax: $ex")
    end
end

function _parse_subpath(ex)
    ex isa Symbol && return PatStep[PSWholePathBind(ex)]
    return _parse_path(ex)
end

# `x::T` type suffix in a pattern: bare `T` is a checkpoint; `T{i}`/`T[i]` is read
# as checkpoint `T` then a position/range/element step (so `value::Leaf{s:e}`
# needs no parens).
function _pat_type_suffix!(steps::Vector{PatStep}, T)
    if T isa Expr && T.head == :curly
        push!(steps, PSType(T.args[1]))
        push!(steps, _braces_pat(T.args[2]))
    elseif T isa Expr && T.head == :ref
        push!(steps, PSType(T.args[1]))
        if length(T.args) == 2
            push!(steps, PSIndex(_parse_value(T.args[2])))
        elseif length(T.args) == 3
            push!(steps, PSRange(_parse_value(T.args[2]), _parse_value(T.args[3])))
        else
            error("type suffix index supports 1 or 2 dimensions: $T")
        end
    else
        push!(steps, PSType(T))
    end
end

# Leading `::X`: a bare symbol is the checkpoint; a chain like `Node.entries{s:e}`
# is read as checkpoint `Node` then the `.entries{s:e}` steps (no parens).
function _pat_leading_type!(steps::Vector{PatStep}, X)
    if X isa Symbol
        push!(steps, PSType(X))
    else
        n = length(steps)
        _parse_path!(steps, X)
        root = steps[n + 1]
        (root isa PSField && root.namepat isa PVLiteral && root.namepat.value isa String) ||
            error("leading ::T must start with a type name: $X")
        steps[n + 1] = PSType(Symbol(root.namepat.value))
    end
end

# Lower the inner expression of a `{...}` pattern to either a position or
# range step.
function _braces_pat(inner)
    if inner isa Expr && inner.head == :call && length(inner.args) == 3 && inner.args[1] == :(:)
        return PSRange(_parse_value(inner.args[2]), _parse_value(inner.args[3]))
    end
    return PSPosition(_parse_value(inner))
end

# ------------------------------------------------------------
# Rule parsing
# ------------------------------------------------------------

function _parse_rule(ex)
    ex isa Expr && ex.head == :call && ex.args[1] == :(=>) ||
        error("expected `pattern => result`, got: $ex")

    lhs, rhs = ex.args[2], ex.args[3]

    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 || error("when(pattern, cond) expects exactly two arguments")
        inner_lhs = lhs.args[2]
        cond = lhs.args[3]
        if inner_lhs isa Expr && inner_lhs.head == :call && inner_lhs.args[1] == :prefix
            length(inner_lhs.args) == 2 || error("prefix(path) expects exactly one argument")
            pat = _parse_path(inner_lhs.args[2])
            return (:prefix, pat, cond, rhs)
        else
            pat = _parse_path(inner_lhs)
            return (:exact, pat, cond, rhs)
        end
    elseif lhs isa Expr && lhs.head == :call && lhs.args[1] == :prefix
        length(lhs.args) == 2 || error("prefix(path) expects exactly one argument")
        pat = _parse_path(lhs.args[2])
        return (:prefix, pat, nothing, rhs)
    elseif lhs === :_
        pat = PatStep[PSWholePathBind(:_)]
        return (:exact, pat, nothing, rhs)
    elseif lhs === :∅
        # Empty-path pattern: matches a reference that terminates *at* the
        # element itself — a whole-element ("tree") selection. Compiles to a
        # zero-step exact match (`_ref_input isa EmptyReferencePath`). This only
        # adds a writable pattern; the no-match fallthrough is still `nothing`.
        return (:exact, PatStep[], nothing, rhs)
    else
        pat = _parse_path(lhs)
        return (:exact, pat, nothing, rhs)
    end
end

# ------------------------------------------------------------
# Code generation helpers
# ------------------------------------------------------------

# Returns (expr, boundnames)
#
# `expr` evaluates either to `success` or to `_nomatch`.
function _gen_value_match(valex, pat::PVWildcard, success, bound::Set{Symbol})
    return success, bound
end

function _gen_value_match(valex, pat::PVLiteral, success, bound::Set{Symbol})
    lit = pat.value
    return :($valex == $(QuoteNode(lit)) ? $success : _nomatch), bound
end

function _gen_value_match(valex, pat::PVInterp, success, bound::Set{Symbol})
    return :($valex == $(esc(pat.expr)) ? $success : _nomatch), bound
end

function _gen_value_match(valex, pat::PVBind, success, bound::Set{Symbol})
    name = pat.name
    if name in bound
        return :($valex == $(esc(name)) ? $success : _nomatch), bound
    else
        return :(let $(esc(name)) = $valex
                     $success
                 end), union(bound, Set([name]))
    end
end

function _gen_value_match(valex, pat::PVTypedBind, success, bound::Set{Symbol})
    name = pat.name
    ty = esc(pat.ty)
    if name in bound
        return :(($valex isa $ty && $valex == $(esc(name))) ? $success : _nomatch), bound
    else
        return :(if $valex isa $ty
                     let $(esc(name)) = $valex
                         $success
                     end
                 else
                     _nomatch
                 end), union(bound, Set([name]))
    end
end

# No `_gen_step_match(::PSType, …)`: a `PSType` is always intercepted at the top of
# `_gen_path_match` / `_gen_prefix_match` (which handle the optional, tolerant type
# assertion) before per-step dispatch is ever reached, so a step method would be
# dead code. Every step reaches position 1 in the recursion, so this holds for
# `PSType` anywhere in a pattern.

function _gen_step_match(hex, tex, step::PSField, rest_success, bound::Set{Symbol})
    nameexpr = :($hex.name)
    inner, bound2 = _gen_value_match(nameexpr, step.namepat, rest_success, bound)

    ex = quote
        if $hex isa ReferenceModule.FieldReference
            $inner
        else
            _nomatch
        end
    end
    return ex, bound2
end

function _gen_step_match(hex, tex, step::PSIndex, rest_success, bound::Set{Symbol})
    idxexpr = :($hex.start + 1)
    inner, bound2 = _gen_value_match(idxexpr, step.idxpat, rest_success, bound)

    ex = quote
        if $hex isa ReferenceModule.RangeReference && ReferenceModule.is_element_reference($hex)
            $inner
        else
            _nomatch
        end
    end
    return ex, bound2
end

function _gen_step_match(hex, tex, step::PSPosition, rest_success, bound::Set{Symbol})
    idxexpr = :($hex.start)
    inner, bound2 = _gen_value_match(idxexpr, step.idxpat, rest_success, bound)

    ex = quote
        if $hex isa ReferenceModule.RangeReference && ReferenceModule.is_position_reference($hex)
            $inner
        else
            _nomatch
        end
    end
    return ex, bound2
end

function _gen_step_match(hex, tex, step::PSRange, rest_success, bound::Set{Symbol})
    startexpr = :($hex.start)
    stopexpr = :($hex.stop)

    inner2, bound2 = _gen_value_match(stopexpr, step.stoppat, rest_success, bound)
    inner1, bound1 = _gen_value_match(startexpr, step.startpat, inner2, bound2)

    ex = quote
        if $hex isa ReferenceModule.RangeReference
            $inner1
        else
            _nomatch
        end
    end
    return ex, bound1
end

function _gen_step_match(hex, tex, step::PSExtension, rest_success, bound::Set{Symbol})
    dsl_match_step(Val(step.name), hex, step.argpats, rest_success, bound,
                   _gen_value_match, _gen_path_match)
end

"""
    dsl_match_step(::Val{name}, hex, argpats, rest_success, bound,
                   gen_value_match, gen_path_match) -> (Expr, Set{Symbol})

Return `(match_branch, updated_bound)` for a `.name(patterns...)` pattern in the
`@reference_case` DSL. `hex` is the expression bound to the current step, and
`argpats` is the vector of parsed patterns (each a `PatValue` for a value
argument, or a `Vector{PatStep}` for a subpath argument). `gen_value_match`
and `gen_path_match` are helper callbacks the caller passes in so extension
methods can generate value/path patterns without reaching into kernel
internals: their signatures are

    gen_value_match(expr, pat, rest_success, bound) -> (Expr, Set{Symbol})
    gen_path_match(path_expr, patsteps, success, bound) -> (Expr, Set{Symbol})

Each package registers a `::Val{:name}` method for its own step types; the
kernel's own `.point` and `.proj` entries live in this file.
"""
function dsl_match_step end

dsl_match_step(::Val{n}, hex, argpats, rest_success, bound, gvm, gpm) where {n} =
    error("no `dsl_match_step(::Val{$(QuoteNode(n))}, …)` method registered — `.$(n)(…)` is not a known @reference_case step")

# No kernel-registered `.name(...)` DSL entries — the cross-package step
# types (`.point`, `.proj`, …) register their own `dsl_match_step` at the
# package that owns them.

function _gen_path_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}())
    # Folded references expose a navigation step directly as `head` (the type is a
    # node field), so patterns written against the navigation skeleton match the
    # path as-is — there are no interleaved checkpoint steps to skip.
    if isempty(steps)
        return :(($path_ex isa ReferenceModule.EmptyReferencePath) ? $success : _nomatch), bound
    end

    if length(steps) == 1 && steps[1] isa PSWholePathBind
        name = steps[1].name
        return :(let $(esc(name)) = $path_ex; $success end), union(bound, Set([name]))
    end

    # A leading `::T` is an OPTIONAL, non-navigating, *tolerant* assertion: it
    # documents the expected node type but never causes a match to fail, so a
    # pattern keeps matching whatever path reaches it (folded with any node type,
    # a plain skeleton, or a skip-bound recursion tail). Matching the rest stays on
    # the SAME path for a folded node (the type is a field, consuming no step) and
    # advances past an unfolded `TypeReference` *step* if one is present. (An
    # enforcing `<: T` gate here wrongly rejects re-rooted child selections whose
    # folded node type differs from the documented one.)
    if steps[1] isa PSType
        sp = gensym(:sp)
        rest_on_tail, b1 = _gen_path_match(:(ReferenceModule.tail($sp)), steps[2:end], success, bound)
        rest_on_same, b2 = _gen_path_match(sp, steps[2:end], success, bound)
        ex = quote
            let $sp = $path_ex
                if $sp isa ReferenceModule.ConcreteReferencePath && ReferenceModule.head($sp) isa ReferenceModule.TypeReference
                    $rest_on_tail
                else
                    $rest_on_same
                end
            end
        end
        return ex, union(b1, b2)
    end

    if length(steps) == 1 && steps[1] isa PSPathInterp
        expr = esc(steps[1].expr)
        return :(ReferenceModule.is_reference_equal_ignoring_types($path_ex, $expr) ? $success : _nomatch), bound
    end

    p = gensym(:p)
    h = gensym(:h)
    t = gensym(:t)

    rest_success, bound1 = _gen_path_match(t, steps[2:end], success, bound)
    step_success, bound2 = _gen_step_match(h, t, steps[1], rest_success, bound1)

    ex = quote
        let $p = $path_ex
            if $p isa ReferenceModule.ConcreteReferencePath
                let $h = ReferenceModule.head($p),
                    $t = ReferenceModule.tail($p)
                    $step_success
                end
            else
                _nomatch
            end
        end
    end

    return ex, bound2
end

function _gen_prefix_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}())
    if isempty(steps)
        return :(_nomatch), bound
    end

    if length(steps) == 1 && steps[1] isa PSPathInterp
        expr = esc(steps[1].expr)
        return :(ReferenceModule.is_prefix_of_ignoring_types($path_ex, $expr) ? $success : _nomatch), bound
    end

    # A leading `::T` is a non-navigating, optional, *tolerant* type assertion
    # (same as in `_gen_path_match`): it never fails a match, advancing past an
    # unfolded `TypeReference` *step* if present, else matching on the same path.
    if steps[1] isa PSType
        sp = gensym(:sp)
        rest_on_tail, b1 = _gen_prefix_match(:(ReferenceModule.tail($sp)), steps[2:end], success, bound)
        rest_on_same, b2 = _gen_prefix_match(sp, steps[2:end], success, bound)
        ex = quote
            let $sp = $path_ex
                if $sp isa ReferenceModule.ConcreteReferencePath && ReferenceModule.head($sp) isa ReferenceModule.TypeReference
                    $rest_on_tail
                else
                    $rest_on_same
                end
            end
        end
        return ex, union(b1, b2)
    end

    p = gensym(:p)
    h = gensym(:h)
    t = gensym(:t)

    rest_match, bound1 = _gen_prefix_match(t, steps[2:end], success, bound)
    step_match, bound2 = _gen_step_match(h, t, steps[1], rest_match, bound1)

    ex = quote
        let $p = $path_ex
            if $p isa ReferenceModule.EmptyReferencePath
                $success
            elseif $p isa ReferenceModule.ConcreteReferencePath
                let $h = ReferenceModule.head($p),
                    $t = ReferenceModule.tail($p)
                    $step_match
                end
            else
                _nomatch
            end
        end
    end

    return ex, bound2
end

function _gen_rule(rule)
    mode, pat, cond, rhs = rule

    body =
        cond === nothing ?
        esc(rhs) :
        :(if $(esc(cond))
              $(esc(rhs))
          else
              _nomatch
          end)

    if mode == :prefix
        ex, _ = _gen_prefix_match(:_ref_input, pat, body, Set{Symbol}())
    else
        ex, _ = _gen_path_match(:_ref_input, pat, body, Set{Symbol}())
    end
    return ex
end

# ------------------------------------------------------------
# Macro entry point
# ------------------------------------------------------------

"""
    @reference_case ref begin
        pattern => result
        ...
    end

Match the reference path `ref` against each `pattern => result` rule in order and
return the `result` of the first that matches, or `nothing` if none do. Patterns
use the same step grammar as `@reference` (`a.b`, `xs[i]`, `xs{k}`, `.proj(p, sub)`,
a leading/suffix `::T` checkpoint, …), with these matching conventions:

- Bare symbols in *path* position are literal field names; bare symbols in *value*
  position (inside `[]`, `field(...)`, …) **bind** the matched value.
- `_` is a wildcard; `name::T` binds `name` only if the value `isa T`; `^(expr)`
  interpolates a value to compare against.
- `when(pattern, cond)` matches `pattern` then requires the guard `cond` (which may
  read the pattern's bindings); `prefix(pattern)` matches a leading prefix rather
  than the whole path; `name...` binds the entire remaining tail; `∅` matches the
  empty (whole-element) path.

A `::T` checkpoint is a **tolerant** assertion: it documents the expected node
type but never fails a match, so a pattern keeps matching whether the path carries
folded node types or is a plain skeleton.
"""
macro reference_case(ref, block)
    entries =
        block isa Expr && block.head == :block ? block.args :
        [block]

    rules = [_parse_rule(e) for e in entries if !(e isa LineNumberNode)]

    chain = :nothing
    for rule in reverse(rules)
        rule_ex = _gen_rule(rule)
        chain = quote
            let _ref_input = $(esc(ref))
                let _m = $rule_ex
                    _m === _nomatch ? $chain : _m
                end
            end
        end
    end

    return quote
        let _nomatch = Base.RefValue{Any}()
            $chain
        end
    end
end