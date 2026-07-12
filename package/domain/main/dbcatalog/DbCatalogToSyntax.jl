"""
    DbCatalogToSyntaxModule

DbCatalog → SyntaxDocument projection. Maps the catalog hierarchy to syntax
tree shapes with keyword grouping nodes:

    DbCatalogRdbms    → entity " host:port" → keyword " Databases" → body
    DbCatalogDatabase → entity " dbname"    → keyword " Schemas"   → body
    DbCatalogSchema   → entity " schema"    → keyword " Tables"    → body
    DbCatalogTable    → entity " table"     → keyword " Columns"   → body
    DbCatalogColumn   → SyntaxLeaf " column::type"

Each non-leaf entity node is collapsible and contains a single keyword child:
  entity_node  (ind=-1, open=" name"):  collapsible, marker-eligible
    keyword_node (ind=0,  open=" Keyword"): collapsible, marker-eligible
      keyword_body (ind=-1, open=""):     children = projected items

Using `indentation = -1` avoids trailing newlines that create blank lines,
while still rendering children with `\\n + indent`.

Selection mapping (School A — delegate child tails through stored child IO maps):
  Input:  <field>[i].rest        (e.g. databases[2].child_path)
  Output: children[1].children[1].children[i].delegated(rest)
The three levels correspond to: keyword_node → keyword_body → actual child.
"""
module DbCatalogToSyntaxModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..DbCatalogDocumentModule: DbCatalogRdbms, DbCatalogDatabase,
                                   DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_red, color_solarized_green, color_solarized_magenta
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, ReferencePath,
                           ElementReference, PositionReference, RangeReference,
                           FieldReference, append_reference
import ..ProjectionReferenceModule: ProjectionReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: make_child_context
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
import ..OperationModule: ReplaceSelectionOperation
export DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode, DbCatalogSchemaToSyntaxNode,
       DbCatalogDatabaseToSyntaxNode, DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
       dbcatalog_marker_eligible

# ── DbCatalogColumnToSyntaxLeaf ───────────────────────────────────────────────

@projection struct DbCatalogColumnToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

function print_document(p::DbCatalogColumnToSyntaxLeaf, recursion, col::DbCatalogColumn, ctx)
    sel = Cell(() -> begin
        path = col.selection
        path === nothing && return nothing
        map_reference_forward(p, nothing, path)
    end)
    SimpleIoMap(p, col, SyntaxLeaf(
        TextString(() -> " " * col.name * "::" * col.data_type, p.style);
        selection=sel))
end

function map_reference_forward(::DbCatalogColumnToSyntaxLeaf, iomap, reference)
    reference = reference
    reference isa EmptyReferencePath && return EmptyReferencePath()
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa ProjectionReference || return nothing
    return h.output_path
end

function map_reference_backward(p::DbCatalogColumnToSyntaxLeaf, iomap, reference)
    reference isa EmptyReferencePath && return EmptyReferencePath()
    reference === nothing && return nothing
    ConcreteReferencePath(Cell(ProjectionReference(p, reference)), Cell(EmptyReferencePath()))
end

