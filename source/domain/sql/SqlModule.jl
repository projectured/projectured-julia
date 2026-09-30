"""
    SqlModule

The SQL statement document model (ANSI/PostgreSQL conventions). The AST is
database-agnostic; `SqlToSyntax` renders it and `SqlToCellTable` executes it
against a `DatabaseInstance`.
"""
module SqlModule

using ..KernelModule
using ..PlatformModule
using ..ReferenceModule   # `@document` injects the implicit `selection::Union{Nothing, Reference}` field

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export SqlStatement, SqlSelectExpression, SqlFromBaseItem, SqlJoinType,
       SqlJoinCondition, SqlJoinConditionExpression, SqlWhereCondition, SqlBooleanExpression
export parse_sql_text, parse_sql_file
export SqlInsertionToSyntaxLeaf,
       SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
       SqlColumnNameToSyntaxLeaf, SqlTableNameToSyntaxLeaf,
       SqlTableExpressionToSyntaxLeaf, SqlSubqueryFromItemToSyntaxNode, SqlJoinTypeToSyntaxLeaf,
       SqlSelectItemToSyntaxNode, SqlSelectClauseToSyntaxNode,
       SqlFromItemToSyntaxNode, SqlFromClauseToSyntaxNode,
       SqlJoinedFromItemToSyntaxNode, SqlJoinOnConditionToSyntaxNode,
       SqlJoinUsingConditionToSyntaxNode,
       SqlWhereFilterConditionToSyntaxNode, SqlWhereClauseToSyntaxNode,
       SqlScalarValueToSyntaxLeaf, SqlRawExpressionToSyntaxLeaf, SqlRawConditionToSyntaxLeaf,
       SqlComparisonToSyntaxNode,
       SqlBooleanBinaryToSyntaxNode, SqlNotToSyntaxNode,
       SqlSelectStatementToSyntaxNode,
       SqlInsertStatementToSyntaxNode, SqlUpdateAssignmentToSyntaxNode,
       SqlUpdateStatementToSyntaxNode,
       SqlColumnDefinitionToSyntaxNode, SqlCreateTableStatementToSyntaxNode,
       SqlCreateSchemaStatementToSyntaxNode, SqlStatementListToSyntaxNode, SqlToSyntax
export SqlSelectStatement, SqlSelectClause, SqlFromClause, SqlWhereClause, SqlNothing, SqlDocument
export SqlFile


include("SqlDocument.jl")
include("SqlParser.jl")
include("SqlToSyntax.jl")
include("SqlFile.jl")

end # module
