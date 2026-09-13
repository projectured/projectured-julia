"""
    JuliaFileModule

`JuliaFile`: a `FileDocument` whose `content` is a `JuliaDocument`
(the projectured Julia AST from `JuliaModule`). Parse uses the
existing `parse_julia`; emit runs the standard `JuliaToSyntax →
SyntaxToText → TextToString` projection chain via `print_natural_text`.

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

**The `definition` marker function.** This module also registers the
Julia domain's entry in the marker vocabulary:
`definition(document, "name")` returns the one top-level definition of
that name — see [`find_julia_definition`](@ref).
"""
module JuliaFileModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..CollectionModule: CellVector, ComputedCellVector
import ..JuliaModule: JuliaDocument, JuliaNothing, JuliaCall, JuliaIdentifier,
                      JuliaString, JuliaBlock, JuliaArray, JuliaTuple, JuliaBinaryOperation,
                      JuliaUnaryOperation, JuliaIndex, JuliaFieldAccess, JuliaRange,
                      JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator,
                      JuliaWhile, JuliaReturn, JuliaTry, JuliaBegin, JuliaIf,
                      JuliaFunction, JuliaLambda, JuliaTernary, JuliaConst,
                      JuliaDocstring, JuliaMacroCall, JuliaStruct, JuliaAbstractType,
                      JuliaSubtype, JuliaCurly
import ..JuliaParserModule: parse_julia
import ..NaturalNotationModule: print_natural_text
import ..SerializationModule: FileDocument, emit_text, populate_file!, get_file_content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!, register_marker_function!,
                            is_file_document

export JuliaFile, PRED_REF_FUNCTION_NAME, find_julia_definition, get_julia_definition_name

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

emit_text(f::JuliaFile) = print_natural_text(get_file_content(f))

function populate_file!(f::JuliaFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = parse_julia(text)
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
    src = parse_marker_text(s.value)
    src === nothing ? node : ReferenceStub(src, ctx)
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
_substitute_markers(n::JuliaBinaryOperation, ctx::LoaderContext)       = _substitute_children!(n, ctx, (:left, :right),          ())
_substitute_markers(n::JuliaUnaryOperation, ctx::LoaderContext)        = _substitute_children!(n, ctx, (:operand,),              ())
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

# ── The `definition` vocabulary function ───────────────────────────────────
#
# `<<definition(file("steps.jl"), "packet_queue_step")>>` embeds one
# top-level definition of a source file. Addressing by the name a
# definition already carries is what makes the marker survive editing
# and reordering the file around it.

"""
    get_julia_definition_name(node) -> String or nothing

The name a top-level Julia definition introduces, or `nothing` for a
statement that introduces none (a `using`, a bare call, …).

A docstring is named by what it documents, and a macro call by its
first argument — so `@document struct Foo … end` is found under
`"Foo"`, and asking for a documented definition yields the docstring
with it rather than the bare definition.

A macro that DECLARES rather than decorates states the name itself
instead of wrapping a definition that carries one, so its first
argument is the name: `@header Ipv4Header begin … end` is found under
`"Ipv4Header"`.
"""
get_julia_definition_name(::Any) = nothing
get_julia_definition_name(n::JuliaFunction)     = _julia_header_name(n.name)
get_julia_definition_name(n::JuliaStruct)       = _julia_header_name(n.header)
get_julia_definition_name(n::JuliaAbstractType) = _julia_header_name(n.header)
get_julia_definition_name(n::JuliaAssignment)   = _julia_header_name(n.target)
get_julia_definition_name(n::JuliaConst)        = get_julia_definition_name(n.assignment)
get_julia_definition_name(n::JuliaDocstring)    = get_julia_definition_name(n.subject)

function get_julia_definition_name(n::JuliaMacroCall)
    args = getfield(n, :arguments)[]
    isempty(args) && return nothing
    subject = args[1] isa Cell ? args[1][] : args[1]
    name = get_julia_definition_name(subject)
    # The inner definition names it where there is one. Where there is not, the
    # first argument is the name: a declaring macro takes the identifier it
    # introduces, and `@header Member <: Family` takes the left side of the `<:`
    # exactly as a struct header does.
    return name === nothing ? _julia_header_name(subject) : name
end

# The name inside a definition header: a plain identifier, the callee of
# a short-form `f(x) = …`, the left side of a `<:`, the base of a
# parametric `Foo{T}`.
_julia_header_name(::Any) = nothing
_julia_header_name(n::JuliaIdentifier) = n.name
_julia_header_name(n::JuliaCall)       = _julia_header_name(n.callee)
_julia_header_name(n::JuliaSubtype)    = _julia_header_name(n.lhs)
_julia_header_name(n::JuliaCurly)      = _julia_header_name(n.callee)

"""
    find_julia_definition(document, name) -> JuliaDocument

The top-level definition called `name` in `document` (a `JuliaFile` or
a parsed `JuliaDocument`). Errors when there is no such definition, and
when there is more than one — an ambiguous embed would silently show
the wrong half of a file, so it is not allowed. Method overloads of one
function are the common case of that and must be embedded by wrapping
them, not by name.
"""
function find_julia_definition(document, name::AbstractString)
    doc = is_file_document(document) ? get_file_content(document) : document
    doc isa JuliaDocument ||
        error("definition(…): expected a Julia document, got ", typeof(document))
    matches = Any[s for s in _julia_toplevel_statements(doc)
                    if get_julia_definition_name(s) == String(name)]
    isempty(matches) &&
        error("definition(…): no top-level definition named ", repr(String(name)),
              " — the file defines (", join(_julia_definition_names(doc), ", "), ")")
    length(matches) > 1 &&
        error("definition(…): ", repr(String(name)), " is defined ", length(matches),
              " times at top level — a marker must name exactly one definition")
    matches[1]
end

_julia_toplevel_statements(doc::JuliaBlock) =
    Any[s isa Cell ? s[] : s for s in getfield(doc, :statements)[]]
_julia_toplevel_statements(doc::JuliaDocument) = Any[doc]

_julia_definition_names(doc) =
    String[n for n in (get_julia_definition_name(s) for s in _julia_toplevel_statements(doc))
             if n !== nothing]

function __init__()
    register_file_document_type!(".jl", JuliaFile)
    register_marker_function!(:definition,
                              (ctx, document, name) -> find_julia_definition(document, name))
end

end # module
