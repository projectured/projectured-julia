# Fragment of `JuliaModule` — `JuliaFile`, the `.jl` file on disk.
#
# A cross-file reference is written in Julia as a `pred_ref("…")` call whose one
# argument is the marker, so the file stays valid Julia. The file writes one
# where the save cuts, and the load splices the node it names into its place.
# The `definition` verb, which names a top-level definition, lives here too.

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
    content::Document = JuliaNothing()
end

emit_text(f::JuliaFile) = print_natural_text(get_file_content(f))

function _is_marker_call(node::JuliaCall)
    callee = node.callee
    callee isa JuliaIdentifier || return false
    callee.name == PRED_REF_FUNCTION_NAME || return false
    args = getfield(node, :arguments)[]
    length(args) == 1 || return false
    arg = args[1] isa Cell ? args[1][] : args[1]
    arg isa JuliaString
end

# What the file writes itself, and how it spells a reference to what it does
# not: a `pred_ref("…")` call with the marker as its one string argument.
get_file_domain(::Type{<:JuliaFile}) = JuliaDocument
make_reference_leaf(::JuliaFile, marker::AbstractString) =
    JuliaCall(JuliaIdentifier(PRED_REF_FUNCTION_NAME), CellVector([JuliaString(make_marker_text(marker))]))
function find_reference_marker(node::JuliaCall)
    _is_marker_call(node) || return nothing
    args = getfield(node, :arguments)[]
    parse_marker_text((args[1] isa Cell ? args[1][] : args[1]).value)
end
parse_file_content(::Type{<:JuliaFile}, text::AbstractString) = parse_julia(text)

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
