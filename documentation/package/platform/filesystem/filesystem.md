# File system

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [fileformat.md](../fileformat/fileformat.md), [pane.md](../pane/pane.md)

The file-system slice of `ProjecturedPlatform` shows folders and files of the disk as a tree, and it holds the workspace: the Explorer view that lists the folders you work in. It shows the names of files, not their contents. This document says how the tree is read, how a file opens, and where its documents differ from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="File system widget example" src="../../../asset/image/example/filesystem-widget.png">

## How it works

| Type | What it is |
| --- | --- |
| `FileSystemFile` | a `pathname`, and no content |
| `FileSystemDirectory` | a `pathname` and its `elements` |
| `Workspace` | `folders`, the roots of the Explorer view |
| `WorkspaceFolder` | a `name` and a `pathname` |
| `FileSystemChooser` | a `directory` and a `name`: the document of an open or save dialog |

`make_filesystem_pathname(path)` makes a `FileSystemFile` or a `FileSystemDirectory`. A folder is read at the first read of its `elements`, and each entry at its own first read: a read of the length is one `readdir`, and a read of an entry is one `isdir`. A folder that can not be read, because of a permission or because it is gone, has no entries. A folder is read once, and nothing watches the disk. `WorkspaceToFileSystem` makes the folder again in a computed cell when the `pathname` of a workspace folder changes.

There are two views of the tree:

- **`FileSystemToSyntax()`** prints a directory as a name leaf and an indented body. A custom `marker_eligible` predicate puts the fold marker on the directory name only, not also on the body. The name of a file is text that the projection introduces, so a text edit on it returns `nothing` and a caret on it selects the file.
- **`FileSystemToWidget()`** prints the tree as one `WidgetTree`, with an icon for each file extension. The root row is open, and each folder under it is closed until a person opens it. A folder row reads the listing of its folder when the row is drawn, to know if it has a chevron, and an empty folder has no chevron. The tree scrolls itself in the slot that its tab gives it, because a tab puts nothing around what it holds, and it draws only the rows in its view, so a row outside the view reads nothing from the disk. The tree takes the width that it is offered, and clips a longer name: there is no horizontal scroll. One pair of functions converts a path in the file system to a path in the tree and back, and the reference maps are those functions.

The Explorer chain is `WorkspaceToFileSystem`, then `FileSystemToWidget`, then `RecursiveProjection(WidgetToGraphics(…))`. The renderer is recursive because the tree prints itself again as the content of its own pane.

### Select a row

A `WorkspaceFolder` holds a name and a path, and the tree below it is computed from the path. So a row of the tree is a place that the projection introduces, and a selection of a row is a `ProjectionReferenceStep` on the folder. The root path of a selected file reads `….folders[1].proj(WorkspaceFolderToFileSystemDirectory(), .elements[2].elements[1])`. The root row is the folder itself, so the folder as a whole, `….folders[1]`, selects the root row.

The selection of the computed directory is a computed cell: the image of the folder's selection. No reader writes it, so the window has one selection, and a key goes where the root path points. A plain click and the arrow keys move the row. An Alt+click selects the `Workspace` as a whole, so the pane that holds it draws its selection ring; the four-argument reader of `WorkspaceToFileSystemDirectory` answers that press itself, because the folder draws as the whole view and no widget draws a ring for it alone.

### Open a file

Enter on a row, or a double click, makes an `OpenFileOperation(path)`. The operation names the file and nothing else. When the editor applies it, `make_file_tab` reads the file into the document type that its extension registers, in a scroll pane, and `open_pane!` asks the pane tree where a file goes. An opener can put a part of its own around the content that the file holds (`wrap`), or around the file document (`file_wrap`), as a link puts a navigator around a file. When the editor has settings, the evaluation gives the file a history (`make_history_wrap` of the undo slice), whatever started the open: around the part of `file_wrap`, so it records every edit of that part, and else around the content, inside the file. A file that is its own content has no content inside it, so the history goes around the file. So a file that the Files pane, the menu Open or a link opens has an undo.

### Choose a file

