"""
    SqlToSyntaxModule

SQL → SyntaxDocument projection. Renders a `SqlSelectStatement` as a syntax tree:

    SELECT <select-list> FROM <table>

Keywords (`SELECT`, `FROM`) render as bold leaves; the select-list items and the
table reference are projected recursively so the projection stays composable and
extensible. Combine with `SyntaxToText` to get the textual form.

Read-only (v1): no reference mapping or read support yet.
"""
module SqlToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..SqlDocumentModule: SqlSelectStatement, SqlAllColumns, SqlTableReference
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_green
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ElementReference, FieldReference
import ..PrinterContextModule: child_context

export SqlAllColumnsToSyntaxLeaf, SqlTableReferenceToSyntaxLeaf,
       SqlSelectStatementToSyntaxNode, SqlToSyntax

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
        TextString("*", p.font, p.color),
        doc.selection))
end

map_reference_forward(::SqlAllColumnsToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlAllColumnsToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlAllColumnsToSyntaxLeaf, iomap, op) = nothing

# ── SqlTableReferenceToSyntaxLeaf ─────────────────────────────────────────────

struct SqlTableReferenceToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
SqlTableReferenceToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green) =
    SqlTableReferenceToSyntaxLeaf(font, color)

function projection_print(p::SqlTableReferenceToSyntaxLeaf, recursion, doc::SqlTableReference, ctx)
    SimpleIoMap(p, doc, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> doc.name, p.font, p.color),
        doc.selection))
end

map_reference_forward(::SqlTableReferenceToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::SqlTableReferenceToSyntaxLeaf, iomap, ref) = nothing
projection_read(::SqlTableReferenceToSyntaxLeaf, iomap, op) = nothing

# ── SqlSelectStatementToSyntaxNode ────────────────────────────────────────────
#
# Output shape (indentation 0, separator " " between the clauses):
#   SyntaxNode(sep=" "):
#     children[1] = SyntaxLeaf("SELECT")                ← keyword
#     children[2] = SyntaxNode(sep=", "):                ← select list
#                     children[1..n] = projected items   (just "*" in v1)
#     children[3] = SyntaxLeaf("FROM")                  ← keyword
#     children[4] = projected table reference            (the table name leaf)
# → "SELECT * FROM <table>"

struct SqlSelectStatementToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
SqlSelectStatementToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_blue) =
    SqlSelectStatementToSyntaxNode(keyword_font, keyword_color)

_keyword_leaf(text, font, color) = SyntaxLeaf(
    TextString("", font, color_default),
    TextString("", font, color_default),
    TextString(text, font, color),
    Cell(nothing))

function projection_print(p::SqlSelectStatementToSyntaxNode, recursion, stmt::SqlSelectStatement, ctx)
    select_kw = _keyword_leaf("SELECT", p.keyword_font, p.keyword_color)
    from_kw   = _keyword_leaf("FROM",   p.keyword_font, p.keyword_color)

    # Project the select-list items and the FROM reference lazily through the
    # recursion projection. Returns (item_iomaps::Vector, from_iomap).
    projected = Cell(() -> begin
        items = [projection_printer_recurse(recursion, item, child_context(ctx, ElementReference(i)))
                 for (i, item) in enumerate(stmt.select_list)]
        from  = projection_printer_recurse(recursion, stmt.from, child_context(ctx, FieldReference("from")))
        (items, from)
    end)

    select_list_node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(", ", p.keyword_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in projected[][1]]),
        0, Cell(false), Cell(nothing))

    children = CellVector(() -> SyntaxDocument[
        select_kw, select_list_node, from_kw, projected[][2].output])

    node = SyntaxNode(
        TextString("", p.keyword_font, color_default),
        TextString("", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        children,
        0, Cell(false), stmt.selection)

    ChildrenIoMap(p, stmt, node, Cell(() -> projected[][1]))
end

map_reference_forward(::SqlSelectStatementToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::SqlSelectStatementToSyntaxNode, iomap, ref) = nothing
projection_read(::SqlSelectStatementToSyntaxNode, iomap, op) = nothing

# ── Compound constructor ──────────────────────────────────────────────────────

function SqlToSyntax()
    TypeDispatchingProjection(
        SqlSelectStatement => SqlSelectStatementToSyntaxNode(),
        SqlAllColumns      => SqlAllColumnsToSyntaxLeaf(),
        SqlTableReference  => SqlTableReferenceToSyntaxLeaf(),
    )
end

end # module
