"""
    DbCatalogToSyntaxModule

DbCatalog → SyntaxDocument projection. Maps the catalog hierarchy to syntax
tree shapes:

    DbCatalogRdbms    → SyntaxNode  " host:port"        (indentation 0)
    DbCatalogDatabase → SyntaxNode  " dbname"           (indentation 1)
    DbCatalogSchema   → SyntaxNode  " schema"           (indentation 2)
    DbCatalogTable    → SyntaxNode  " table"            (indentation 3)
    DbCatalogColumn   → SyntaxLeaf  " column::type"    (indentation 4)

Children are read directly from each node's own child `CellVector`
(`rdbms.databases`, `db.schemas`, `schema.tables`, `table.columns`) and
projected recursively. The output is a hierarchical syntax tree suitable for
expand/collapse visualization when combined with `SyntaxToText`.
"""
module DbCatalogToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..DbCatalogDocumentModule: DbCatalogRdbms, DbCatalogDatabase,
                                   DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_red, color_solarized_green, color_solarized_magenta
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, append_reference
import ..PrinterContextModule: child_context
export DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode, DbCatalogSchemaToSyntaxNode,
       DbCatalogDatabaseToSyntaxNode, DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
       dbcatalog_marker_eligible

# ── DbCatalogColumnToSyntaxLeaf ───────────────────────────────────────────────

struct DbCatalogColumnToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
DbCatalogColumnToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) =
    DbCatalogColumnToSyntaxLeaf(font, color)

function projection_print(p::DbCatalogColumnToSyntaxLeaf, recursion, col::DbCatalogColumn, ctx)
    SimpleIoMap(p, col, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> " " * col.name * "::" * col.data_type, p.font, p.color),
        col.selection))
end

map_reference_forward(::DbCatalogColumnToSyntaxLeaf, iomap, ref) = nothing
map_reference_backward(::DbCatalogColumnToSyntaxLeaf, iomap, ref) = nothing
projection_read(::DbCatalogColumnToSyntaxLeaf, iomap, op) = nothing

# ── Shared node builder ───────────────────────────────────────────────────────
#
# Every non-leaf catalog level produces the same shape:
#   SyntaxNode(indentation=n):
#     children[1] = SyntaxLeaf(" name")               ← name leaf
#     children[2] = SyntaxNode(indentation=n+1):       ← body node
#                     children[1..n] = projected child outputs
# `children` is the node's own child CellVector (databases/schemas/tables/…).

function _catalog_syntax_node(recursion, ctx, selection, indentation::Int,
                              name_font::StyleFont, name_color::StyleColor,
                              label, children)
    child_iomaps = Cell(() -> begin
        [projection_printer_recurse(recursion, elem, child_context(ctx, ElementReference(i)))
         for (i, elem) in enumerate(children)]
    end)

    name_leaf = SyntaxLeaf(
        TextString("", name_font, color_default),
        TextString("", name_font, color_default),
        TextString(label, name_font, name_color),
        selection)

    body_node = SyntaxNode(
        TextString("", name_font, color_default),
        TextString("", name_font, color_default),
        TextString("", name_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        indentation + 1,
        Cell(false),
        Cell(nothing))

    sel = Cell(() -> begin
        path = selection
        path isa ConcreteReferencePath || return nothing
        path.head isa ProjectionReference ? path : nothing
    end)

    node = SyntaxNode(
        TextString("", name_font, color_default),
        TextString("", name_font, color_default),
        TextString("", name_font, color_default),
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]),
        indentation,
        Cell(false),
        sel)

    node, child_iomaps
end

# ── DbCatalogTableToSyntaxNode ────────────────────────────────────────────────

struct DbCatalogTableToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogTableToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_green) =
    DbCatalogTableToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogTableToSyntaxNode, recursion, table::DbCatalogTable, ctx)
    node, child_iomaps = _catalog_syntax_node(
        recursion, ctx, table.selection, 3, p.name_font, p.name_color,
        () -> " " * table.name, table.columns)
    ChildrenIoMap(p, table, node, child_iomaps)