function read_intent(p::DbCatalogColumnToSyntaxLeaf, iomap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    ReplaceSelectionOperation(result)
end

# ── Shared reference mapping helpers ─────────────────────────────────────────
#
# All non-leaf catalog projections share the same 3-level output shape:
#   entity_node → keyword_node → keyword_body → children
# so the reference mapping logic is factored into shared helpers parameterised
# by the input-domain children field name ("databases", "schemas", etc.).

"""
Forward: `<field_name>[i].rest → children[1].children[i].delegated(rest)`
(entity → keyword group `children[1]` → item `children[i]`).
"""
function _catalog_forward_ref(p, iomap::ChildrenIoMap, reference, field_name::String)
    reference = reference
    reference isa EmptyReferencePath && return EmptyReferencePath()
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa ProjectionReference && h.projection === p && return reference
    # Match: field_name{s:e}.rest (FieldReference + RangeReference + tail)
    h isa FieldReference && h.name == field_name || return nothing
    rest = reference.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    child_i = h2.start + 1
    child_rest = rest.tail
    iomaps = iomap.child_iomaps[]
    1 <= child_i <= length(iomaps) || return nothing
    child = iomaps[child_i]
    inner = map_reference_forward(child.projection, child, child_rest)
    inner === nothing && return nothing
    @reference ::SyntaxNode.children[1].children[child_i].^(inner)
end

"""
Backward: `children[1].children[i].rest → <field_name>[i].delegated(rest)`
Peels 2 levels of children (keyword group, then the actual item).
"""
function _catalog_backward_ref(p, iomap::ChildrenIoMap, reference, field_name::String)
    reference isa EmptyReferencePath && return EmptyReferencePath()
    # Peel: children[1] (the keyword group), then children[i] (the item).
    @reference_case reference begin
        ::SyntaxNode.children[1].rest1... => begin
            @reference_case rest1 begin
                ::SyntaxNode.children{s:e}.rest2... => begin
                    child_i = s + 1
                    iomaps = iomap.child_iomaps[]
                    1 <= child_i <= length(iomaps) || return nothing
                    child = iomaps[child_i]
                    inner = map_reference_backward(child.projection, child, rest2)
                    inner === nothing && return nothing
                    ConcreteReferencePath(
                        Cell(FieldReference(field_name)),
                        Cell(ConcreteReferencePath(
                            Cell(ElementReference(child_i)),
                            Cell(inner))))
                end
                _ => nothing
            end
        end
        _ => nothing
    end
end

"""
Reader for `ReplaceSelectionOperation`: try backward mapping, fall back to
`ProjectionReference(p, {flat})` for structural positions (entity names,
keyword labels, whitespace).
"""
function _catalog_read_selection(p, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(
        ConcreteReferencePath(Cell(ProjectionReference(p,
            ConcreteReferencePath(Cell(PositionReference(flat)), Cell(EmptyReferencePath())))),
            Cell(EmptyReferencePath())))
end

# ── Lazy-expansion helper ─────────────────────────────────────────────────────
#
# A catalog level's child collection is a *lazy* `CellVector` whose thunk queries
# the database only when forced (see `DatabaseInstanceToDbCatalog`). To support
# lazy expansion, an entity node starts **collapsed** unless its children are
# *already materialized* — so the initial render queries nothing, and expanding a
# node (flipping `collapsed`) is what first forces its child query, which then
# projects into syntax and widgets.
#
# "Already materialized" is read **without forcing**: the `CellVector`'s backing
# `elements` cell is a computed cell that becomes `valid` only after it has been
# evaluated (the query ran) and stays `valid` until invalidated. A value-backed
# (eagerly built) collection is `valid` from construction, so non-lazy children
# render expanded. A pre-forced lazy collection (e.g. via `explore_dbcatalog!`)
# also reads `valid`, so only the explored path opens up front.
function _children_realized(children)
    children isa CellVector || return true
    cell = getfield(children, :elements)
    cell isa Cell ? getfield(cell, :valid) : true
end

# ── Shared node builder ───────────────────────────────────────────────────────
#
# Every non-leaf catalog level produces the shape:
#   entity_node  (ind=-1, open=" name"):     ← the named entity; always expanded
#     keyword_node (ind=-1, open=" Keyword"): ← a collapsible *kind-of-child*
#       child[1..n] = projected child outputs ← its items, held directly
#
# The keyword node is its own collapsible group (a "kind" of child — Columns,
# and in future Indexes, etc. — sit side by side as sibling keyword groups under
# one entity). It is **collapsed unless its child collection is already
# materialized**, so the initial render queries nothing and expanding the group
# is what first forces its lazy `CellVector` (the DB query), which then projects
# into syntax and widgets. The entity node merely groups its keyword(s) and stays
# expanded (the user can still fold it via its header).
#
# Using ind=-1 (rather than a positive value) enters the newline branch
# (children get \n + indent) but skips the trailing \n + indent that would
# otherwise create blank lines between sibling items.
#
# Selection is wired via the deferred-iomap trick: the entity_node's selection
# cell reads from the input document's selection and maps it forward through
# this projection's own map_reference_forward. The iomap_cell is returned so
# the caller can set it after building the ChildrenIoMap.

function _catalog_syntax_node(p, recursion, ctx, input_doc,
                              name_style::StyleText,
                              keyword::String, label, children)
    child_iomaps = Cell(() -> begin
        [print_child(recursion, elem, make_child_context(ctx, ElementReference(i)))
         for (i, elem) in enumerate(children)]
    end)

    # The keyword group holds the projected items directly and is the lazy /
    # collapsible unit. Collapsed until its child collection is materialized.
    keyword_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]);
        open=TextString(" " * keyword, font_ubuntu_monospace_regular_20, color_default),
        indentation=-1,
        collapsed=Cell(!_children_realized(children)))

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = input_doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    # The entity groups its keyword(s); it stays expanded (foldable by the user).
    entity_node = SyntaxNode(
        CellVector(Cell[Cell(keyword_node)]);
        open=TextString(label, name_style),
        indentation=-1,
        selection=sel)

    entity_node, child_iomaps, iomap_cell
