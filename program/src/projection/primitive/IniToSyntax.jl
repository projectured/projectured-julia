"""
    IniToSyntaxModule

INI → SyntaxDocument projection. Maps INI document types to syntax tree
nodes for rendering as syntax-highlighted text.

Layout:
- `IniFile`            → SyntaxNode (children = sections/comments/includes)
- `IniSection`         → SyntaxNode (open = `[name]`, children = entries)
- `IniConfigOption`    → SyntaxNode (key = value, optional # comment)
- `IniParamAssignment` → SyntaxNode (key = value, optional # comment)
- `IniComment`         → SyntaxLeaf (# text)
- `IniInclude`         → SyntaxLeaf (include path)
- `IniInsertion`       → SyntaxLeaf (placeholder)

Readers are deferred to a future step.
"""
module IniToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IniModule: IniDocument, IniInsertion, IniComment, IniInclude, IniConfigOption, IniParamAssignment, IniSection, IniFile
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default,
                      color_solarized_blue, color_solarized_green, color_solarized_magenta,
                      color_solarized_cyan, color_solarized_yellow, color_solarized_gray,
                      color_solarized_red
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                         ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export IniInsertionToSyntaxLeaf, IniCommentToSyntaxLeaf, IniIncludeToSyntaxLeaf,
       IniConfigOptionToSyntaxNode, IniParamAssignmentToSyntaxNode,
       IniSectionToSyntaxNode, IniFileToSyntaxNode, IniToSyntax

# ── IniInsertionToSyntaxLeaf ─────────────────────────────────────────────────

struct IniInsertionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
IniInsertionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) =
    IniInsertionToSyntaxLeaf(font, color)

function projection_print(p::IniInsertionToSyntaxLeaf, recursion, ins::IniInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, ins.selection))
    SimpleIoMap(p, ins, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString("insert INI entry here", p.font, p.color),
        output_selection))
end

# ── IniCommentToSyntaxLeaf ───────────────────────────────────────────────────

struct IniCommentToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
IniCommentToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) =
    IniCommentToSyntaxLeaf(font, color)