end

map_reference_forward(::DbCatalogTableToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogTableToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogTableToSyntaxNode, iomap, op) = nothing

# ── DbCatalogSchemaToSyntaxNode ───────────────────────────────────────────────

struct DbCatalogSchemaToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogSchemaToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_blue) =
    DbCatalogSchemaToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogSchemaToSyntaxNode, recursion, schema::DbCatalogSchema, ctx)
    node, child_iomaps = _catalog_syntax_node(
        recursion, ctx, schema.selection, 2, p.name_font, p.name_color,
        () -> " " * schema.name, schema.tables)
    ChildrenIoMap(p, schema, node, child_iomaps)
end

map_reference_forward(::DbCatalogSchemaToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogSchemaToSyntaxNode, iomap, op) = nothing

# ── DbCatalogDatabaseToSyntaxNode ─────────────────────────────────────────────

struct DbCatalogDatabaseToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogDatabaseToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_red) =
    DbCatalogDatabaseToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogDatabaseToSyntaxNode, recursion, db::DbCatalogDatabase, ctx)
    node, child_iomaps = _catalog_syntax_node(
        recursion, ctx, db.selection, 1, p.name_font, p.name_color,
        () -> " " * db.name, db.schemas)
    ChildrenIoMap(p, db, node, child_iomaps)
end

map_reference_forward(::DbCatalogDatabaseToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogDatabaseToSyntaxNode, iomap, op) = nothing

# ── DbCatalogRdbmsToSyntaxNode ────────────────────────────────────────────────

struct DbCatalogRdbmsToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
DbCatalogRdbmsToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_red) =
    DbCatalogRdbmsToSyntaxNode(name_font, name_color)

function projection_print(p::DbCatalogRdbmsToSyntaxNode, recursion, rdbms::DbCatalogRdbms, ctx)
    node, child_iomaps = _catalog_syntax_node(
        recursion, ctx, rdbms.selection, 0, p.name_font, p.name_color,
        () -> " " * rdbms.host * ":" * string(rdbms.port), rdbms.databases)
    ChildrenIoMap(p, rdbms, node, child_iomaps)
end

map_reference_forward(::DbCatalogRdbmsToSyntaxNode, iomap, ref) = nothing
map_reference_backward(::DbCatalogRdbmsToSyntaxNode, iomap, ref) = nothing
projection_read(::DbCatalogRdbmsToSyntaxNode, iomap, op) = nothing

# ── Marker eligibility ──────────────────────────────────────────────────────────
#
# Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
# lands on non-empty catalog nodes (rdbms, database, schema, table) and never
# on leaf columns or empty body wrappers.
#
#   • indentation < 4          → not a column leaf
#   • children[2] is the body   → catalog node shape (name leaf + body node)
#   • body has children         → non-empty: there is something to fold
"""
    dbcatalog_marker_eligible(node) -> Bool

Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
lands on non-empty catalog nodes and never on leaf columns or empty body wrappers.
"""
dbcatalog_marker_eligible(::SyntaxLeaf) = false
function dbcatalog_marker_eligible(node::SyntaxNode)
    node.indentation < 4 || return false
    children = node.children
    length(children) >= 2 || return false
    body = children[2]
    body isa SyntaxNode && length(body.children) > 0
end

# ── Compound constructor ──────────────────────────────────────────────────────

function DbCatalogToSyntax()
    TypeDispatchingProjection(
        DbCatalogRdbms      => DbCatalogRdbmsToSyntaxNode(),
        DbCatalogDatabase   => DbCatalogDatabaseToSyntaxNode(),
        DbCatalogSchema     => DbCatalogSchemaToSyntaxNode(),
        DbCatalogTable      => DbCatalogTableToSyntaxNode(),
        DbCatalogColumn     => DbCatalogColumnToSyntaxLeaf(),
    )
end

end # module
