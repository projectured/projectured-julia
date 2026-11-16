"""
    SqlModule

SQL statement documents: select, insert, update and other statements, after the ANSI
and PostgreSQL conventions. The AST is database-agnostic; `SqlToSyntax` renders it
and `SqlToCellTable` executes it against a `DatabaseInstance`.
"""
module SqlModule

using ..KernelModule
using ..PlatformModule
using ..ReferenceModule   # `@document` injects the implicit `selection::Union{Nothing, Reference}` field

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content,
                              get_file_format_extensions, get_file_format_domain,
                              parse_document_string, get_file_type, get_file_format
import ..NaturalModule: make_syntax_projection, find_natural_file_format
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..DisplayModule: make_workload_file

export SqlStatement, SqlSelectExpression, SqlFromBaseItem, SqlJoinType,
       SqlJoinCondition, SqlJoinConditionExpression, SqlWhereCondition, SqlBooleanExpression
export parse_sql_text, parse_sql_file
export SqlTheme, ScaledSqlTheme
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
export SqlFile, SqlFileFormat


include("SqlDocument.jl")
include("SqlParser.jl")
include("SqlTheme.jl")
include("SqlToSyntax.jl")
include("SqlFile.jl")

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{SqlFile}) =
    (; name = "a.sql", text = "SELECT name FROM people;\n", shown = r"people")

end # module
