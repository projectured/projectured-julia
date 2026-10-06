# Fragment of `ShellModule` — Open and Save As.
#
# A dialog is a `WidgetDialog` holding a `FileSystemChooser`. The chooser chooses
# a path and does nothing with one; what happens to the path is the command that
# opened the dialog, and the two differ only there. So both are one function with
# a different verb at the end.

"""
    make_file_dialog(directory, title, confirm) -> WidgetDialog

A modal dialog over a file chooser: `title` names what it is for, and `confirm`
is the label of the button that takes the chosen path. Each button is as large
as its label.

`directory` is where it opens. The chooser it holds is what answers the path, so
a caller reads `get_chosen_path` of it when the person confirms.
"""
function make_file_dialog(directory::AbstractString, title::AbstractString,
                          confirm::AbstractString)
    chooser = make_filesystem_chooser(directory)
    dialog = WidgetDialog(title, chooser, Any[WidgetButton("Cancel"), WidgetButton(confirm)];
                          popup_id = :file_dialog)
    (dialog, chooser)
end

"""
    open_file_dialog!(; directory = pwd(), editor = get_evaluation_editor()) -> Nothing

Open a file that is not in the window's workspace.

It opens the dialog; the path is taken when the person confirms, and
`OpenFileOperation` is what opens it, so a file opened here lands in a tab
exactly as a file opened from the explorer does.
"""
function open_file_dialog!(; directory::AbstractString = pwd(), editor = get_evaluation_editor())
    dialog, chooser = make_file_dialog(directory, "Open", "Open")
    _show_file_dialog!(editor, dialog, chooser) do path
        isfile(path) ? OpenFileOperation(path) : nothing
    end
end

"""
    save_file_dialog!(file; directory = pwd(), editor = get_evaluation_editor()) -> Nothing

Give `file` a name and write it there.

`file` is the `FileDocument` a tab holds. Saving it under a new name is two
things and this does both in order: the file takes the name, and then it is
written, by the one operation that writes a file.
"""
function save_file_dialog!(file; directory::AbstractString = pwd(),
                           editor = get_evaluation_editor())
    dialog, chooser = make_file_dialog(directory, "Save as", "Save")
    _show_file_dialog!(editor, dialog, chooser) do path
        isempty(basename(path)) && return nothing
        file.filename = path
        SaveFileOperation(file)
    end
end

# The dialog is a window of its own, as every popup here is (`PAR-MANY-WINDOWS`).
# What the confirm button answers is what `take` makes of the chosen path.
function _show_file_dialog!(take::Function, editor, dialog, chooser)
    confirm = last(collect(dialog.buttons))
    confirm.action = Action(confirm.action.label;
                            callback = _ -> begin
                                operation = take(get_chosen_path(chooser))
                                operation === nothing || evaluate_operation(editor, operation)
                                nothing
                            end)
    evaluate_operation(editor, OpenWindowOperation(id = :file_dialog, title = string(dialog.title),
                                                   x = -1, y = -1, width = 640, height = 420,
                                                   style = :floating, content = dialog))
    nothing
end
