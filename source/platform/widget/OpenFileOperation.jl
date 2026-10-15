# Fragment of `WidgetModule` — the request to open a file: a path, and the parts
# that the opener puts around what the file holds.

"""
    OpenFileOperation(path; wrap = identity, file_wrap = identity)

The request to open the file at `path`. A part that a person presses answers
it, such as a link to a file, and it goes up to the editor, which evaluates it.
It names the file and nothing about where the file shows: a tab, a pane or a
page.

`wrap` is applied to the content that the file document holds, and `file_wrap`
to the file document: an opener puts a part of its own around the file there,
such as a navigator. When the editor has settings, the evaluation of the open
gives the file a history, whatever started the open: around the part that
`file_wrap` makes, so it records every edit of that part, and else around the
content, inside the file, as a file tab has it.
"""
struct OpenFileOperation <: Operation
    path::String
    wrap::Any
    file_wrap::Any
end

OpenFileOperation(path::AbstractString; wrap = identity, file_wrap = identity) =
    OpenFileOperation(String(path), wrap, file_wrap)

# It carries its own subject and names no reference, so every reader between
# the gesture and the editor passes it up unchanged.
is_self_contained_operation(::OpenFileOperation) = true
