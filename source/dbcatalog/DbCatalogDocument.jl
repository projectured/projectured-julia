"""
    DbCatalogDocumentModule

Document hierarchy modelling the PostgreSQL catalog tree:
`DbCatalogRdbms → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn`

No global state — constructors are plain wrappers with no side effects.
"""
module DbCatalogModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: Reference
export DbCatalogDocument
import ..SqlDocumentModule: SqlColumnDefinition, SqlCreateTableStatement,
                            SqlCreateSchemaStatement, SqlStatementList,
                            SqlTableName, SqlColumnName
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: ElementReferenceStep
import ..PrinterContextModule: make_child_context, with_property, get_property
export DbCatalogRdbmsToSql, DbCatalogDatabaseToSql, DbCatalogSchemaToSql,
       DbCatalogTableToSql, DbCatalogColumnToSql, DbCatalogToSql
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_red, color_solarized_green, color_solarized_magenta
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReference, EmptyReference, Reference,
                           ElementReferenceStep, PositionReferenceStep, RangeReferenceStep,
                           FieldReferenceStep, extend_reference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep, make_introduced_reference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..PrinterContextModule: make_child_context
import ..SyntaxToTextModule: SyntaxCompoundToText, _syntax_to_flat
import ..OperationModule: ReplaceSelectionOperation
export DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode, DbCatalogSchemaToSyntaxNode,
       DbCatalogDatabaseToSyntaxNode, DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
       is_dbcatalog_marker_eligible
export DbCatalogRdbms, DbCatalogDatabase




abstract type DbCatalogDocument <: Document end

@document struct DbCatalogRdbms <: DbCatalogDocument
    host::String
    port::Int
    databases::CellVector
end

@document struct DbCatalogDatabase <: DbCatalogDocument
    name::String
    schemas::CellVector
end

@document struct DbCatalogSchema <: DbCatalogDocument
    name::String
    tables::CellVector
end

@document struct DbCatalogTable <: DbCatalogDocument
    name::String
    columns::CellVector
end

@document struct DbCatalogColumn <: DbCatalogDocument
    name::String
    data_type::String
end

# Concise `show` for the five catalog document types. The @document macro's
# default lists every field (host / port / CellVector spew) which is unusable
# in the REPL and useless in stack traces. These variants render only the
# identifying scalar(s), matching the T5 expectations.
Base.show(io::IO, r::DbCatalogRdbms)    = print(io, "DbCatalogRdbms(", r.host, ":", r.port, ")")
Base.show(io::IO, d::DbCatalogDatabase) = print(io, "DbCatalogDatabase(", d.name, ")")
Base.show(io::IO, s::DbCatalogSchema)   = print(io, "DbCatalogSchema(", s.name, ")")
Base.show(io::IO, t::DbCatalogTable)    = print(io, "DbCatalogTable(", t.name, ")")
Base.show(io::IO, c::DbCatalogColumn)   = print(io, "DbCatalogColumn(", c.name, "::", c.data_type, ")")


include("DbCatalogToSql.jl")
include("DbCatalogToSyntax.jl")

end # module
