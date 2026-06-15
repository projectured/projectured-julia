function make_sql_document_example()
    # SELECT * FROM persons
    SqlSelectStatement("persons")
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