end

# ── DbCatalogTableToSyntaxNode ────────────────────────────────────────────────

@projection struct DbCatalogTableToSyntaxNode
    name::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
end

function print_document(p::DbCatalogTableToSyntaxNode, recursion, table::DbCatalogTable, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, table, p.name,
        "Columns", () -> " " * table.name, table.columns)
    iomap = ChildrenIoMap(p, table, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogTableToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "columns")
map_reference_backward(p::DbCatalogTableToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "columns")
read_intent(p::DbCatalogTableToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation) =
    _catalog_read_selection(p, iomap, op)

# ── DbCatalogSchemaToSyntaxNode ───────────────────────────────────────────────

@projection struct DbCatalogSchemaToSyntaxNode
    name::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::DbCatalogSchemaToSyntaxNode, recursion, schema::DbCatalogSchema, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, schema, p.name,
        "Tables", () -> " " * schema.name, schema.tables)
    iomap = ChildrenIoMap(p, schema, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogSchemaToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "tables")
map_reference_backward(p::DbCatalogSchemaToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "tables")
read_intent(p::DbCatalogSchemaToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation) =
    _catalog_read_selection(p, iomap, op)

# ── DbCatalogDatabaseToSyntaxNode ─────────────────────────────────────────────

@projection struct DbCatalogDatabaseToSyntaxNode
    name::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
end

function print_document(p::DbCatalogDatabaseToSyntaxNode, recursion, db::DbCatalogDatabase, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, db, p.name,
        "Schemas", () -> " " * db.name, db.schemas)
    iomap = ChildrenIoMap(p, db, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogDatabaseToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "schemas")
map_reference_backward(p::DbCatalogDatabaseToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "schemas")
read_intent(p::DbCatalogDatabaseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation) =
    _catalog_read_selection(p, iomap, op)

# ── DbCatalogRdbmsToSyntaxNode ────────────────────────────────────────────────

@projection struct DbCatalogRdbmsToSyntaxNode
    name::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
end

function print_document(p::DbCatalogRdbmsToSyntaxNode, recursion, rdbms::DbCatalogRdbms, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, rdbms, p.name,
        "Databases", () -> " " * rdbms.host * ":" * string(rdbms.port), rdbms.databases)
    iomap = ChildrenIoMap(p, rdbms, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogRdbmsToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "databases")
map_reference_backward(p::DbCatalogRdbmsToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "databases")
read_intent(p::DbCatalogRdbmsToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation) =
    _catalog_read_selection(p, iomap, op)

# ── Marker eligibility ──────────────────────────────────────────────────────────
#
# Entity nodes and keyword nodes carry their label in the `open` field.
# Body nodes (keyword_body) have empty `open`. This lets us mark exactly the
# collapsible named nodes — entities and keywords — while skipping body wrappers.
"""
    dbcatalog_marker_eligible(node) -> Bool

Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
lands on entity nodes and keyword nodes (which carry a label in `open`), but not
on body wrappers or column leaves.
"""
dbcatalog_marker_eligible(::SyntaxLeaf) = false
# Eligibility keys off the label alone (a non-empty `open`): entity and keyword
# nodes carry one, body/leaf nodes do not. Deliberately does NOT inspect
# `node.children` — a keyword group's children are a lazy `CellVector` whose
# length can't be read without forcing the database query, which would defeat
# lazy expansion.
dbcatalog_marker_eligible(node::SyntaxNode) = !isempty(node.open.content::AbstractString)

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
