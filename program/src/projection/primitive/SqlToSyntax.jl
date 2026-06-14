"""
    SqlToSyntaxModule

SQL → SyntaxDocument projection. Renders a `SqlSelectStatement` as a syntax tree.

Keywords render as bold colored leaves; identifiers as regular leaves.
Projections compose recursively through the clause structure. Combine with
`SyntaxToText` to get the textual form.

Read-only: no reference mapping or read support yet.
"""
module SqlToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..SqlDocumentModule: SqlSelectStatement, SqlSelectClause, SqlFromClause, SqlWhereClause,
                            SqlSelectItem, SqlAllColumns, SqlColumnReference,
                            SqlTableExpression, SqlSubqueryFromItem, SqlFromItem, SqlJoinSegment, SqlJoinType,
                            SqlInnerJoin, SqlLeftOuterJoin, SqlRightOuterJoin, SqlFullOuterJoin, SqlCrossJoin,
                            SqlScalarValue, SqlComparison, SqlAnd, SqlOr, SqlNot,
                            render_sql
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_green
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ElementReference, FieldReference
import ..PrinterContextModule: child_context

export SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
       SqlTableExpressionToSyntaxLeaf, SqlSubqueryFromItemToSyntaxNode, SqlJoinTypeToSyntaxLeaf,
       SqlSelectItemToSyntaxNode, SqlSelectClauseToSyntaxNode,
       SqlFromItemToSyntaxNode, SqlFromClauseToSyntaxNode,
       SqlJoinSegmentToSyntaxNode, SqlWhereClauseToSyntaxNode,
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

map_reference_forward(::SqlAllColumnsToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlAllColumnsToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlAllColumnsToSyntaxLeaf, iomap, op) = nothing

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

map_reference_forward(::SqlColumnReferenceToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlColumnReferenceToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlColumnReferenceToSyntaxLeaf, iomap, op) = nothing

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

map_reference_forward(::SqlTableExpressionToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlTableExpressionToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlTableExpressionToSyntaxLeaf, iomap, op) = nothing

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
    paren_node = SyntaxNode("(", ")", " ", () -> SyntaxDocument[subq_im[].output])
    node = _space_node(() -> begin
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
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlSubqueryFromItemToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlSubqueryFromItemToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlSubqueryFromItemToSyntaxNode, iomap, op) = nothing

# ── SqlJoinTypeToSyntaxLeaf ───────────────────────────────────────────────────

struct SqlJoinTypeToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlJoinTypeToSyntaxLeaf(; font=font_ubuntu_monospace_bold_24, color=color_solarized_blue) =
    SqlJoinTypeToSyntaxLeaf(font, color)

function projection_print(p::SqlJoinTypeToSyntaxLeaf, recursion, doc::SqlJoinType, ctx)
    SimpleIoMap(p, doc, _kw(render_sql(doc), p.font, p.color))
end

map_reference_forward(::SqlJoinTypeToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlJoinTypeToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlJoinTypeToSyntaxLeaf, iomap, op) = nothing

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
    node = _space_node(() -> begin
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
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlSelectItemToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlSelectItemToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlSelectItemToSyntaxNode, iomap, op) = nothing

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

    node = _space_node(() -> begin
        kws = SyntaxDocument[_kw("SELECT", p.keyword_font, p.keyword_color)]
        doc.distinct !== nothing && push!(kws, _kw("DISTINCT", p.keyword_font, p.keyword_color))
        push!(kws, items_body)
        kws
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlSelectClauseToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlSelectClauseToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlSelectClauseToSyntaxNode, iomap, op) = nothing

# ── SqlJoinSegmentToSyntaxNode ────────────────────────────────────────────────

struct SqlJoinSegmentToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlJoinSegmentToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24,
                              keyword_color=color_solarized_blue) =
    SqlJoinSegmentToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::SqlJoinSegmentToSyntaxNode, recursion, doc::SqlJoinSegment, ctx)
    projected = Cell(() -> begin
        jt = projection_print(recursion, recursion, doc.join_type,
                              child_context(ctx, FieldReference("join_type")))
        fi = projection_print(recursion, recursion, doc.from_item,
                              child_context(ctx, FieldReference("from_item")))
        (jt, fi)
    end)
    node = _space_node(() -> begin
        jt, fi = projected[]
        SyntaxDocument[jt.output, fi.output]
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlJoinSegmentToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlJoinSegmentToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlJoinSegmentToSyntaxNode, iomap, op) = nothing

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
    joins_body = _newline_body(() -> begin
        _, joins = projected[]
        SyntaxDocument[j.output for j in joins]
    end)
    node = _space_node(() -> begin
        base, joins = projected[]
        isempty(joins) ? SyntaxDocument[base.output] :
                         SyntaxDocument[base.output, joins_body]
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlFromItemToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlFromItemToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlFromItemToSyntaxNode, iomap, op) = nothing

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

    node = _space_node(
        () -> SyntaxDocument[_kw("FROM", p.keyword_font, p.keyword_color), items_body])
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlFromClauseToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlFromClauseToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlFromClauseToSyntaxNode, iomap, op) = nothing

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
    node = _space_node(
        () -> SyntaxDocument[_kw("WHERE", p.keyword_font, p.keyword_color), cond_body])
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlWhereClauseToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlWhereClauseToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlWhereClauseToSyntaxNode, iomap, op) = nothing

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
        TextString(() -> render_sql(doc), p.font, p.color),
        doc.selection))
end

map_reference_forward(::SqlScalarValueToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlScalarValueToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlScalarValueToSyntaxLeaf, iomap, op) = nothing

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
    node = _space_node(() -> begin
        left, right = projected[]
        SyntaxDocument[left.output, _kw(doc.operator, p.keyword_font, p.keyword_color), right.output]
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlComparisonToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlComparisonToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlComparisonToSyntaxNode, iomap, op) = nothing

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
    node = SyntaxNode("(", ")", " ", () -> begin
        left, right = projected[]
        SyntaxDocument[left.output, _kw(p.keyword, p.keyword_font, p.keyword_color), right.output]
    end)
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlBooleanBinaryToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlBooleanBinaryToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlBooleanBinaryToSyntaxNode, iomap, op) = nothing

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
    node = SyntaxNode("(", ")", " ", () ->
        SyntaxDocument[_kw("NOT", p.keyword_font, p.keyword_color), expr_im[].output])
    SimpleIoMap(p, doc, node)
end

map_reference_forward(::SqlNotToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlNotToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlNotToSyntaxNode, iomap, op) = nothing

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

    children = CellVector(() -> begin
        sc, fc, wc = projected[]
        docs = SyntaxDocument[sc.output, fc.output]
        wc !== nothing && push!(docs, wc.output)
        docs
    end)

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        children,
        0, Cell(false), stmt.selection)

    SimpleIoMap(p, stmt, node)
end

map_reference_forward(::SqlSelectStatementToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlSelectStatementToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlSelectStatementToSyntaxNode, iomap, op) = nothing

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
        SqlJoinSegment          => SqlJoinSegmentToSyntaxNode(),
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
