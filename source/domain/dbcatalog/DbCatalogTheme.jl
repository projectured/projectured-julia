# Fragment of `DbCatalogModule` — the theme of the catalog syntax: a column, a
# table, a schema, a database and an RDBMS, and the keyword that opens a group
# of children.

"""
    DbCatalogTheme

The fonts and the colors of a database catalog: a column, a table, a schema, a
database and the keyword that opens a group.

The theme of the DbCatalog projections. `@theme` declares it, so
`ScaledDbCatalogTheme` holds each value times its scale, and
`DbCatalogTheme()` is the default theme.

The fields are the text styles of a column, a table, a schema, a database and
the keyword that opens a group of children. Each field has a docstring that
says what it draws, which the appearance tab shows under its name.

The builder gives each DbCatalog projection its styles with
`get_db_catalog_style`, from a theme scaled or not; a projection built with no
styles holds the plain values of the default theme.
"""
@theme struct DbCatalogTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A column, with its type."
    column_text::TextRole   = TextRole(:field)
    "The name of a table."
    table_text::TextRole    = TextRole(:type_name; weight = 700)
    "The name of a schema."
    schema_text::TextRole   = TextRole(:module_name; weight = 700)
    "The name of a database and of an RDBMS."
    database_text::TextRole = TextRole(:module_name; weight = 700)
    "The keyword that opens a group of children, such as \"Columns\", \"Tables\", \"Schemas\" or \"Databases\"."
    keyword_text::TextRole  = TextRole(:text_muted)
end
