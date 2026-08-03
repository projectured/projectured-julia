"""
    JuliaFileModule

`JuliaFile`: a `FileDocument` whose `content` is a `JuliaDocument`
(the projectured Julia AST from `JuliaModule`). Parse uses the
existing `juliaparse`; emit runs the standard `JuliaToSyntax →
SyntaxToText → TextToString` projection chain via `document_to_text`.

**Marker syntax in Julia source.** A cross-file reference reads as a
call to a specially-named function:

    pred_ref("<<file(\\"child.jl\\")>>")

The projectured Julia parser doesn't handle macro syntax (`@ref …`)
but does handle a plain call, so we use a call to an ordinary
identifier `pred_ref` whose single argument is the full marker text
string (`<<file(\"path\")>>`). Load walks the AST for
`JuliaCall(JuliaIdentifier("pred_ref"), [JuliaString])` and rewrites
each such call slot with a `ReferenceStub`. Emit is symmetric via
the projection extension (see `JuliaToSyntax.jl`), so no pre-save
AST mutation is required.
"""
module JuliaFileModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..CollectionModule: CellVector, ComputedCellVector
import ..JuliaModule: JuliaDocument, JuliaNothing, JuliaCall, JuliaIdentifier,
                      JuliaString, JuliaBlock, JuliaArray, JuliaTuple, JuliaBinaryOp,
                      JuliaUnaryOp, JuliaIndex, JuliaFieldAccess, JuliaRange,
                      JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator,
                      JuliaWhile, JuliaReturn, JuliaTry, JuliaBegin, JuliaIf,
                      JuliaFunction, JuliaLambda, JuliaTernary
import ..JuliaParserModule: juliaparse
import ..NaturalFormatModule: document_to_text
import ..FileProjectModule: FileDocument, emit_text, populate_file!, content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!

export JuliaFile, PRED_REF_FUNCTION_NAME

"""
The identifier used to encode a cross-file marker as a Julia call
expression: `pred_ref("<<file(\\"path\\")>>")`.
"""
const PRED_REF_FUNCTION_NAME = "pred_ref"

"""
    JuliaFile(filename, content)

A file document whose `content` is a `JuliaDocument`. See the module
docstring for the `pred_ref(...)` marker convention.
"""
@document struct JuliaFile <: FileDocument
    filename::String
    content::JuliaDocument = JuliaNothing()
end

emit_text(f::JuliaFile) = document_to_text(content(f))