function map_reference_forward(::IniCommentToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        text.rest... => @reference value.^(rest)
    end
end

function map_reference_backward(::IniCommentToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value.rest... => @reference text.^(rest)
    end
end

function projection_read(p::IniCommentToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::IniCommentToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::IniCommentToSyntaxLeaf, recursion, c::IniComment, ctx)
    sel = Cell(() -> begin
        @reference_case c.selection begin
            text.rest... => @reference value.^(rest)
        end
    end)
    SimpleIoMap(p, c, SyntaxLeaf(
        TextString("#", p.font, p.color),
        TextString("", p.font, color_default),
        TextString(() -> c.text, p.font, p.color),
        sel))
end

# ── IniIncludeToSyntaxLeaf ───────────────────────────────────────────────────

struct IniIncludeToSyntaxLeaf <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
    path_font::StyleFont
    path_color::StyleColor
end
IniIncludeToSyntaxLeaf(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta,
                         path_font=font_ubuntu_monospace_regular_24, path_color=color_solarized_green) =
    IniIncludeToSyntaxLeaf(keyword_font, keyword_color, path_font, path_color)

function map_reference_forward(::IniIncludeToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        path.rest... => @reference children[2].value.^(rest)
    end
end

function map_reference_backward(::IniIncludeToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 2
                @reference_case rest begin
                    value.tail... => @reference path.^(tail)
                end
            else
                nothing
            end
        end
    end
end

function projection_read(p::IniIncludeToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::IniIncludeToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::IniIncludeToSyntaxLeaf, recursion, inc::IniInclude, ctx)
    path_sel = Cell(() -> begin
        @reference_case inc.selection begin
            path.rest... => @reference value.^(rest)
        end
    end)
    keyword_leaf = SyntaxLeaf(
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        TextString("include", p.keyword_font, p.keyword_color))
    path_leaf = SyntaxLeaf(
        TextString("", p.path_font, color_default),
        TextString("", p.path_font, color_default),
        TextString(() -> inc.path, p.path_font, p.path_color),
        path_sel)
    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        SyntaxDocument[keyword_leaf, path_leaf])
    SimpleIoMap(p, inc, node)
end

# ── IniConfigOptionToSyntaxNode ──────────────────────────────────────────────
#
# Layout: SyntaxNode(open="", close="", sep="", [
#   SyntaxLeaf(key),            child 1
#   SyntaxLeaf(" = "),          child 2 (projection-introduced)
#   SyntaxLeaf(value),          child 3
#   SyntaxLeaf(" # comment"),   child 4 (optional, only when comment != nothing)
# ], indentation=0)

struct IniConfigOptionToSyntaxNode <: Projection
    key_font::StyleFont
    key_color::StyleColor
    eq_font::StyleFont
    eq_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
    comment_font::StyleFont
    comment_color::StyleColor
end
IniConfigOptionToSyntaxNode(;
        key_font=font_ubuntu_monospace_regular_24,   key_color=color_solarized_blue,
        eq_font=font_ubuntu_monospace_regular_24,    eq_color=color_solarized_gray,
        value_font=font_ubuntu_monospace_regular_24, value_color=color_solarized_cyan,
        comment_font=font_ubuntu_monospace_regular_24, comment_color=color_solarized_gray) =
    IniConfigOptionToSyntaxNode(key_font, key_color, eq_font, eq_color,
                                value_font, value_color, comment_font, comment_color)

function map_reference_forward(::IniConfigOptionToSyntaxNode, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        key.rest...   => @reference children[1].value.^(rest)
        value.rest... => @reference children[3].value.^(rest)
    end
end

function map_reference_backward(::IniConfigOptionToSyntaxNode, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                @reference_case rest begin
                    value.tail... => @reference key.^(tail)
                end
            elseif child_i == 3
                @reference_case rest begin
                    value.tail... => @reference value.^(tail)
                end
            else
                nothing
            end
        end
    end
end

function projection_read(p::IniConfigOptionToSyntaxNode, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::IniConfigOptionToSyntaxNode, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::IniConfigOptionToSyntaxNode, recursion, opt::IniConfigOption, ctx)
    key_sel = Cell(() -> begin
        @reference_case opt.selection begin
            key.rest... => @reference value.^(rest)
        end
    end)
    value_sel = Cell(() -> begin
        @reference_case opt.selection begin
            value.rest... => @reference value.^(rest)
        end
    end)

    key_leaf = SyntaxLeaf(
        TextString("", p.key_font, color_default),
        TextString("", p.key_font, color_default),
        TextString(() -> opt.key, p.key_font, p.key_color),
        key_sel)
    eq_leaf = SyntaxLeaf(
        TextString("", p.eq_font, color_default),
        TextString("", p.eq_font, color_default),
        TextString(" = ", p.eq_font, p.eq_color))
    value_leaf = SyntaxLeaf(
        TextString("", p.value_font, color_default),
        TextString("", p.value_font, color_default),
        TextString(() -> opt.value, p.value_font, p.value_color),
        value_sel)

    children = SyntaxDocument[key_leaf, eq_leaf, value_leaf]
    if opt.comment !== nothing
        comment_leaf = SyntaxLeaf(
            TextString(" #", p.comment_font, p.comment_color),
            TextString("", p.comment_font, color_default),
            TextString(() -> something(opt.comment, ""), p.comment_font, p.comment_color))
        push!(children, comment_leaf)
    end

    node = SyntaxNode(
        TextString("", p.key_font, color_default),
        TextString("", p.key_font, color_default),
        TextString("", p.key_font, color_default),
        children)
    SimpleIoMap(p, opt, node)
end

# ── IniParamAssignmentToSyntaxNode ───────────────────────────────────────────
#
# Same layout as IniConfigOptionToSyntaxNode but different default colours.

struct IniParamAssignmentToSyntaxNode <: Projection
    key_font::StyleFont
    key_color::StyleColor
    eq_font::StyleFont
    eq_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
    comment_font::StyleFont
    comment_color::StyleColor
end
IniParamAssignmentToSyntaxNode(;
        key_font=font_ubuntu_monospace_regular_24,   key_color=color_solarized_green,
        eq_font=font_ubuntu_monospace_regular_24,    eq_color=color_solarized_gray,
        value_font=font_ubuntu_monospace_regular_24, value_color=color_solarized_cyan,
        comment_font=font_ubuntu_monospace_regular_24, comment_color=color_solarized_gray) =
    IniParamAssignmentToSyntaxNode(key_font, key_color, eq_font, eq_color,
                                   value_font, value_color, comment_font, comment_color)

function map_reference_forward(::IniParamAssignmentToSyntaxNode, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        key.rest...   => @reference children[1].value.^(rest)
        value.rest... => @reference children[3].value.^(rest)
    end
end

function map_reference_backward(::IniParamAssignmentToSyntaxNode, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                @reference_case rest begin
                    value.tail... => @reference key.^(tail)
                end
            elseif child_i == 3
                @reference_case rest begin
                    value.tail... => @reference value.^(tail)
                end
            else
                nothing
            end
        end
    end
end

function projection_read(p::IniParamAssignmentToSyntaxNode, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::IniParamAssignmentToSyntaxNode, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::IniParamAssignmentToSyntaxNode, recursion, pa::IniParamAssignment, ctx)
    key_sel = Cell(() -> begin
        @reference_case pa.selection begin
            key.rest... => @reference value.^(rest)
        end
    end)
    value_sel = Cell(() -> begin
        @reference_case pa.selection begin
            value.rest... => @reference value.^(rest)
        end
    end)

    key_leaf = SyntaxLeaf(
        TextString("", p.key_font, color_default),
        TextString("", p.key_font, color_default),
        TextString(() -> pa.key, p.key_font, p.key_color),
        key_sel)
    eq_leaf = SyntaxLeaf(
        TextString("", p.eq_font, color_default),
        TextString("", p.eq_font, color_default),
        TextString(" = ", p.eq_font, p.eq_color))
    value_leaf = SyntaxLeaf(
        TextString("", p.value_font, color_default),
        TextString("", p.value_font, color_default),
        TextString(() -> pa.value, p.value_font, p.value_color),
        value_sel)

    children = SyntaxDocument[key_leaf, eq_leaf, value_leaf]
    if pa.comment !== nothing
        comment_leaf = SyntaxLeaf(
            TextString(" #", p.comment_font, p.comment_color),
            TextString("", p.comment_font, color_default),
            TextString(() -> something(pa.comment, ""), p.comment_font, p.comment_color))
        push!(children, comment_leaf)
    end

    node = SyntaxNode(
        TextString("", p.key_font, color_default),
        TextString("", p.key_font, color_default),
        TextString("", p.key_font, color_default),
        children)
    SimpleIoMap(p, pa, node)
end

# ── IniSectionToSyntaxNode ───────────────────────────────────────────────────
#
# Layout: SyntaxNode(open="[name]", close="", sep="", [
#   ... recursively projected entries ...
# ], indentation=1)
#
# Selection:
#   .name[k]      → output open text (projected, display-only for now)
#   .entries[i].… → .children[i].… (via child iomap)

struct IniSectionToSyntaxNode <: Projection
    heading_font::StyleFont
    heading_color::StyleColor
end
IniSectionToSyntaxNode(; heading_font=font_ubuntu_monospace_bold_24, heading_color=color_solarized_yellow) =
    IniSectionToSyntaxNode(heading_font, heading_color)

function map_reference_forward(p::IniSectionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        entries{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::IniSectionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            translated = map_reference_backward(child.projection, child, rest)
            translated === nothing && return nothing
            @reference entries[child_i].^(translated)
        end
    end
end

function projection_read(p::IniSectionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::IniSectionToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function _ini_section_heading(s::IniSection)
    s.is_general ? "[General]" : "[Config $(s.name)]"
end

function projection_print(p::IniSectionToSyntaxNode, recursion, s::IniSection, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, entry,
                                   child_context(ctx, @reference ^(reference).entries[i]))
                               for (i, entry) in enumerate(s)])

    sel = Cell(() -> begin
        path = s.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            entries{s_idx:_}.rest... => begin
                child_i = s_idx + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[child_i].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])

    output = SyntaxNode(
        TextString(() -> _ini_section_heading(s), p.heading_font, p.heading_color),
        TextString("", p.heading_font, color_default),
        TextString("", p.heading_font, color_default),
        children_cv, 1, s.collapsed, sel)
    ChildrenIoMap(p, s, output, child_iomaps)
end

# ── IniFileToSyntaxNode ──────────────────────────────────────────────────────
#
# Layout: SyntaxNode(open="", close="", sep="", [
#   ... recursively projected children (sections, comments, includes) ...
# ], indentation=0)
#
# Selection:
#   .children[i].… → .children[i].… (via child iomap)

struct IniFileToSyntaxNode <: Projection end

function map_reference_forward(p::IniFileToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::IniFileToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            translated = map_reference_backward(child.projection, child, rest)
            translated === nothing && return nothing
            @reference children[child_i].^(translated)
        end
    end
end

function projection_read(p::IniFileToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::IniFileToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::IniFileToSyntaxNode, recursion, f::IniFile, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, child,
                                   child_context(ctx, @reference ^(reference).children[i]))
                               for (i, child) in enumerate(f)])

    sel = Cell(() -> begin
        path = f.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            children{s_idx:_}.rest... => begin
                child_i = s_idx + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[child_i].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])

    output = SyntaxNode(
        TextString("", font_ubuntu_monospace_regular_24, color_default),
        TextString("", font_ubuntu_monospace_regular_24, color_default),
        TextString("\n", font_ubuntu_monospace_regular_24, color_default),
        children_cv, 1, Cell(false), sel)
    ChildrenIoMap(p, f, output, child_iomaps)
end

# ── Compound convenience constructor ─────────────────────────────────────────

function IniToSyntax()
    TypeDispatchingProjection(
        IniInsertion       => IniInsertionToSyntaxLeaf(),
        IniComment         => IniCommentToSyntaxLeaf(),
        IniInclude         => IniIncludeToSyntaxLeaf(),
        IniConfigOption    => IniConfigOptionToSyntaxNode(),
        IniParamAssignment => IniParamAssignmentToSyntaxNode(),
        IniSection         => IniSectionToSyntaxNode(),
        IniFile            => IniFileToSyntaxNode(),
    )
end

end # module
