# File system

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [fileformat.md](../fileformat/fileformat.md), [pane.md](../pane/pane.md)

The file-system slice of `ProjecturedPlatform` shows folders and files of the disk as a tree, and it holds the workspace: the Explorer view that lists the folders you work in. It shows the names of files, not their contents. This document says how a folder reads the disk, how the tree shows it, how a file opens, and where its documents differ from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="File system widget example" src="../../../asset/image/example/filesystem-widget.png">

## How it works

| Type | What it is |
| --- | --- |
| `FileSystemFile` | a `pathname`, and no content |
| `FileSystemDirectory` | a `pathname` and what the last read of the folder found: `elements`, `state`, `failure`, `has_entries` and `read_count` |
| `Workspace` | `folders`, the roots of the Explorer view |
| `WorkspaceFolder` | a `name`, a `pathname` and its `directory`, the `FileSystemDirectory` of the folder; a node of a tree and a kind of the explorer |
| `WorkspaceExplorer` | a `workspace` and `open`, the folders that this explorer shows open: what the Files tab shows |
| `FileSystemChooser` | a `directory`, `open` and a `name`: the document of an open or save dialog |

A `FileSystemFile` has a field `document`, the document that the editor holds open for the file. The acquire of the file takes the document that `find_open_file_document` finds in the `OpenFileList` of the editor, else it reads the file, so one file path is one document in an editor ([fileformat.md](../fileformat/fileformat.md)). The release of the file clears the field, unless the document has an unsaved edit or a conflict.

`make_filesystem_pathname(path)` makes a `FileSystemFile`, or a `FileSystemDirectory` that is unread. A print reads only what a folder holds, and never the disk.

### A folder holds what its last read found

`elements` holds the entries in the order of their names, each a `FileSystemFile` or a `FileSystemDirectory`. `state` is `:unread`, `:reading`, `:read`, or `:failed` with the exception in `failure`. A folder that can not be read, because of a permission or because it is gone, is `:failed`. `has_entries` says whether the folder holds an entry, as the read of its parent found it: `true`, `false`, or `nothing` while that is not known. `has_folder_entries(folder)` answers from the entries of a folder that is read, and from `has_entries` otherwise. `read_count` counts the reads.

### A folder reads when a holder acquires it

An unread folder reads nothing. A holder of the folder acquires it, such as an explorer whose folder is open. The acquire watches the folder and each of its sub-folders, and starts a read with `start_document_read!` ([domain.md](../domain/domain.md)). The read runs on a task and waits a short time. A small folder is complete in the first frame. A large folder, or a slow disk, shows a row "reading" until the read ends. The read lists the names with their kinds in one call, and checks each sub-folder for an entry with one `readdir`, so the sub-folder shows a chevron only when it holds an entry. A known cost: that check reads the whole listing of the sub-folder.

The watch is a watch of a folder in the file change slice ([filechange.md](../filechange/filechange.md)). The sub-folders are watched for their emptiness, with the folder as the receiver, up to the limit of watches of the store. A change of the folder reads it again. A change of a sub-folder checks whether it holds an entry. An editor with no file change feed watches nothing, and the folder reads at its acquire only.

The answer of a read is an `ApplyFolderListingOperation`. It compares the new listing with `elements` by name. A kept entry keeps its document, so an open folder stays open. Each run of gone and new entries is one splice of `elements`, so a new file is one insert and the paths after it move. The answer of an older read is dropped: `read_count` names the read. A change of a sub-folder gives an `ApplyFolderEmptinessOperation`. Both operations go in a `ReplaceViewStateOperation`, so undo records no read.

The release stops the watches and keeps the entries. The folder shows its last listing when a holder acquires it again, and reads it again.

`read_filesystem_folder!(folder; depth)` reads a folder at once on the calling task, and its sub-folders down to `depth` levels. A script, an example and a test use it when no editor runs. It never runs in a print.

### The workspace and the explorer

A `WorkspaceFolder` holds its `directory`, made unread with the folder, so a document holds what a read found. `Workspace` holds the folders that a person opened.

`WorkspaceFolder` is a node of a tree: its children are the entries of its folder document. It is a kind of the explorer: its insertion alias is "folder", and `make_insertion_document` gives `WorkspaceFolder("", "")`, a folder with no place. The row of that folder says "New folder", has no chevron and holds nothing. Its page has a field for the place, which edits `pathname`. Open, or Return in the field, writes the place into the folder and into its folder document (`_make_folder_place_operation` in `Workspace.jl`) and holds that document, so the read starts.

The page of a folder is `FileSystemDirectoryToWidget`. It shows the path, the state of the read of the folder, and a table of its entries. Each name is a link that opens the page of the entry.