function populate_file!(f::JuliaFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = juliaparse(text)
    ast = _substitute_markers(ast, ctx)
    getfield(f, :content)[] = ast
    f
end

# Recognise a marker call: `pred_ref("<<file(\"path\")>>")` — a
# JuliaCall whose callee is a JuliaIdentifier named `pred_ref` and
# whose single argument is a JuliaString.
function _is_marker_call(node::JuliaCall)
    callee = node.callee
    callee isa JuliaIdentifier || return false
    callee.name == PRED_REF_FUNCTION_NAME || return false
    args = getfield(node, :arguments)[]
    length(args) == 1 || return false
    arg = args[1] isa Cell ? args[1][] : args[1]
    arg isa JuliaString
end

_marker_stub(node::JuliaCall, ctx::LoaderContext) = begin
    args = getfield(node, :arguments)[]
    s = args[1] isa Cell ? args[1][] : args[1]
    ref = parse_marker_text(s.value)
    ref === nothing ? node : ReferenceStub(ref, ctx)
end

# Traversal — mutates `Document`-typed slot cells in place, rebuilds
# nothing. Any slot whose current value is a marker call swaps to a
# ReferenceStub with `ctx`.
_substitute_markers(node, ctx::LoaderContext) = node

function _substitute_markers(node::JuliaCall, ctx::LoaderContext)
    # First recurse into callee + arguments so a marker inside them
    # (arguments passed to a real call) is still lifted.
    getfield(node, :callee)[] = _substitute_markers(node.callee, ctx)
    v = getfield(node, :arguments)[]
    for i in eachindex(v)
        v[i] = _substitute_markers(v[i], ctx)
    end
    _is_marker_call(node) ? _marker_stub(node, ctx) : node
end

# A generic in-place descent for the compound Julia AST types.
# Documented shape: mutate any `Document`-typed field's cell to the
# substituted value; recurse into any `CellVector` field's elements.
function _substitute_children!(node, ctx::LoaderContext, doc_fields, vec_fields)
    for name in doc_fields
        current = getfield(node, name)[]
        current isa Nothing && continue
        getfield(node, name)[] = _substitute_markers(current, ctx)
    end
    for name in vec_fields
        v = getfield(node, name)[]
        for i in eachindex(v)
            v[i] = _substitute_markers(v[i], ctx)
        end
    end
    node
end

_substitute_markers(n::JuliaBlock, ctx::LoaderContext)          = _substitute_children!(n, ctx, (),                       (:statements,))
_substitute_markers(n::JuliaArray, ctx::LoaderContext)          = _substitute_children!(n, ctx, (),                       (:elements,))
_substitute_markers(n::JuliaTuple, ctx::LoaderContext)          = _substitute_children!(n, ctx, (),                       (:elements,))
_substitute_markers(n::JuliaBinaryOp, ctx::LoaderContext)       = _substitute_children!(n, ctx, (:left, :right),          ())
_substitute_markers(n::JuliaUnaryOp, ctx::LoaderContext)        = _substitute_children!(n, ctx, (:operand,),              ())
_substitute_markers(n::JuliaTernary, ctx::LoaderContext)        = _substitute_children!(n, ctx, (:condition, :then_branch, :else_branch), ())
_substitute_markers(n::JuliaIndex, ctx::LoaderContext)          = _substitute_children!(n, ctx, (:collection,),           (:indices,))
_substitute_markers(n::JuliaFieldAccess, ctx::LoaderContext)    = _substitute_children!(n, ctx, (:object, :field),        ())
_substitute_markers(n::JuliaRange, ctx::LoaderContext)          = _substitute_children!(n, ctx, (:start, :step, :stop),   ())
_substitute_markers(n::JuliaTypeAnnotation, ctx::LoaderContext) = _substitute_children!(n, ctx, (:value, :type),          ())
_substitute_markers(n::JuliaAssignment, ctx::LoaderContext)     = _substitute_children!(n, ctx, (:target, :value),        ())
_substitute_markers(n::JuliaForIterator, ctx::LoaderContext)    = _substitute_children!(n, ctx, (:variable, :iterable),   ())
_substitute_markers(n::JuliaFor, ctx::LoaderContext)            = _substitute_children!(n, ctx, (:body,),                 (:iterators,))
_substitute_markers(n::JuliaWhile, ctx::LoaderContext)          = _substitute_children!(n, ctx, (:condition, :body),      ())
_substitute_markers(n::JuliaReturn, ctx::LoaderContext)         = _substitute_children!(n, ctx, (:value,),                ())
_substitute_markers(n::JuliaTry, ctx::LoaderContext)            = _substitute_children!(n, ctx, (:body, :catch_var, :catch_branch, :finally_branch), ())
_substitute_markers(n::JuliaBegin, ctx::LoaderContext)          = _substitute_children!(n, ctx, (:body,),                 ())
_substitute_markers(n::JuliaIf, ctx::LoaderContext)             = _substitute_children!(n, ctx, (:condition, :then_branch, :else_branch), ())
_substitute_markers(n::JuliaFunction, ctx::LoaderContext)       = _substitute_children!(n, ctx, (:name, :body),           (:params,))
_substitute_markers(n::JuliaLambda, ctx::LoaderContext)         = _substitute_children!(n, ctx, (:body,),                 (:parameters,))

function __init__()
    register_file_document_type!(".jl", JuliaFile)
end

end # module
