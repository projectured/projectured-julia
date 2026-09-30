# Fragment of `HelpModule`.
#
# Projects an `AboutPage` onto a `SyntaxNode`: the name of the program, its
# sentence, then its version, the Julia version that runs, and its home page, one
# line each. An empty field has no line.
#
# The lines are made in a thunk, so a change of a field of the page draws again.
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
@projection struct AboutPageToSyntax
    name::ImmutableCell{StyleText} = StyleText(font_dejavu_sans_bold_24, color_slate_900)
    summary::ImmutableCell{StyleText} = StyleText(font_dejavu_sans_regular_16, color_slate_700)
    detail::ImmutableCell{StyleText} = StyleText(font_dejavu_sans_regular_16, color_slate_500)
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
