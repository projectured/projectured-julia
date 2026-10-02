# Fragment of `FileSystemModule` — the theme of the file-system tree: the text
# of a file and the text of a directory.

"""
    FileSystemTheme

The theme of the file-system tree, as syntax. `@theme` declares it, so
`ScaledFileSystemTheme` holds each value times its scale, and
`FileSystemTheme()` is the default theme.

- `file_text` — the basename of a file.
- `directory_text` — the name of a directory.

A file-system projection reads the scaled theme through its `UntrackedCell`
style fields; with no theme it holds the plain values of the default theme.
The widget tree of the file system follows the widget theme instead.
"""
@theme struct FileSystemTheme
    file_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    directory_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
end

# The style field of a file-system projection that holds the text `name` of
# the theme `theme`: a `FileSystemTheme`, a scaled one, or `nothing` for the
# default values.
_get_filesystem_style(theme, name::Symbol) =
    make_style_field(FileSystemTheme, scale_theme(theme), StyleText, name)
