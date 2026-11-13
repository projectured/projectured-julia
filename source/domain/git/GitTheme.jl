# The theme of the pages of the git domain: the style of each kind of line of a git
# text, and the gap between the parts of a page.

"""
    GitTheme

The colors and the fonts of the texts of the git domain, one for each kind of line
of a [`GitTextLine`](@ref): the subject, the facts and the message of a commit, the
heading and the rows of the list of the changed files, the path of a changed file,
the lines of a diff and of a file at a revision, and the notes. Also the gap
between the parts of a page.

`@theme` declares it, so `ScaledGitTheme` holds each value times its scale, and
`GitTheme()` is the default theme. A page takes its styles with `get_git_style`,
from a theme scaled or not.
"""
@theme struct GitTheme
    "The subject of a commit, at the top of its page."
    subject_text::ThemeText = TextRole(:text; font_role = :title)
    "The hash, the author, the date and the parents of a commit, and the kind and the counts of a change."
    fact_text::ThemeText = TextRole(:text_muted; font_role = :quiet)
    "The message of a commit, after its subject."
    message_text::ThemeText = TextRole(:text; font_role = :document_text)
    "The heading of the list of the changed files."
    section_text::ThemeText = TextRole(:text_muted; font_role = :section)
    "A row of the list of the changed files: the kind, the path and the counts."
    file_text::ThemeText = TextRole(:text; font_role = :code)
    "The path of a changed file, above its diff, and of a file at a revision."
    path_text::ThemeText = TextRole(:text; font_role = :code, weight = 700)
    "The first line of a hunk, which says where the hunk starts on each side."
    hunk_text::ThemeText = TextRole(:info_text; font_role = :code)
    "A kept line of a diff, and a line of a file at a revision."
    kept_text::ThemeText = TextRole(:text; font_role = :code)
    "A removed line of a diff."
    removed_text::ThemeText = TextRole(:error_text; font_role = :code)
    "An added line of a diff."
    added_text::ThemeText = TextRole(:success_text; font_role = :code)
    "The line of a file at a revision that the open of the file names."
    marked_text::ThemeText = TextRole(:accent_text; font_role = :code, weight = 700)
    "A note, such as a diff that git still reads, and an empty line between two parts."
    note_text::ThemeText = TextRole(:text_faint; font_role = :quiet)
    "The words of git for a read that failed."
    failure_text::ThemeText = TextRole(:error_text; font_role = :text)
    "The gap between the title of a file at a revision and its text."
    gap::Spacing = Spacing(8)
end
