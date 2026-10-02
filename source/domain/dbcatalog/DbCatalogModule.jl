"""
    DbCatalogModule

Document hierarchy modelling the PostgreSQL catalog tree:
`DbCatalogRdbms → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn`

No global state — constructors are plain wrappers with no side effects.
"""
module DbCatalogModule

using ..KernelModule
using ..PlatformModule
using ..SqlModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export DbCatalogDocument
export DbCatalogRdbmsToSql, DbCatalogDatabaseToSql, DbCatalogSchemaToSql,
       DbCatalogTableToSql, DbCatalogColumnToSql, DbCatalogToSql
export DbCatalogTheme, ScaledDbCatalogTheme
export DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode, DbCatalogSchemaToSyntaxNode,
       DbCatalogDatabaseToSyntaxNode, DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
       is_dbcatalog_marker_eligible
export DbCatalogRdbms, DbCatalogDatabase


include("DbCatalogDocument.jl")
include("DbCatalogToSql.jl")
include("DbCatalogTheme.jl")
include("DbCatalogToSyntax.jl")

end # module
