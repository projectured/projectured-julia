# Fragment of `ScreenModule` — a document shown in an editor that runs.
#
# `show_document!` asks the content of the first window where a new document
# goes. A package that gives a container, such as the tabs of the pane package,
# adds a method for the type of its container. With no such method, the
# document opens in a window of its own. A document that wraps the content,
# such as the chrome or the clipboard of a window, is looked through.

"""
    show_document!(document; title, editor = get_evaluation_editor()) -> nothing

Show `document` in the running `editor`: where the content of its first window
holds documents, or in a window of its own. `title` names the tab or the
window, and a document that is shown already gets the focus again. Call it on
the task of the editor.
"""
function show_document!(document; title::AbstractString, editor::Editor = get_evaluation_editor())
    screen = get_wrapped_document(editor.document)
    content = screen isa ScreenDocument && length(screen.windows) > 0 ?
        screen.windows[1].content : screen
    show_document!(editor, get_wrapped_document(content), document; title = title)
end

"""
    show_document!(editor, content, document; title) -> nothing

The method for a content that holds no other document: `document` opens in a
window of its own, beside the first window and as large as it. A document that
a window shows already opens no second window.
"""
function show_document!(editor::Editor, content, document; title::AbstractString)
    screen = get_wrapped_document(editor.document)
    (screen isa ScreenDocument && length(screen.windows) > 0) ||
        error("show_document!: the editor shows no window, so it can not open one for ",
              repr(title))
    windows = screen.windows
    for index in 1:length(windows)
        windows[index].content === document && return nothing
    end
    first_window = windows[1]
    push!(windows, Cell(WindowDocument(; id = Symbol(title), title = String(title),
                                       x = first_window.x + 40, y = first_window.y + 40,
                                       width = first_window.width,
                                       height = first_window.height,
                                       content = document)))
    nothing
end
