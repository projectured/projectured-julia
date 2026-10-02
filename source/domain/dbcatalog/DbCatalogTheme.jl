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

A DbCatalog projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct DbCatalogTheme
    "A column, with its type."
    column_text::StyleText   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "The name of a table."
    table_text::StyleText    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
    "The name of a schema."
    schema_text::StyleText   = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    "The name of a database and of an RDBMS."
    database_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
    "The keyword that opens a group of children, such as \"Columns\", \"Tables\", \"Schemas\" or \"Databases\"."
    keyword_text::StyleText  = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

# The style field of a DbCatalog projection that holds the text `name` of the
# theme `theme`: a `DbCatalogTheme`, a scaled one, or `nothing` for the default
# values.
_get_dbcatalog_style(theme, name::Symbol) = make_style_field(DbCatalogTheme, scale_theme(theme), StyleText; name)