`WorkspaceExplorer(workspace)` is what a tab shows. `open` holds the open folders, by their documents. The folder of each workspace folder is open at the start. All explorers of one workspace share one listing of each folder, and each explorer keeps its own open folders, so two explorers can show different open folders over one read. The explorer holds its open folders: its acquire acquires each, so a folder that is open in two explorers has two holders and is read once. `open` is view state, so undo records no open or closed folder. A duplicate of an explorer shares the workspace and copies `open`.

There are two views of the tree:

- **`FileSystemToSyntax()`** prints a directory as a name leaf and an indented body. A custom `marker_eligible` predicate puts the fold marker on the directory name only, not also on the body. The name of a file is text that the projection introduces, so a text edit on it returns `nothing` and a caret on it selects the file. A folder that has no entries yet shows a mark after its name: " …" while it is unread or reads, and " (can not read)" when it failed.
- **`FileSystemToWidget(; open_file)`** prints the tree as one `WidgetTree`, with an icon for each file extension. Its input is a `WorkspaceExplorer`, or any other file-system document, with its root open.

The tree view reads only what the folders hold. A folder row has a chevron when `has_folder_entries` is `true`, or while the folder reads, so an empty folder has no chevron in its first frame and a closed row reads nothing from the disk. An open folder with no entries yet shows one row "reading". A folder that failed shows one row "can not read: " with the first line of the error. The tree scrolls itself in the slot that its tab gives it, because a tab puts nothing around what it holds, and it draws only the rows in its view, so a row outside the view builds no node. The tree takes the width that it is offered, and clips a longer name: there is no horizontal scroll.

For an explorer, the tree has a root for each folder of the workspace, named as the folder. The open nodes come from `open`, by document, so a new entry above an open folder keeps that folder open. A press on a chevron answers one `ReplaceViewStateOperation` that writes `open` and holds a `ChangeHeldDocumentsOperation`. The folder that opens is acquired and reads, and the folder that closes is released. The file action is a parameter of the view, `open_file`: it takes the absolute path of a file and returns the operation that a press on the file makes. The default is `OpenFileOperation`, and each user of the tree can pass its own.

One pair of functions converts a path in the explorer to a path in the tree and back, and the reference maps are those functions. The path `workspace.folders[k].directory.elements[a]…` of the explorer is the node `roots[k].children[a]…`, and `workspace.folders[k]` is the root `roots[k]`.

The Files tab chain is `FileSystemToWidget`, then `RecursiveProjection(WidgetToGraphics(…))`, registered for `WorkspaceExplorer`. The renderer is recursive because the tree prints itself again as the content of its own pane. A bare `Workspace` draws through `WorkspaceToFileSystem` first, which shows its first folder.

### Select a row

A row of an explorer is a document of the workspace: the folders and entries are stored. So a selection of a row is the path `workspace.folders[k].directory.elements[a]…` of the explorer, and a key goes where that path points. A plain click and the arrow keys move the row. The tree itself and a part that the view drew, such as a scroll bar, are named by an introduced reference.

In the chain of a bare `Workspace`, the tree is the output of `WorkspaceToFileSystem`, so a row is a place that the projection introduces. A selection of that row is a `ProjectionReferenceStep` on the folder. An Alt+click selects the `Workspace` as a whole, so the pane that holds it draws its selection ring.

### Open a file

Enter on a row, or a double click, makes an `OpenFileOperation(path)`. The operation is a type of the widget slice (`OpenFileOperation.jl`), and this slice evaluates it (`FileSystemDocument.jl`). The operation names the file and nothing else. When the editor applies it, `make_file_tab` reads the file into the document type that its extension registers, in a scroll pane, and `open_pane!` asks the pane tree where a file goes. An opener can put a part of its own around the content that the file holds (`wrap`), or around the file document (`file_wrap`), as a link puts a navigator around a file. When the editor has settings, the evaluation gives the file a history (`make_history_wrap` of the undo slice), whatever started the open: around the part of `file_wrap`, so it records every edit of that part, and else around the content, inside the file. A file that is its own content has no content inside it, so the history goes around the file. So a file that the Files pane, the menu Open or a link opens has an undo.

### Choose a file

`FileSystemChooser` is the document of the open and save dialogs of the shell slice. `get_chosen_path` joins the directory and the name. The shell turns the chosen path into an open or a save.

`FileSystemChooserToWidget` draws the chooser as a one-column grid: the tree over the field of the name. The tree is the tree of an explorer, built from `open` of the chooser, with the rows, the chevrons and the "reading" row of the Files tab. A chevron opens or closes a folder and changes what the chooser holds, and the chooser holds its open folders as an explorer does. The file action of the tree is `WriteChosenNameOperation`: Enter or a double press on a file row writes the name of the file into `name`. The field is a text widget whose content is `name`, so a key in the field edits `name`. The paths map `children[1].roots[1].children[a]…` to `directory.elements[a]…` and `children[2].content<rest>` to `name<rest>`. The renderer takes the view through `make_graphics_projection` for `FileSystemChooser`, chained with `GridLayoutToGraphicsCanvas`.

