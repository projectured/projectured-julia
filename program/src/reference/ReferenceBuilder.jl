module ReferenceBuilderModule

using ..ReferenceModule
export @reference

# ------------------------------------------------------------
# Parsing for constructor DSL
#
# Rootless forms:
#   address.city
#   items[i].name
#   config.field(fname)
#   cursor.point(x, y)
#   rendered.proj(p, [0])
#   rendered.proj(p, token[i])
#
# Semantics:
#   - top-level bare symbols in path position are literal field names
#   - inside [expr], field(expr), point(x,y), proj(p, path), arguments are
#     ordinary Julia expressions that get evaluated at runtime
# ------------------------------------------------------------

abstract type BuildStep end

struct BSField <: BuildStep
    nameexpr
end

struct BSIndex <: BuildStep
    idxexpr
end

struct BSPosition <: BuildStep
    idxexpr
end

struct BSRange <: BuildStep
    startexpr
    stopexpr
end

struct BSPoint <: BuildStep
    xexpr
    yexpr
end

struct BSProjection <: BuildStep
    projexpr
    outpath::Vector{BuildStep}
end

struct BSPathSplice <: BuildStep
    expr
end

function _parse_build_path(ex)
    steps = BuildStep[]
    _parse_build_path!(steps, ex)
    return steps
end

function _parse_build_path!(steps::Vector{BuildStep}, ex)
    if ex isa Symbol
        # Path-position symbol => literal field name
        push!(steps, BSField(String(ex)))
        return steps

    elseif ex isa Expr && ex.head == :. && ex.args[2] isa QuoteNode
        # a.b
        _parse_build_path!(steps, ex.args[1])
        push!(steps, BSField(String(ex.args[2].value)))
        return steps

    elseif ex isa Expr && ex.head == :ref
        # base[idx] — ElementReference (1-based), or base[i, j] — RangeReference
        if length(ex.args) == 2
            _parse_build_path!(steps, ex.args[1])
            push!(steps, BSIndex(ex.args[2]))
        elseif length(ex.args) == 3
            _parse_build_path!(steps, ex.args[1])
            push!(steps, BSRange(ex.args[2], ex.args[3]))
        else
            error("indexing supports 1 or 2 dimensions in @reference: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :curly
        # base{idx} — PositionReference (0-based)
        length(ex.args) == 2 || error("only one-dimensional position is supported in @reference: $ex")
        _parse_build_path!(steps, ex.args[1])
        push!(steps, BSPosition(ex.args[2]))
        return steps

    elseif ex isa Expr && ex.head == :call
        f = ex.args[1]

        if f == :proj
            # Top-level: proj(projection, subpath)
            length(ex.args) == 3 || error(".proj(projection, outpath) expects exactly two arguments: $ex")
            push!(steps, BSProjection(ex.args[2], _parse_build_subpath(ex.args[3])))
            return steps

        elseif f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            _parse_build_path!(steps, f.args[1])

            if opname == :field
                length(ex.args) == 2 || error(".field(name) expects exactly one argument")
                push!(steps, BSField(ex.args[2]))
                return steps

            elseif opname == :point
                length(ex.args) == 3 || error(".point(x, y) expects exactly two arguments")
                push!(steps, BSPoint(ex.args[2], ex.args[3]))
                return steps

            elseif opname == :proj
                length(ex.args) == 3 || error(".proj(projection, outpath) expects exactly two arguments")
                push!(steps, BSProjection(ex.args[2], _parse_build_subpath(ex.args[3])))
                return steps

            else
                error("unsupported path operation .$opname(...) in @reference: $ex")
            end
        else
            error("unsupported call form in @reference: $ex")
        end

    elseif ex isa Expr && ex.head == :vect
        # [i] as a relative subpath — ElementReference (1-based), or [i, j] — RangeReference
        if length(ex.args) == 1
            push!(steps, BSIndex(ex.args[1]))
        elseif length(ex.args) == 2
            push!(steps, BSRange(ex.args[1], ex.args[2]))
        else
            error("subpath vector syntax supports 1 or 2 elements in @reference: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :braces
        # {i} as a relative subpath — PositionReference (0-based)
        length(ex.args) == 1 || error("subpath braces syntax supports exactly one element, e.g. {0} or {k}: $ex")
        push!(steps, BSPosition(ex.args[1]))
        return steps

    else
        error("unsupported @reference syntax: $ex")
    end
end

function _parse_build_subpath(ex)
    # ^(expr) splices an already-computed ReferencePath directly
    if ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
        return BuildStep[BSPathSplice(ex.args[2])]
    end
    return _parse_build_path(ex)
end

# ------------------------------------------------------------
# Code generation
# ------------------------------------------------------------

function _gen_build_step(step::BSField)
    nameex = step.nameexpr isa String ? QuoteNode(step.nameexpr) : esc(step.nameexpr)
    return :(ReferenceModule.FieldReference(String($nameex)))
end

function _gen_build_step(step::BSIndex)
    return :(ReferenceModule.ElementReference(Int($(esc(step.idxexpr)))))
end

function _gen_build_step(step::BSPosition)
    return :(ReferenceModule.PositionReference(Int($(esc(step.idxexpr)))))
end

function _gen_build_step(step::BSRange)
    return :(ReferenceModule.RangeReference(Int($(esc(step.startexpr))), Int($(esc(step.stopexpr)))))
end

function _gen_build_step(step::BSPoint)
    return :(ReferenceModule.PointReference(Int($(esc(step.xexpr))), Int($(esc(step.yexpr)))))
end

function _gen_build_step(step::BSPathSplice)
    return esc(step.expr)
end

function _gen_build_step(step::BSProjection)
    projex = esc(step.projexpr)
    outpathex = _gen_build_path(step.outpath)
    return :(ReferenceModule.ProjectionReference($projex, $outpathex))
end

function _gen_build_path(steps::Vector{BuildStep})
    if length(steps) == 1 && steps[1] isa BSPathSplice
        return _gen_build_step(steps[1])
    end
    stepexprs = [_gen_build_step(s) for s in steps]
    return :(ReferenceModule.ReferencePath($(stepexprs...)))
end

macro reference()
    return _gen_build_path(BuildStep[])
end

macro reference(ex)
    steps = _parse_build_path(ex)
    return _gen_build_path(steps)
end

end