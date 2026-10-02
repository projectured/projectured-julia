# Fragment of `DbCatalogModule` — the theme of the catalog syntax: a column, a
# table, a schema, a database and an RDBMS, and the keyword that opens a group
# of children.

"""
    DbCatalogTheme

The theme of the DbCatalog projections. `@theme` declares it, so
`ScaledDbCatalogTheme` holds each value times its scale, and
`DbCatalogTheme()` is the default theme.

- `column_text` — a column, with its type.
- `table_text` — the name of a table.
- `schema_text` — the name of a schema.
- `database_text` — the name of a database and of an RDBMS.
- `keyword_text` — the keyword that opens a group of children, such as
  "Columns", "Tables", "Schemas" or "Databases".

A DbCatalog projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct DbCatalogTheme
    column_text::StyleText   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    table_text::StyleText    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
    schema_text::StyleText   = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    database_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
    keyword_text::StyleText  = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

# The style field of a DbCatalog projection that holds the text `name` of the
# theme `theme`: a `DbCatalogTheme`, a scaled one, or `nothing` for the default
# values.
_get_dbcatalog_style(theme, name::Symbol) = make_style_field(DbCatalogTheme, scale_theme(theme), StyleText, name)