### Duplicate the Explorer

`has_document_duplicate` is `true` for every `WorkspaceDocument`, so the tab of the Explorer shows a `+` above its `x`. The duplicate of a `WorkspaceExplorer` shares the workspace and copies `open`, so it opens the same folders and shares what they read; see [document.md](../../kernel/document.md#the-duplicate). The selected row is not in the explorer, so a duplicate opens with no row selected. The duplicate of a bare `Workspace` is a copy of its folders.

### The theme

`FileSystemTheme` holds the text of a file and of a directory in the syntax form. Each value has the default that the slice draws with no
appearance. `FileSystemFileToSyntaxLeaf` and `FileSystemDirectoryToSyntaxNode` hold their styles and no theme.
`FileSystemToSyntax(; theme)` fills them with `get_file_system_style`, from a `FileSystemTheme` scaled or not, or the
default values for `nothing`. The registration gives the scaled theme of the `Appearance`. The tree of the explorer is made of widgets, so it follows the widget theme.

## How it fits

The file-system slice depends on the file-format and pane slices for the open, on the widget slice for the tree, on the layout slice for the grid of the chooser, on the file change slice for the watch of a folder and the store of an editor (`find_file_change_store`), on the domain slice for the acquire and the read, and on the focus slice for the Alt+press that selects the workspace. The shell slice uses it for the dialogs and for the Files button of the toolbar.

Its `__init__` registers:

- `register_natural_syntax!(:filesystem, …)` with the syntax view;
- `register_natural_graphics!(:workspace, …)` with the Explorer chain for a `WorkspaceExplorer`, which comes before the chain for any other `WorkspaceDocument`.

A `.pred` file builds `Workspace`, `WorkspaceFolder` and `WorkspaceExplorer` by their names, so a saved window keeps its Explorer. A file keeps the name and the place of each folder, and no entry that a read found. No parser exists. A `WorkspaceExplorer` answers to the insertion names `files` and `file explorer`, and it starts with the current folder. The Files tool of the window makes a `WorkspaceExplorer`.

## Design decisions

- **An open names the file, not the place.** The file-system slice has no reference to tabs or panes. The pane tree chooses the place of a file.
- **A chooser only chooses.** The dialog document holds a path. The shell acts on it.
- **A row is a stored document.** A folder holds its entries, so a selection of a row is a path through the explorer, and the window has one selection.
- **A print reads only cells.** A folder reads in an operation, on a task, and never in a computation. The state of a folder is in its document: the entries, the read state and whether it holds an entry.
- **An explorer owns what a person controls, and shares what it reads.** The open folders are in the explorer, and the listing is in the folder document that the workspace holds. So two explorers of one workspace show different open folders over one read.
- **A holder sets what is read.** A folder reads and watches itself while a holder holds it, and a closed folder reads nothing. The release keeps the entries.
- **The file action is a parameter of the view.** A row of a file names the file, and the document around the tree sets the meaning: the Files tab opens the file, and the chooser writes the name.

## Usage

```julia
tree = read_filesystem_folder!(make_filesystem_pathname("example/platform/filesystem/fixture/project"))
workspace = Workspace([WorkspaceFolder("project", abspath("example/platform/filesystem/fixture/project"))])
explorer = WorkspaceExplorer(workspace)   # a tab shows it, and its folders read when it is held
run_example("files")                      # the Explorer view of the fixture project
```

- Examples: `filesystem_example` (syntax), `filesystem_widget_example` (the tree) and `files_example` (the workspace). They read the fixture under `example/platform/filesystem/fixture/project/` with `read_filesystem_folder!`, so they do not change when the repository changes.
- Test: `test_filesystem()` runs the layering guard, the two projection tests, `test_filesystem_document()`, which checks the acquire, the read and the watch of a folder, and `test_workspace_to_filesystem()`, which maps a row through the workspace and back. `FileDialogTest.jl` of the shell slice draws the chooser. The SDL suite has `test_tree_render()`, which renders a folder of 1,000 entries in a small pane and checks that only the drawn rows build their nodes.

## Limits

- A bare `Workspace` with more than one folder shows only the first folder. The comment in `source/platform/filesystem/WorkspaceToFileSystem.jl` says so. An explorer shows every folder.
- A change on the disk shows only in a folder that a holder holds and that the store watches. Past the limit of watches, a sub-folder updates its emptiness at the next read of its parent.
- The empty check of a sub-folder reads its whole listing.
- A folder of a path where nothing is yet is `:failed` at its first read.
- A key that moves the selection to a row below the edge of the pane does not scroll the row into view.
- A file has no content view here. To edit a file, open it; its extension selects the domain.
- A long name is clipped at the edge of the pane.
