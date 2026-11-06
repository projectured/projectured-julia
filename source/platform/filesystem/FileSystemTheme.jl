# Fragment of `FileSystemModule` — the theme of the file-system tree: the text
# of a file and the text of a directory.

"""
    FileSystemTheme

The fonts and the colors of a file and a directory in the Explorer tab.

The theme of the file-system tree, as syntax. `@theme` declares it, so
`ScaledFileSystemTheme` holds each value times its scale, and
`FileSystemTheme()` is the default theme.

The fields are the text styles of a file and a directory. Each field has a
docstring that says what it draws, which the appearance tab shows under its
name.

`FileSystemToSyntax` gives the projections of the file-system tree their
styles with `get_file_system_style`, from a theme scaled or not; a projection
built with no styles holds the plain values of the default theme. The widget
tree of the file system follows the widget theme instead.
"""
@theme struct FileSystemTheme
    "The basename of a file."
    file_text::ThemeText = TextRole(:text; font_role = :text)
    "The name of a directory."
    directory_text::ThemeText = TextRole(:module_name; font_role = :text, weight = 400)
end
