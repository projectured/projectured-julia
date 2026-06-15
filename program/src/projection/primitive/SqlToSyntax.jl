"""
    SqlToSyntaxModule

SQL → SyntaxDocument projection. Renders a `SqlSelectStatement` as a syntax tree.

Keywords render as bold colored leaves; identifiers as regular leaves.
Projections compose recursively through the clause structure. Combine with
`SyntaxToText` to get the textual form.

Selection mapping is implemented at all levels: leaf projections share
`doc.selection` with the SyntaxLeaf; `SqlSelectStatementToSyntaxNode` uses
`ChildrenIoMap` with clause-level delegation so selection propagates through
the full statement tree.
"""
module SqlToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..SqlDocumentModule: SqlSelectStatement, SqlSelectClause, SqlFromClause, SqlWhereClause,
                            SqlWhereFilterCondition,
                            SqlSelectItem, SqlAllColumns, SqlColumnReference,
                            SqlTableExpression, SqlSubqueryFromItem, SqlFromItem, SqlJoinedFromItem, SqlJoinType,
                            SqlInnerJoin, SqlLeftOuterJoin, SqlRightOuterJoin, SqlFullOuterJoin, SqlCrossJoin,
                            SqlJoinOnCondition,
                            SqlScalarValue, SqlComparison, SqlAnd, SqlOr, SqlNot
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_green
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, FieldReference, ProjectionReference, EmptyReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
import ..PrinterContextModule: child_context

export SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
       SqlTableExpressionToSyntaxLeaf, SqlSubqueryFromItemToSyntaxNode, SqlJoinTypeToSyntaxLeaf,
       SqlSelectItemToSyntaxNode, SqlSelectClauseToSyntaxNode,
       SqlFromItemToSyntaxNode, SqlFromClauseToSyntaxNode,
       SqlJoinedFromItemToSyntaxNode, SqlJoinOnConditionToSyntaxNode,
       SqlWhereFilterConditionToSyntaxNode, SqlWhereClauseToSyntaxNode,
       SqlScalarValueToSyntaxLeaf, SqlComparisonToSyntaxNode,
       SqlBooleanBinaryToSyntaxNode, SqlNotToSyntaxNode,
       SqlSelectStatementToSyntaxNode, SqlToSyntax

# ── helpers ────────────────────────────────────────────────────────────────────

_kw(text, font, color) = SyntaxLeaf(
    TextString("", font, color_default),
    TextString("", font, color_default),
    TextString(text, font, color),
    Cell(nothing))

_space_node(f::Function) =
    SyntaxNode("", "", " ", f)

_comma_node(f::Function) =
    SyntaxNode("", "", ", ", f)

_comma_body(f::Function) =
    SyntaxNode("", "", ",", f; indentation=1)

_newline_body(f::Function) =
    SyntaxNode("", "", "", f; indentation=1)

# ── SqlAllColumnsToSyntaxLeaf ─────────────────────────────────────────────────

struct SqlAllColumnsToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlAllColumnsToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_default) =
    SqlAllColumnsToSyntaxLeaf(font, color)

function projection_print(p::SqlAllColumnsToSyntaxLeaf, recursion, doc::SqlAllColumns, ctx)
    SimpleIoMap(p, doc, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> begin
            q = doc.qualifier
            q === nothing ? "*" : "$(q.name).*"
        end, p.font, p.color),
        doc.selection))
end

function map_reference_forward(::SqlAllColumnsToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

function map_reference_backward(::SqlAllColumnsToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

projection_read(::SqlAllColumnsToSyntaxLeaf, iomap::SimpleIoMap, op) = nothing

# ── SqlColumnReferenceToSyntaxLeaf ────────────────────────────────────────────

struct SqlColumnReferenceToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlColumnReferenceToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_default) =
    SqlColumnReferenceToSyntaxLeaf(font, color)

function projection_print(p::SqlColumnReferenceToSyntaxLeaf, recursion, doc::SqlColumnReference, ctx)
    SimpleIoMap(p, doc, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> begin
            q = doc.qualifier
            col = doc.column_name.name
            q === nothing ? col : "$(q.name).$col"
        end, p.font, p.color),
        doc.selection))
end

