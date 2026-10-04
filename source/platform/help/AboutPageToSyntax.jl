# Fragment of `HelpModule`.
#
# Projects an `AboutPage` onto a `SyntaxNode`: the name of the program, its
# sentence, then its version, the Julia version that runs, and its home page, one
# line each. An empty field has no line.
#
# The lines are made in a thunk, so a change of a field of the page draws again.
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
#
# The projection holds its styles and no theme; `make_about_page_projection`
# fills them from a theme.
@projection UntrackedCell struct AboutPageToSyntax
    name::StyleText = get_help_style(nothing, :title_text)
    summary::StyleText = get_help_style(nothing, :description_text)
    detail::StyleText = get_help_style(nothing, :detail_text)
end

"""
    make_about_page_projection(; theme = nothing) -> AboutPageToSyntax

The projection of the about page, with the styles of `theme`: a `HelpTheme`,
scaled or not, or the default styles for `nothing`.
"""
function make_about_page_projection(; theme = nothing)
    get_style(name) = get_help_style(theme, name)
    AboutPageToSyntax(; name = get_style(:title_text), summary = get_style(:description_text),
                      detail = get_style(:detail_text))
end

function print_document(p::AboutPageToSyntax, recursion, page::AboutPage, ctx::PrinterContext)
    SimpleIoMap(p, page, SyntaxNode(() -> _make_about_lines(p, page); sep = TextString("\n")))
end

function _make_about_lines(p::AboutPageToSyntax, page::AboutPage)
    lines = SyntaxDocument[SyntaxLeaf(TextString(page.name, p.name))]
    isempty(page.summary) || push!(lines, SyntaxLeaf(TextString(page.summary, p.summary)))
    push!(lines, SyntaxLeaf(TextString("", p.detail)))
    isempty(page.version) || push!(lines, SyntaxLeaf(TextString("Version " * page.version, p.detail)))
    push!(lines, SyntaxLeaf(TextString("Julia " * string(VERSION), p.detail)))
    isempty(page.homepage) || push!(lines, SyntaxLeaf(TextString(page.homepage, p.detail)))
    lines
end
