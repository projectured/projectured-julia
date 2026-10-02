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

A file-system projection reads the scaled theme through its `UntrackedCell`
style fields; with no theme it holds the plain values of the default theme.
The widget tree of the file system follows the widget theme instead.
"""
@theme struct FileSystemTheme
    "The basename of a file."
    file_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_blue)
    "The name of a directory."
    directory_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20; weight = 700), color_solarized_red)
end

# The style field of a file-system projection that holds the text `name` of
# the theme `theme`: a `FileSystemTheme`, a scaled one, or `nothing` for the
# default values.
_get_filesystem_style(theme, name::Symbol) =
    make_style_field(FileSystemTheme, scale_theme(theme), StyleText; name)
