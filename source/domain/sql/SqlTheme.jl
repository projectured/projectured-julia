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

A SQL projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct SqlTheme
    "A reserved word, such as `SELECT`, `FROM`, `WHERE` or `AND`."
    keyword_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20; weight = 700), color_solarized_blue)
    "A column, a value, a raw expression, a data type, or any other identifier that is not a keyword or a table name."
    plain_text::StyleText   = StyleText(StyleFont("Ubuntu Mono", 20), color_default)
    "A table name."
    name_text::StyleText    = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_green)
end

# The style field of a SQL projection that holds the text `name` of the theme
# `theme`: a `SqlTheme`, a scaled one, or `nothing` for the default values.
_get_sql_style(theme, name::Symbol) = make_style_field(SqlTheme, scale_theme(theme), StyleText; name)

# The plain font of a SQL projection that holds only a `StyleFont`, not a full
# style: the font of `plain_text` in the theme `theme`, scaled or not.
function _get_sql_font(theme)
    scaled = scale_theme(theme)
    scaled === nothing ? get_theme_defaults(SqlTheme).plain_text.font :
                         make_theme_cell(StyleFont, scaled, s -> s.plain_text.font)
end

# The value that the role `name` of the SQL theme has at this print: the style of a
# delimiter that a printer builds, such as the comma of a list. With no theme it
# is the default value, which is the style of a bare `TextString`.
_get_sql_text(theme, name::Symbol) = unwrap_cell(_get_sql_style(theme, name))