function map_reference_forward(::SqlColumnReferenceToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

function map_reference_backward(::SqlColumnReferenceToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

projection_read(::SqlColumnReferenceToSyntaxLeaf, iomap::SimpleIoMap, op) = nothing

# ── SqlTableExpressionToSyntaxLeaf ────────────────────────────────────────────

struct SqlTableExpressionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlTableExpressionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green) =
    SqlTableExpressionToSyntaxLeaf(font, color)

function projection_print(p::SqlTableExpressionToSyntaxLeaf, recursion, doc::SqlTableExpression, ctx)
    SimpleIoMap(p, doc, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> begin
            tn = doc.table_name
            base = tn.schema_name === nothing ? tn.name : "$(tn.schema_name).$(tn.name)"
            a = doc.alias
            a === nothing ? base : "$base AS $(a.name)"
        end, p.font, p.color),
        doc.selection))
end

function map_reference_forward(::SqlTableExpressionToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

function map_reference_backward(::SqlTableExpressionToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

projection_read(::SqlTableExpressionToSyntaxLeaf, iomap::SimpleIoMap, op) = nothing

# ── SqlSubqueryFromItemToSyntaxNode ──────────────────────────────────────────

struct SqlSubqueryFromItemToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
    identifier_font::StyleFont
end
SqlSubqueryFromItemToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                                   keyword_color=color_solarized_blue,
                                   identifier_font=font_ubuntu_monospace_regular_24) =
    SqlSubqueryFromItemToSyntaxNode(keyword_font, keyword_color, identifier_font)

function projection_print(p::SqlSubqueryFromItemToSyntaxNode, recursion, doc::SqlSubqueryFromItem, ctx)
    subq_im = Cell(() -> projection_print(recursion, recursion, doc.subquery,
                                          child_context(ctx, FieldReference("subquery"))))
    child_iomaps_cell = Cell(() -> Any[subq_im[]])

    paren_node = SyntaxNode("(", ")", " ", () -> SyntaxDocument[subq_im[].output])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            docs = SyntaxDocument[paren_node]
            if doc.alias !== nothing
                push!(docs, _kw("AS", p.keyword_font, p.keyword_color))
                push!(docs, SyntaxLeaf(
                    TextString("", p.identifier_font, color_default),
                    TextString("", p.identifier_font, color_default),
                    TextString(() -> doc.alias === nothing ? "" : doc.alias.name,
                               p.identifier_font, color_default),
                    Cell(nothing)))
            end
            docs
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        subquery.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].children[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference subquery.^(inner)
        end
    end
end

function projection_read(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

_join_type_display(::SqlInnerJoin)      = "INNER JOIN"
_join_type_display(::SqlLeftOuterJoin)  = "LEFT OUTER JOIN"
_join_type_display(::SqlRightOuterJoin) = "RIGHT OUTER JOIN"
_join_type_display(::SqlFullOuterJoin)  = "FULL OUTER JOIN"
_join_type_display(::SqlCrossJoin)      = "CROSS JOIN"

# ── SqlJoinTypeToSyntaxLeaf ───────────────────────────────────────────────────

struct SqlJoinTypeToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlJoinTypeToSyntaxLeaf(; font=font_ubuntu_monospace_bold_24, color=color_solarized_blue) =
    SqlJoinTypeToSyntaxLeaf(font, color)

function projection_print(p::SqlJoinTypeToSyntaxLeaf, recursion, doc::SqlJoinType, ctx)
    SimpleIoMap(p, doc, _kw(_join_type_display(doc), p.font, p.color))
end

function map_reference_forward(::SqlJoinTypeToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

function map_reference_backward(::SqlJoinTypeToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

projection_read(::SqlJoinTypeToSyntaxLeaf, iomap::SimpleIoMap, op) = nothing

# ── SqlSelectItemToSyntaxNode ─────────────────────────────────────────────────

struct SqlSelectItemToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
    alias_font::StyleFont
end
SqlSelectItemToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                            keyword_color=color_solarized_blue,
                            alias_font=font_ubuntu_monospace_regular_24) =
    SqlSelectItemToSyntaxNode(keyword_font, keyword_color, alias_font)

function projection_print(p::SqlSelectItemToSyntaxNode, recursion, doc::SqlSelectItem, ctx)
    expr_im = Cell(() -> projection_print(recursion, recursion, doc.expression,
                                          child_context(ctx, FieldReference("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            docs = SyntaxDocument[expr_im[].output]
            if doc.column_alias !== nothing
                push!(docs, _kw("AS", p.keyword_font, p.keyword_color))
                push!(docs, SyntaxLeaf(
                    TextString("", p.alias_font, color_default),
                    TextString("", p.alias_font, color_default),
                    TextString(() -> doc.column_alias === nothing ? "" : doc.column_alias.name,
                               p.alias_font, color_default),
                    Cell(nothing)))
            end
            docs
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        expression.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference expression.^(inner)
        end
    end
end

function projection_read(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlSelectClauseToSyntaxNode ───────────────────────────────────────────────

struct SqlSelectClauseToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlSelectClauseToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                               keyword_color=color_solarized_blue) =
    SqlSelectClauseToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlSelectClauseToSyntaxNode, recursion, doc::SqlSelectClause, ctx)
    item_ims = Cell(() -> [
        projection_print(recursion, recursion, item, child_context(ctx, ElementReference(i)))
        for (i, item) in enumerate(doc.items)])

    items_body = _comma_body(() -> SyntaxDocument[im.output for im in item_ims[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            kws = SyntaxDocument[_kw("SELECT", p.keyword_font, p.keyword_color)]
            doc.distinct !== nothing && push!(kws, _kw("DISTINCT", p.keyword_font, p.keyword_color))
            push!(kws, items_body)
            kws
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, item_ims)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        items{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps[]
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            body_idx = iomap.input.distinct !== nothing ? 3 : 2
            @reference children[body_idx].children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{outer_s:_}.children{t:u}.rest... => begin
            outer_i = outer_s + 1
            body_idx = iomap.input.distinct !== nothing ? 3 : 2
            outer_i != body_idx && return nothing
            item_i = t + 1
            cims = iomap.child_iomaps[]
            1 <= item_i <= length(cims) || return nothing
            child = cims[item_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference items[item_i].^(inner)
        end
    end
end

function projection_read(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinedFromItemToSyntaxNode ─────────────────────────────────────────────

struct SqlJoinedFromItemToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlJoinedFromItemToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                                keyword_color=color_solarized_blue) =
    SqlJoinedFromItemToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlJoinedFromItemToSyntaxNode, recursion, doc::SqlJoinedFromItem, ctx)
    projected = Cell(() -> begin
        jt = projection_print(recursion, recursion, doc.join_type,
                              child_context(ctx, FieldReference("join_type")))
        fi = projection_print(recursion, recursion, doc.from_item,
                              child_context(ctx, FieldReference("from_item")))
        cond_im = doc.condition === nothing ? nothing :
            projection_print(recursion, recursion, doc.condition,
                             child_context(ctx, FieldReference("condition")))
        (jt, fi, cond_im)
    end)
    child_iomaps_cell = Cell(() -> begin
        jt, fi, cond_im = projected[]
        cond_im === nothing ? Any[jt, fi] : Any[jt, fi, cond_im]
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            jt, fi, cond_im = projected[]
            cond_im === nothing ? SyntaxDocument[jt.output, fi.output] :
                                  SyntaxDocument[jt.output, fi.output, cond_im.output]
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        join_type.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        from_item.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].^(inner)
        end
        condition.rest... => begin
            cims = iomap.child_iomaps[]
            length(cims) < 3 && return nothing
            child = cims[3]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference join_type.^(inner)
        end
        children[2].rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference from_item.^(inner)
        end
        children[3].rest... => begin
            cims = iomap.child_iomaps[]
            length(cims) < 3 && return nothing
            child = cims[3]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference condition.^(inner)
        end
    end
end

function projection_read(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinOnConditionToSyntaxNode ─────────────────────────────────────────────

struct SqlJoinOnConditionToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlJoinOnConditionToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                                 keyword_color=color_solarized_blue) =
    SqlJoinOnConditionToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlJoinOnConditionToSyntaxNode, recursion, doc::SqlJoinOnCondition, ctx)
    expr_im = Cell(() ->
        projection_print(recursion, recursion, doc.expression,
                         child_context(ctx, FieldReference("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> SyntaxDocument[_kw("ON", p.keyword_font, p.keyword_color), expr_im[].output]),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        expression.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].^(inner)
        end
    end
end

function map_reference_backward(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[2].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference expression.^(inner)
        end
    end
end

function projection_read(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlFromItemToSyntaxNode ───────────────────────────────────────────────────

struct SqlFromItemToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlFromItemToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                           keyword_color=color_solarized_blue) =
    SqlFromItemToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlFromItemToSyntaxNode, recursion, doc::SqlFromItem, ctx)
    projected = Cell(() -> begin
        base = projection_print(recursion, recursion, doc.base_item,
                                child_context(ctx, FieldReference("base_item")))
        joins = [projection_print(recursion, recursion, seg,
                                  child_context(ctx, ElementReference(i)))
                 for (i, seg) in enumerate(doc.joins)]
        (base, joins)
    end)
    child_iomaps_cell = Cell(() -> begin base, joins = projected[]; Any[base; joins] end)

    joins_body = _newline_body(() -> begin
        _, joins = projected[]
        SyntaxDocument[j.output for j in joins]
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            base, joins = projected[]
            isempty(joins) ? SyntaxDocument[base.output] :
                             SyntaxDocument[base.output, joins_body]
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        base_item.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        joins{s:_}.rest... => begin
            join_i = s + 1
            cims = iomap.child_iomaps[]
            cim_i = join_i + 1                  # index 1 is base_im
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].children[join_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference base_item.^(inner)
        end
        children{outer_s:_}.children{t:u}.rest... => begin
            outer_s != 1 && return nothing       # joins_body is always at pos 2
            join_i = t + 1
            cims = iomap.child_iomaps[]
            cim_i = join_i + 1                  # index 1 is base_im
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference joins[join_i].^(inner)
        end
    end
end

function projection_read(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlFromClauseToSyntaxNode ─────────────────────────────────────────────────

struct SqlFromClauseToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlFromClauseToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                             keyword_color=color_solarized_blue) =
    SqlFromClauseToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlFromClauseToSyntaxNode, recursion, doc::SqlFromClause, ctx)
    item_ims = Cell(() -> [
        projection_print(recursion, recursion, item, child_context(ctx, ElementReference(i)))
        for (i, item) in enumerate(doc.items)])

    items_body = _comma_body(() -> SyntaxDocument[im.output for im in item_ims[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> SyntaxDocument[_kw("FROM", p.keyword_font, p.keyword_color), items_body]),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, item_ims)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        items{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps[]
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{outer_s:_}.children{t:u}.rest... => begin
            outer_s != 1 && return nothing          # items_body is always at pos 2
            item_i = t + 1
            cims = iomap.child_iomaps[]
            1 <= item_i <= length(cims) || return nothing
            child = cims[item_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference items[item_i].^(inner)
        end
    end
end

function projection_read(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlWhereFilterConditionToSyntaxNode ──────────────────────────────────────

struct SqlWhereFilterConditionToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlWhereFilterConditionToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                                      keyword_color=color_solarized_blue) =
    SqlWhereFilterConditionToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlWhereFilterConditionToSyntaxNode, recursion, doc::SqlWhereFilterCondition, ctx)
    expr_im = Cell(() ->
        projection_print(recursion, recursion, doc.expression,
                         child_context(ctx, FieldReference("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        CellVector(() -> SyntaxDocument[expr_im[].output]),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        expression.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference expression.^(inner)
        end
    end
end

function projection_read(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlWhereClauseToSyntaxNode ────────────────────────────────────────────────

struct SqlWhereClauseToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlWhereClauseToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                              keyword_color=color_solarized_blue) =
    SqlWhereClauseToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlWhereClauseToSyntaxNode, recursion, doc::SqlWhereClause, ctx)
    cond_im = Cell(() -> doc.condition === nothing ? nothing :
        projection_print(recursion, recursion, doc.condition,
                         child_context(ctx, FieldReference("condition"))))
    cond_body = _newline_body(() -> begin
        ci = cond_im[]
        ci !== nothing ? SyntaxDocument[ci.output] : SyntaxDocument[]
    end)
    child_iomaps_cell = Cell(() -> begin ci = cond_im[]; ci === nothing ? Any[] : Any[ci] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> SyntaxDocument[_kw("WHERE", p.keyword_font, p.keyword_color), cond_body]),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        condition.rest... => begin
            cims = iomap.child_iomaps[]
            isempty(cims) && return nothing
            child = cims[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].children[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[2].children[1].rest... => begin
            cims = iomap.child_iomaps[]
            isempty(cims) && return nothing
            child = cims[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference condition.^(inner)
        end
    end
end

function projection_read(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlScalarValueToSyntaxLeaf ───────────────────────────────────────────────

struct SqlScalarValueToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlScalarValueToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_default) =
    SqlScalarValueToSyntaxLeaf(font, color)

function projection_print(p::SqlScalarValueToSyntaxLeaf, recursion, doc::SqlScalarValue, ctx)
    SimpleIoMap(p, doc, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> begin
            val = doc.value
            val isa Bool           ? (val ? "TRUE" : "FALSE") :
            val isa AbstractString ? "'$val'" :
            string(val)
        end, p.font, p.color),
        doc.selection))
end

function map_reference_forward(::SqlScalarValueToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

function map_reference_backward(::SqlScalarValueToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
    end
end

projection_read(::SqlScalarValueToSyntaxLeaf, iomap::SimpleIoMap, op) = nothing

# ── SqlComparisonToSyntaxNode ─────────────────────────────────────────────────

struct SqlComparisonToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlComparisonToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                             keyword_color=color_solarized_blue) =
    SqlComparisonToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlComparisonToSyntaxNode, recursion, doc::SqlComparison, ctx)
    projected = Cell(() -> begin
        left  = projection_print(recursion, recursion, doc.left,
                                 child_context(ctx, FieldReference("left")))
        right = projection_print(recursion, recursion, doc.right,
                                 child_context(ctx, FieldReference("right")))
        (left, right)
    end)
    child_iomaps_cell = Cell(() -> begin left, right = projected[]; Any[left, right] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            left, right = projected[]
            SyntaxDocument[left.output, _kw(doc.operator, p.keyword_font, p.keyword_color), right.output]
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        left.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        right.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference left.^(inner)
        end
        children[3].rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference right.^(inner)
        end
    end
end

function projection_read(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlBooleanBinaryToSyntaxNode (AND / OR) ──────────────────────────────────

struct SqlBooleanBinaryToSyntaxNode <: Projection
    keyword::String
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlBooleanBinaryToSyntaxNode(keyword; keyword_font=font_ubuntu_monospace_bold_24,
                                       keyword_color=color_solarized_blue) =
    SqlBooleanBinaryToSyntaxNode(keyword, keyword_font, keyword_color)

function projection_print(p::SqlBooleanBinaryToSyntaxNode, recursion, doc, ctx)
    projected = Cell(() -> begin
        left  = projection_print(recursion, recursion, doc.left,
                                 child_context(ctx, FieldReference("left")))
        right = projection_print(recursion, recursion, doc.right,
                                 child_context(ctx, FieldReference("right")))
        (left, right)
    end)
    child_iomaps_cell = Cell(() -> begin left, right = projected[]; Any[left, right] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("(", p.keyword_font, color_default),
        TextString(")", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() -> begin
            left, right = projected[]
            SyntaxDocument[left.output, _kw(p.keyword, p.keyword_font, p.keyword_color), right.output]
        end),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        left.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        right.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[1].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference left.^(inner)
        end
        children[3].rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference right.^(inner)
        end
    end
end

function projection_read(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlNotToSyntaxNode ────────────────────────────────────────────────────────

struct SqlNotToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlNotToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                      keyword_color=color_solarized_blue) =
    SqlNotToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlNotToSyntaxNode, recursion, doc::SqlNot, ctx)
    expr_im = Cell(() -> projection_print(recursion, recursion, doc.expression,
                                          child_context(ctx, FieldReference("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("(", p.keyword_font, color_default),
        TextString(")", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        CellVector(() ->
            SyntaxDocument[_kw("NOT", p.keyword_font, p.keyword_color), expr_im[].output]),
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        expression.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].^(inner)
        end
    end
end

function map_reference_backward(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children[2].rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference expression.^(inner)
        end
    end
end

function projection_read(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

projection_read(::SqlNotToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlSelectStatementToSyntaxNode ────────────────────────────────────────────
#
# Output shape (sep="" at top level; each clause node ends with \n from its
# indented body, so clauses appear on separate lines without extra separators):
#   SyntaxNode(sep=""):
#     children[1] = select_clause node  → "SELECT [DISTINCT]\n  item,\n  …\n"
#     children[2] = from_clause node    → "FROM\n  item,\n  …\n"
#     children[3] = where_clause node   → "WHERE\n  …\n"  (omitted if no condition)

struct SqlSelectStatementToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlSelectStatementToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                                  keyword_color=color_solarized_blue) =
    SqlSelectStatementToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlSelectStatementToSyntaxNode, recursion, stmt::SqlSelectStatement, ctx)
    projected = Cell(() -> begin
        sc = projection_print(recursion, recursion, stmt.select_clause,
                              child_context(ctx, FieldReference("select_clause")))
        fc = projection_print(recursion, recursion, stmt.from_clause,
                              child_context(ctx, FieldReference("from_clause")))
        wc = stmt.where_clause.condition === nothing ? nothing :
             projection_print(recursion, recursion, stmt.where_clause,
                              child_context(ctx, FieldReference("where_clause")))
        (sc, fc, wc)
    end)

    child_iomaps_cell = Cell(() -> begin
        sc, fc, wc = projected[]
        wc !== nothing ? Any[sc, fc, wc] : Any[sc, fc]
    end)

    children = CellVector(() -> begin
        sc, fc, wc = projected[]
        docs = SyntaxDocument[sc.output, fc.output]
        wc !== nothing && push!(docs, wc.output)
        docs
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = stmt.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        children,
        0, Cell(false), sel)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), _) => reference
        select_clause.rest... => begin
            cims = iomap.child_iomaps[]
            child = cims[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        from_clause.rest... => begin
            cims = iomap.child_iomaps[]
            child = cims[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[2].^(inner)
        end
        where_clause.rest... => begin
            cims = iomap.child_iomaps[]
            length(cims) < 3 && return nothing
            child = cims[3]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps[]
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            if child_i == 1
                @reference select_clause.^(inner)
            elseif child_i == 2
                @reference from_clause.^(inner)
            else
                @reference where_clause.^(inner)
            end
        end
    end
end

function projection_read(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── Compound constructor ──────────────────────────────────────────────────────

function SqlToSyntax()
    jt = SqlJoinTypeToSyntaxLeaf()
    TypeDispatchingProjection(
        SqlSelectStatement      => SqlSelectStatementToSyntaxNode(),
        SqlSelectClause         => SqlSelectClauseToSyntaxNode(),
        SqlFromClause           => SqlFromClauseToSyntaxNode(),
        SqlWhereClause          => SqlWhereClauseToSyntaxNode(),
        SqlSelectItem           => SqlSelectItemToSyntaxNode(),
        SqlAllColumns           => SqlAllColumnsToSyntaxLeaf(),
        SqlColumnReference      => SqlColumnReferenceToSyntaxLeaf(),
        SqlTableExpression      => SqlTableExpressionToSyntaxLeaf(),
        SqlSubqueryFromItem     => SqlSubqueryFromItemToSyntaxNode(),
        SqlFromItem             => SqlFromItemToSyntaxNode(),
        SqlJoinedFromItem       => SqlJoinedFromItemToSyntaxNode(),
        SqlJoinOnCondition      => SqlJoinOnConditionToSyntaxNode(),
        SqlWhereFilterCondition => SqlWhereFilterConditionToSyntaxNode(),
        SqlInnerJoin            => jt,
        SqlLeftOuterJoin        => jt,
        SqlRightOuterJoin       => jt,
        SqlFullOuterJoin        => jt,
        SqlCrossJoin            => jt,
        SqlScalarValue          => SqlScalarValueToSyntaxLeaf(),
        SqlComparison           => SqlComparisonToSyntaxNode(),
        SqlAnd                  => SqlBooleanBinaryToSyntaxNode("AND"),
        SqlOr                   => SqlBooleanBinaryToSyntaxNode("OR"),
        SqlNot                  => SqlNotToSyntaxNode(),
    )
end

end # module
