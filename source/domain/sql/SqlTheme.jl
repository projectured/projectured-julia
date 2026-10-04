# Fragment of `SqlModule` — the theme of the SQL syntax: the text of a
# keyword, of plain text, and of a table name.

"""
    SqlTheme

The fonts and the colors of a SQL statement: its keywords, its table names and
its other words.

The theme of the SQL projections. `@theme` declares it, so `ScaledSqlTheme`
holds each value times its scale, and `SqlTheme()` is the default theme.

The fields are the text styles of a keyword, plain text and a table name.
Each field has a docstring that says what it draws, which the appearance tab
shows under its name.

The builder gives each SQL projection its styles with `get_sql_style`, from a
theme scaled or not; a projection built with no styles holds the plain values
of the default theme.
"""
@theme struct SqlTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A reserved word, such as `SELECT`, `FROM`, `WHERE` or `AND`."
    keyword_text::TextRole = TextRole(:keyword; weight = 700)
    "A column, a value, a raw expression, a data type, or any other identifier that is not a keyword or a table name."
    plain_text::TextRole   = TextRole(:text)
    "A table name."
    name_text::TextRole    = TextRole(:definition)
    "The brackets, the commas, the spaces and the semicolons between the parts of a statement."
    punctuation_text::TextRole = TextRole(:punctuation; weight = 700)
end

# The plain font of a SQL projection that holds only a `StyleFont`, not a full
# style: the font of `plain_text` in the theme `theme`, scaled or not.
function _get_sql_font(theme)
    theme === nothing && return get_theme_defaults(SqlTheme).plain_text.font
    make_theme_cell(StyleFont, theme, values -> values.plain_text.font)
end