`FileSystemChooser` is the document of the open and save dialogs of the shell slice. In the chooser, the open gesture of a row makes a `WriteChosenNameOperation` instead of an `OpenFileOperation`: Enter or a double click writes the name of the file into the `name` field. `get_chosen_path` joins the directory and the name. The shell turns the chosen path into an open or a save.

### Duplicate the Explorer

`has_document_duplicate` is `true` for every `WorkspaceDocument`, so the tab of the Explorer shows a `+` above its `x`. The duplicate is a copy of the folders; see [document.md](../../kernel/document.md#the-duplicate). The selected row and the open folders are not in the workspace. The reader writes the row selection on the computed `FileSystemDirectory`, and the open folders are a cell of the `WidgetTree` (`expanded`). So a duplicate opens with no row selected and only the first level open.

### The theme

`FileSystemTheme` holds the text of a file and of a directory in the syntax form. Each value has the default that the slice draws with no
appearance. `FileSystemFileToSyntaxLeaf` and `FileSystemDirectoryToSyntaxNode` hold their styles and no theme.
`FileSystemToSyntax(; theme)` fills them with `get_file_system_style`, from a `FileSystemTheme` scaled or not, or the
default values for `nothing`. The registration gives the scaled theme of the `Appearance`. The tree of the explorer is made of widgets, so it follows the widget theme.

## How it fits

The file-system slice depends on the file-format and pane slices for the open, on the widget slice for the tree, and on the focus slice for the Alt+press that selects the workspace. The shell slice uses it for the dialogs and for the Explorer button of the toolbar.

Its `__init__` registers:

- `register_natural_syntax!(:filesystem, …)` with the syntax view;
- `register_natural_graphics!(:workspace, …)` with the Explorer chain for a `WorkspaceDocument`.

A `.pred` file builds `Workspace` and `WorkspaceFolder` by their names, so a saved window keeps its Explorer. No parser exists. A `Workspace` also answers to the insertion names `explorer` and `file explorer`, and it starts with the current folder.

## Design decisions

- **An open names the file, not the place.** The file-system slice has no reference to tabs or panes. The pane tree chooses the place of a file.
- **A chooser only chooses.** The dialog document holds a path. The shell acts on it.
- **A row is a place the projection introduces.** The tree is computed from a path, so a row has no document of its own in the workspace. The row goes into the root path as a `ProjectionReferenceStep` on the folder, as a catalog row does on a `DatabaseInstance`. A second selection on the computed directory would split the window's selection in two.
- **A folder is read once, and nothing watches it.** The first read happens when the Explorer draws the row of the folder or opens it. A live view of the disk needs a synchronizer outside the cells. [plan/tentative/filesystem-file-content-projection.md](../../../../plan/tentative/filesystem-file-content-projection.md) discusses one.
- **The screen decides what is read.** The renderer draws only the rows in the viewport, and a row is computed only when it is drawn, so the Explorer reads the folders on the screen and no others.

## Usage

```julia
tree = make_filesystem_pathname("example/platform/filesystem/fixture/project")
explorer = Workspace([WorkspaceFolder("project", abspath("example/platform/filesystem/fixture/project"))])
run_example("files")                     # the Explorer view of the fixture project
```

- Examples: `filesystem_example` (syntax), `filesystem_widget_example` (the tree) and `files_example` (the workspace). They read the fixture under `example/platform/filesystem/fixture/project/`, so they do not change when the repository changes.
- Test: `test_filesystem()` runs the layering guard, the two projection tests, `test_filesystem_document()`, which checks the reads of a folder, and `test_workspace_to_filesystem()`, which maps a row through the workspace and back. The SDL suite has `test_tree_render()`, which renders a folder of 1,000 entries in a small pane and checks that only the drawn rows read their entries.

## Limits

- A workspace with more than one folder shows only the first folder. The comment in `source/platform/filesystem/WorkspaceToFileSystem.jl` says so.
- A change on the disk does not show until something assigns the folder path again.
- A key that moves the selection to a row below the edge of the pane does not scroll the row into view.
- A selected row other than the root row names no document, so a copy of it copies nothing.
- A file has no content view here. To edit a file, open it; its extension selects the domain.
- A folder that was read is not read again when it closes and opens.
- A long name is clipped at the edge of the pane.
- The tree keeps the open folders as index paths. When the folder path changes, the tree starts again with only the root open.
