# Fragment of `XmlModule`.
#
# `XmlFile`: a `FileDocument` whose `content` is an `XmlDocument`
# (the projectured XML AST). Parse uses the existing `parse_xml`; emit
# runs the standard `XmlToSyntax → SyntaxToText → TextToString`
# projection chain via `print_natural_text`.
#
# **Marker syntax in XML.**
#
#     <pred:ref>&lt;&lt;file("child.xml")&gt;&gt;</pred:ref>
#
# The element's tag is `pred:ref` and its sole child is an `XmlText`
# whose content is the marker text (the `<<` and `>>` naturally
# survive the XML escape/unescape round-trip). Load walks the AST for
# elements with `tag == "pred:ref"` whose only child is a single text
# node, and rewrites each such slot into a `ReferenceStub`. Emit is
# symmetric via a projection extension (see `XmlToSyntax.jl`).
"""
The XML tag identifying a cross-file marker element:

    <pred:ref>&lt;&lt;file("path")&gt;&gt;</pred:ref>
"""
const PRED_REF_ELEMENT_TAG = "pred:ref"

# XmlFile requires a non-empty content — the root element. Empty is
# `XmlNothing()`, which is not an `XmlElement`, so the placeholder we
# hand `_load_into_context` is an empty-tagged element that
# `populate_file!` overwrites.
@document struct XmlFile <: FileDocument
    filename::String
    content::XmlDocument = XmlNothing()
end

emit_text(f::XmlFile) = print_natural_text(get_file_content(f))

function populate_file!(f::XmlFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = parse_xml(text)
    ast = _substitute_markers(ast, ctx)
    getfield(f, :content)[] = ast
    f
end

_unwrap(x) = x isa AbstractCell ? x[] : x

# A `pred:ref` element with a single text child is a marker.
function _is_marker_element(node::XmlElement)
    _unwrap(getfield(node, :tag)) == PRED_REF_ELEMENT_TAG || return false
    children = _unwrap(getfield(node, :children))
    length(children) == 1 || return false
    _unwrap(children[1]) isa XmlText
end

function _marker_stub(node::XmlElement, ctx::LoaderContext)
    child = _unwrap(_unwrap(getfield(node, :children))[1])
    src = parse_marker_text(strip(_unwrap(getfield(child, :content))))
    src === nothing ? node : ReferenceStub(src, ctx)
end

# Traversal — mutate in place. Element children may themselves be
# marker elements or contain them; attributes hold plain strings so
# they never carry markers.
_substitute_markers(node, ctx::LoaderContext) = node

function _substitute_markers(node::XmlElement, ctx::LoaderContext)
    if _is_marker_element(node)
        return _marker_stub(node, ctx)
    end
    v = getfield(node, :children)[]
    for i in eachindex(v)
        v[i] = _substitute_markers(v[i], ctx)
    end
    node
end
