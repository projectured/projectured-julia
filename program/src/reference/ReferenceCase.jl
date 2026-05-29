module ReferenceCaseModule

using ..ReferenceModule
export @reference_case, when, prefix

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
    idxpat::PatValue    # matches ElementReference.index[] :: Int
end

struct PSPosition <: PatStep
    idxpat::PatValue    # matches PositionReference.index[] :: Int
end

struct PSRange <: PatStep
    startpat::PatValue
    stoppat::PatValue
end

struct PSPoint <: PatStep
    xpat::PatValue
    ypat::PatValue
end

struct PSProjection <: PatStep
    projpat::PatValue
    outpath::Vector{PatStep}
end

struct PSWholePathBind <: PatStep
    name::Symbol
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
            # Top-level: proj(projpat, subpath)
            length(ex.args) == 3 || error("proj(projpat, outpath) expects exactly two arguments: $ex")
            push!(steps, PSProjection(_parse_value(ex.args[2]), _parse_subpath(ex.args[3])))
            return steps

        elseif f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            _parse_path!(steps, f.args[1])

            if opname == :field
                length(ex.args) == 2 || error(".field(...) expects exactly one argument")
                push!(steps, PSField(_parse_value(ex.args[2])))
                return steps

            elseif opname == :point
                length(ex.args) == 3 || error(".point(x, y) expects exactly two arguments")
                push!(steps, PSPoint(_parse_value(ex.args[2]), _parse_value(ex.args[3])))
                return steps

            elseif opname == :proj
                length(ex.args) == 3 || error(".proj(projpat, outpath) expects exactly two arguments")
                push!(steps, PSProjection(_parse_value(ex.args[2]), _parse_subpath(ex.args[3])))
                return steps

            else
                error("unsupported path operation .$opname(...) in pattern: $ex")
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

function _gen_step_match(hex, tex, step::PSPoint, rest_success, bound::Set{Symbol})
    xexpr = :($hex.x)
    yexpr = :($hex.y)

    inner2, bound2 = _gen_value_match(yexpr, step.ypat, rest_success, bound)
    inner1, bound1 = _gen_value_match(xexpr, step.xpat, inner2, bound2)

    ex = quote
        if $hex isa ReferenceModule.PointReference
            $inner1
        else
            _nomatch
        end
    end
    return ex, bound1
end

function _gen_step_match(hex, tex, step::PSProjection, rest_success, bound::Set{Symbol})
    projexpr = :($hex.projection)
    outpathexpr = :($hex.output_path)

    after_out, bound2 = _gen_path_match(outpathexpr, step.outpath, rest_success, bound)
    after_proj, bound1 = _gen_value_match(projexpr, step.projpat, after_out, bound2)

    ex = quote
        if $hex isa ReferenceModule.ProjectionReference
            $after_proj
        else
            _nomatch
        end
    end
    return ex, bound1
end

function _gen_path_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}())
    if isempty(steps)
        return :(($path_ex isa ReferenceModule.EmptyReferencePath) ? $success : _nomatch), bound
    end

    if length(steps) == 1 && steps[1] isa PSWholePathBind
        name = steps[1].name
        return :(let $(esc(name)) = $path_ex; $success end), union(bound, Set([name]))
    end

    if length(steps) == 1 && steps[1] isa PSPathInterp
        expr = esc(steps[1].expr)
        return :(ReferenceModule.reference_equal($path_ex, $expr) ? $success : _nomatch), bound
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
        return :(ReferenceModule.is_prefix_of($path_ex, $expr) ? $success : _nomatch), bound
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

end