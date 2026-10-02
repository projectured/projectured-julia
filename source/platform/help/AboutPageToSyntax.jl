# Fragment of `HelpModule`.
#
# Projects an `AboutPage` onto a `SyntaxNode`: the name of the program, its
# sentence, then its version, the Julia version that runs, and its home page, one
# line each. An empty field has no line.
#
# The lines are made in a thunk, so a change of a field of the page draws again.
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
@projection UntrackedCell struct AboutPageToSyntax
    theme::Any = nothing
    name::StyleText = _get_help_style(theme, :title_text)
    summary::StyleText = _get_help_style(theme, :description_text)
    detail::StyleText = _get_help_style(theme, :detail_text)
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
