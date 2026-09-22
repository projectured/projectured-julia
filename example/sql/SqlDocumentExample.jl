function make_sql_document_example()
    # SELECT * FROM persons
    SqlSelectStatement("persons")
end

# Atomic SQL leaves — one meaningful instance each, for the catalog. These are the
# opaque display leaves (all_columns / column_name / table_name / scalar_value):
# non-editable, but navigable once the leaf stages carry the introduced-token caret.
make_sql_all_columns_document_example()  = SqlAllColumns()
make_sql_column_name_document_example()  = SqlColumnName("age")
make_sql_table_name_document_example()   = SqlTableName("persons")
make_sql_scalar_value_document_example() = SqlScalarValue(36)
make_sql_column_reference_document_example() = SqlColumnReference("age")
make_sql_table_expression_document_example() = SqlTableExpression("persons")

# Minimal non-empty compound (node) documents — for the catalog.
make_sql_comparison_document_example()       = SqlComparison(SqlColumnReference("a"), "=", SqlScalarValue(1))
make_sql_select_item_document_example()      = SqlSelectItem(SqlColumnReference("a"))
make_sql_select_statement_document_example() = SqlSelectStatement("persons")

make_sql_and_document_example() =
    SqlAnd(SqlComparison(SqlColumnReference("a"), "=", SqlScalarValue(1)),
           SqlComparison(SqlColumnReference("b"), "=", SqlScalarValue(2)))
make_sql_or_document_example() =
    SqlOr(SqlComparison(SqlColumnReference("a"), "=", SqlScalarValue(1)),
          SqlComparison(SqlColumnReference("b"), "=", SqlScalarValue(2)))
make_sql_not_document_example() =
    SqlNot(SqlComparison(SqlColumnReference("a"), "=", SqlScalarValue(1)))
make_sql_where_filter_condition_document_example() =
    SqlWhereFilterCondition(SqlComparison(SqlColumnReference("a"), "=", SqlScalarValue(1)))
make_sql_where_clause_document_example() =
    SqlWhereClause(make_sql_where_filter_condition_document_example())
make_sql_select_clause_document_example() =
    SqlSelectClause(SqlSelectItem(SqlColumnReference("a")))
make_sql_from_item_document_example() =
    SqlFromItem(SqlTableExpression("persons"))
make_sql_from_clause_document_example() =
    SqlFromClause(make_sql_from_item_document_example())
make_sql_join_on_condition_document_example() =
    SqlJoinOnCondition(SqlComparison(SqlColumnReference("a"), "=", SqlColumnReference("b")))
make_sql_joined_from_item_document_example() =
    SqlJoinedFromItem(SqlInnerJoin(), SqlTableExpression("orders"), make_sql_join_on_condition_document_example())
make_sql_join_using_condition_document_example() =
    SqlJoinUsingCondition(SqlColumnName("id"), SqlColumnName("name"))
make_sql_raw_expression_document_example() =
    SqlRawExpression("COUNT(*)")
make_sql_raw_condition_document_example() =
    SqlRawCondition("name LIKE 'A%'")
make_sql_subquery_from_item_document_example() =
    SqlSubqueryFromItem(SqlSelectStatement("persons"))
make_sql_column_definition_document_example() =
    SqlColumnDefinition("age", "integer")
make_sql_create_table_statement_document_example() =
    SqlCreateTableStatement(SqlTableName("persons"), [make_sql_column_definition_document_example()])
make_sql_create_schema_statement_document_example() =
    SqlCreateSchemaStatement("public")
make_sql_statement_list_document_example() =
    SqlStatementList([SqlSelectStatement("persons")])
make_sql_insert_statement_document_example() =
    SqlInsertStatement(SqlTableName("persons"), [SqlColumnName("name")], [SqlScalarValue("Ada")])
make_sql_update_assignment_document_example() =
    SqlUpdateAssignment(SqlColumnName("age"), SqlScalarValue(37))
make_sql_update_statement_document_example() =
    SqlUpdateStatement(SqlTableName("persons"), [make_sql_update_assignment_document_example()])

function make_sql_insert_document_example()
    # INSERT INTO persons (name, age) VALUES ('Ada', 36)
    SqlInsertStatement(
        SqlTableName("persons"),
        [SqlColumnName("name"), SqlColumnName("age")],
        [SqlScalarValue("Ada"), SqlScalarValue(36)])
end

function make_sql_update_document_example()
    # UPDATE persons SET age = 37 WHERE name = 'Ada'
    SqlUpdateStatement(
        SqlTableName("persons"),
        [SqlUpdateAssignment(SqlColumnName("age"), SqlScalarValue(37))],
        SqlWhereClause(SqlWhereFilterCondition(SqlComparison(
            SqlColumnReference(SqlColumnName("name")),
            "=",
            SqlScalarValue("Ada")))))
end

function make_sql_nested_document_example()
    # SELECT sub.person_name, sub.person_age
    # FROM persons JOIN (SELECT p.name AS person_name, p.age AS person_age
    #                    FROM persons AS p WHERE p.name <> 'X') AS sub
    #              ON persons.name = sub.person_name
    # WHERE sub.person_name <> 'X'
    SqlSelectStatement(
        SqlSelectClause(
            SqlSelectItem(SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name"))),
            SqlSelectItem(SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_age")))),
        SqlFromClause(SqlFromItem(
            SqlTableExpression(SqlTableName("persons")),
            CellVector([SqlJoinedFromItem(
                SqlInnerJoin(),
                SqlSubqueryFromItem(
                    SqlSelectStatement(
                        SqlSelectClause(
                            SqlSelectItem(
                                SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name")),
                                SqlColumnAlias("person_name")),
                            SqlSelectItem(
                                SqlColumnReference(SqlTableAlias("p"), SqlColumnName("age")),
                                SqlColumnAlias("person_age"))),
                        SqlFromClause(SqlFromItem(
                            SqlTableExpression(SqlTableName("persons"), SqlTableAlias("p")))),
                        SqlWhereClause(
                            SqlWhereFilterCondition(SqlComparison(
                                SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name")),
                                "<>",
                                SqlScalarValue("X"))))),
                    SqlTableAlias("sub")),
                SqlJoinOnCondition(SqlComparison(
                    SqlColumnReference(SqlTableName("persons"), SqlColumnName("name")),
                    "=",
                    SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name")))))]),
            Cell(nothing))),
        SqlWhereClause(
            SqlWhereFilterCondition(SqlComparison(
                SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name")),
                "<>",
                SqlScalarValue("X")))))
end
