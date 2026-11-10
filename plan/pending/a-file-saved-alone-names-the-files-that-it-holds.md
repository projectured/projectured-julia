# A file saved alone names the files that it holds

> **Kind:** plan · **Status:** a plan, written 2026-11-05 at `main` `0d8dd49a0`, and revised the
> same day at `main` `6b93bfcf3` to follow the decisions of the owner (D0, D1, D2, D6, D7, D8) and
> the decisions of G3 and G4. The owner approved the implementation on 2026-11-05. Steps 1 to 4 are
> built in the worktree `projectured-julia-held-files`, branch `held-files`, with omnet-julia in
> `omnet-julia-held-files`, branch `held-files`. ·
> **Needed by:** G3 [the-assistant-shows-a-picture-file.md](../done/the-assistant-shows-a-picture-file.md),
> G4 [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md),
> G5 [the-assistant-fills-a-live-table.md](the-assistant-fills-a-live-table.md) · **Needs:** G4
> step 2 for steps 5 and 6 · **Order:** the owner moved step 5 forward on 2026-11-06 ("Yes"): it
> runs after G4 steps 1 to 3 land and before G4 step 4, which needs `open_file_document!`. Step 6
> keeps its place after the layout plan · **G4 D10:** on 2026-11-06 the owner decided in G4 that
> the file document watches its file and keeps the hash and the band, and that `FilePage` goes away
> (G4 D10 to D13, G4 step 1b). Below, "the page of a file" reads "the file document", and a view of
> it is a `FileView`. G4 step 1b removes `find_held_file(page::FilePage)` of step 3 here, and the
> view of a file answers `find_held_file` with its file. Step 5 adds `open_file_document!(path;
> editor)` in place of `open_file_page!`, and it makes a file document that reads nothing. The text
> of §4.6, §4.7 and steps 5 and 6 is revised to these names (2026-11-07, at `main` `140ae8853`,
> after G4 steps 1 to 3 landed); the owner said "Yes" to the start of step 5 the same day ·
> **Stands on:**
> [serialization.md](../../documentation/package/platform/serialization/serialization.md),
> [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md),
> [filechange.md](../../documentation/package/platform/filechange/filechange.md),
> [filesystem.md](../../documentation/package/platform/filesystem/filesystem.md)

This plan makes a save of one file write `file("…")` for each opened file that the file holds, and
makes an open of that file in an editor give each `file("…")` the editor's one page of that file.
The open reads no held file: a held page reads its file when a view draws it. The plan covers the
three ways that the editor saves a file that holds another file: the save of a file alone, the page
that a card holds, and the file of the explorer content. Steps 1 to 4 need no other plan, and G3, G4
and G5 need them to save an opened file in a document. Steps 5 and 6 need G4 step 2, which makes the
text of a page a background cell (§4.10).

## 1. The goal

When this plan is done:

1. A dashboard in `/work/evolution.pred` with
   `DashboardCard("qos/jitter_qos", <the opened file /work/commits/9b919d0c46/qos/jitter_qos.png>)`
   saves as `DashboardCard("qos/jitter_qos", file("commits/9b919d0c46/qos/jitter_qos.png"))`. The
   save writes no byte of the held file, and it does not throw.
2. The same holds for every file kind, for a held page of a file, such as the page in a card (G4),
   and for a held file in a named tuple, such as a record of a table (G5).
3. An open of `/work/evolution.pred` in an editor gives the card the editor's one page of the
   picture: the page that a tab shows, else a new page. A tab and a card then share one page, and
   each shows its own view of it (G4 D2).
4. The open reads no held file. A held page reads its file after the frame in which a view draws it
   (G4 D4). Until then the page shows that it reads and refuses a save, so an empty page never
   writes over its file.
5. A reload of the holder, after F5 or after a change on disk, gives each `file("…")` its page in
   the same way. A card that another program adds to the holder shows its file.
6. A load with no editor reads no other file, and a save of what it loaded writes the same text.
7. A save of the holder writes no held file. The edits of a held file that are not saved stay until
   a person saves that file. The save check of D15 (the band, "changed on disk") does not change.

**Terms.** A **held file** is a file document, or a document that stands for one, such as the page
of a file, that another document holds as a value. The **holder** is the file whose save meets the
held file. The **opened document** of a file is what `find_open_file_document(path; editor)`
answers: the `FilePage` that a tab or a page shows, or the file document when no page holds it
(`OpenFileList.jl:6-31`). G4 D8 decides that no bare file is watched, so after G4 the opened
document is a page (§7). The **editor's one page** of a file is its opened document, else the new
page that the open makes for it. A page that is **not read yet** is a page whose text cell (G4 D4)
has no answer yet.

## 2. What exists

The assistant read each row in the code of `main` `0d8dd49a0` on 2026-11-05, and checked each row
again at `main` `6b93bfcf3` on the same day. Of the files that the plan cites, only
`WidgetDocument.jl`, `Application.jl` and `ExplorerTest.jl` changed between the two, and their line
numbers here are the new ones. The rows of omnet-julia hold at its `main` `a1dfa5af3`. A row marked
**measured** was run at `0d8dd49a0` with a scratch script outside the repository, through
`workspace/bin/bounded-run` in `environment/all`. The code that it ran did not change.
`SEALING.md` lists files of `source/kernel/` only, and no step of this plan changes a file there.

| Fact | Where |
| --- | --- |
| A file saved alone throws `FileCutException` at a held file document: "... holds the file document ... it needs a reference, and a file saved alone cannot write one — save it in a FileProject". `save_file!` catches it, logs it and answers `false`. **Measured**: `save_file!(JsonFile("root.json", JsonObject("c" => JsonFile("child.json", …))), d)` logs that error, answers `false` and writes no file. | `FileCut.jl:267-272`, `:291-299`, `:430-442` |
| A project save writes `file("child.json")` for a held file document, also when the held file is not in the set, and writes no held file. **Measured**: the save answers `true`, and the folder holds `root.json` only. The docstring of `save_user_interface` and `pane.md:242` say that the save aborts for a file outside the set. That is not true. | `FileCut.jl:269-272`, `UserInterfaceFile.jl:25-32` |
| A marker names a file by the name that the file gives, `repr(get_filename(file))`. An editor gives each file its absolute path (`make_file_tab`), so a file saved by Ctrl+S names itself by its absolute path. **Measured**: a `JsonFile` with an absolute name and one object at two places saves `"<<node(file(\"/tmp/…/a.json\"), \"entries[1].value\")>>"`, and `load_file(dir, "a.json")` leaves that marker a string. The two places are two objects after the load. | `FileCut.jl:366-370`, `DocumentFile.jl:167-174`, `:246-247`, `FileSplice.jl:177` |
| `file("…")` as the whole value of a slot loads as the **content** of the file, not as the file document. As the argument of another verb it is the file document. **Measured**: a project of `root.json`, whose object holds `JsonFile("child.json", …)`, and `child.json` loads with a `JsonString` in the slot, not the `JsonFile`. `test_user_interface_file` asserts the same for a tab: the tab held a `JsonFile`, and after the load it holds the `JsonObject`. | `FileSplice.jl:244-247`, `test/projectured/editor/UserInterfaceFileTest.jl:59-62` |
| The root node of another file, and the root of the file itself, is also `file("…")`. So one marker has two meanings: the file, and its root node. A path in `node(…)` must have a step: "an empty path names the file; write file(…) instead". | `FileCut.jl:366-370`, `FileSplice.jl:341-350` |
| Two loaders of omnet-julia take `file("…")` as the content and search the set for the file again: `load_catalog_shell` and `finish_omnet_project!`. | omnet-julia `source/presentation/project/CatalogShell.jl:420-428`, `OmnetProject.jl:118-145` |
| The cut walks a field that holds a document and a vector of documents. It does not go into a tuple or a named tuple. **Measured**: a `.pred` file whose holder has `value = (pic = JsonFile("c.json", …),)` saves alone with no exception and writes the held file whole: `JsonFile(filename = "c.json", content = JsonString(value = "leaf"))`. | `FileCut.jl:243-259`, `:329-349`, `PredFile.jl:431-442`, `:467-485` |
| The follow and the splice of a load do not go into a tuple or a named tuple either. **Measured**: `load_project(d, ["h2.pred"]; follow = true)` of `value = (pic = file("c.json"),)` opens one file, and `value.pic` stays a `PredReference`. The same marker in a vector loads as the content of `c.json`. | `FileSplice.jl:137-160`, `:195-226` |
| A `FilePage` is no file document and has no `pred_arguments` of its own, so a `.pred` file writes every field of it. The cut takes it for a node of the `.pred` file and walks its `content`, the scroll pane. | `FileProject.jl:80-81`, `FilePage.jl:30-34`, `PredFile.jl:81` |
| The cut of a `.pred` file walks only a field that `pred_arguments` writes as a **keyword**. A `WidgetScrollPane` and a `WidgetTransformPane` write their `content` as a positional argument, so the cut does not walk it, and the writer writes the document there whole. **Measured**: `cut_file_text(PredFile(…, DashboardCard("notes", make_file_tab_content(path))), d)` throws nothing and writes `FilePage(content = WidgetScrollPane(TextFile(filename = "/tmp/…/notes.txt", content = PrimitiveString(value = "hello")), …), band = nothing, file_hash = 0xb84e0ed46dd97f32)`. So a save alone of a card that holds a page writes a copy of the text of the file too, as the explorer content does. | `PredFile.jl:148-153`, `WidgetDocument.jl:4009`, `:4013` |
| A section of the explorer content whose `DashboardCard` holds a `FilePage` saves with no exception, and writes the page whole: the file with a copy of its text, the scroll pane and the hash. The next start reads that copy back. **Measured** by the agent of the G4 revision on 2026-11-05 with `print_pred_text`, and reported to this plan by the coordinator. The reason: `save_explorer_content!` writes with `print_pred_text`, which prints a tree and never cuts, and `load_explorer_content` reads with `parse_pred_text`, which splices nothing. | `ExplorerContentFile.jl:60-70`, `:90-99` |
| G4 D2, decided by the owner: a tab and a card share one page, and each place shows its own view of it, `make_document_view(page)`. G4 D3: a card holds the page as its content and keeps its view in a slot that a walk does not enter, and a tab holds the view (G4 step 1a). G4 D4, decided by the owner: the text of a page is a background cell whose input is the path and a count of changes, the watch only adds one to the count, and a page that is not read yet shows that it reads and refuses a save (G4 step 2). G4 D8, decided by the owner: no bare file is watched. The default of `make_document_view` answers the document itself, and no view of a page exists yet. | the G4 plan, D2, D3, D4 and D8; `DocumentView.jl:32` |
| G3 D1, D2, D9 and D12, decided by the owner: a picture is `ImageFile <: FileDocument`, a file that a person does not edit, its content is `Image <: ImageDocument`, its pixels are a background cell, and the watch only reports a change. On main, `ImageFile <: ImageDocument` holds a path and its pixels, and no file type reads a `.png`. | the G3 plan, D1, D2, D9 and D12; `Image.jl:20-34` |
| G5 D2, decided by the owner: a record of a table is a named tuple. A picture of a record is a held file in a named tuple. | the G5 plan, D2 and "Where G5 meets G3" |
| `get_edited_field` names a field also for a `PaneTab`, a `Navigator`, an `ArrangementDocument` and a `WidgetScrollPane`. | `PaneDocument.jl:144`, `NavigatorDocument.jl:120`, `ArrangementDocument.jl:34`, `WidgetDocument.jl:4034` |
| The editor reads a file of a natural format with `import_document`, which splices nothing, and a `.pred` or `.txt` file with `load_file`, which splices the markers into the file itself. Both keep a marker into another file as a leaf. | `NaturalFormat.jl:27-33`, `DocumentFile.jl:98-111`, `FileSplice.jl:118-127` |
| An open of a file takes the opened document of the editor first, else it reads the file into a page with the history of the settings of the editor. It runs in the evaluation of `OpenFileOperation`, in `open_file!` on the editor task, and in the acquire of a `FileSystemFile`. | `FileSystemDocument.jl:55-63`, `:82-86`, `:201-227`, `:252-260` |
| `FileSystemFile` holds a path and, after its acquire, the opened document of the editor for it. It writes only its path to a `.pred` file. | `FileSystemDocument.jl:41-63` |
| The open files of an editor are a session document of that editor. A page or a file enters the list at its acquire and leaves it at the release of its last holder. The acquire of a file document that no page holds watches its file too. | `OpenFileList.jl:78-79`, `:163-181`, `FileChangeStore.jl:280-310` |
| omnet-julia opens an INI file from a link as a file document with no page (`make_file_tab`). | omnet-julia `source/ide/LegacyIniFileEntryToWidget.jl:150-156` |
| The reload of a file swaps a new content into the history of the file. The content comes from a read on the editor task, or from the watcher, which reads and parses on its own task. F5, the load of a page and a change that the drain gives to a page all evaluate `ReloadFileOperation`. | `DocumentFile.jl:449-470`, `FileChangeStore.jl:476-487`, `FilePage.jl:204-213`, `:324-345` |
| The make of a page hashes the text of its file, and the start of a watch hashes the file again, on the task that makes or acquires the page. A page with no hash writes with no check. | `FilePage.jl:111-117`, `:191-192`, `FileChangeStore.jl:44-49`, `:138-152` |
| A background cell computes its value off the loop. A read never waits: it records a demand, and after the frame a task runs the work. The `apply` of the cell answers an operation, which the editor evaluates on its task, and with no editor the operation gets `nothing` as its editor. A folder adds one to its read count at each change. | `BackgroundCells.jl:181-232`, `FileSystemDocument.jl:556-560` |
| A cell of a roster draws a picture only for an `ImageFile`. Any other value shows as text. | `RosterToGraphics.jl:138-145` |
| The save of a page checks the hash of its own file on disk, writes only that file, and shows the band when another program changed it. | `FilePage.jl:186-202` |
| Every editor save gives the folder of the saved file as the base folder. | `DocumentFile.jl:119`, `:247`, `:414` |
| A file document with no name has no save, and "Save as" (`save_file_dialog!`) gives it a name. | `DocumentFile.jl:485-486`, `fileformat.md`, section Limits |

## 3. What the code lacks

1. **A save of one file can not name another file.** It throws at a held file document.
2. **A held page writes a copy of its file.** The explorer content writes it whole. A save alone
   writes it whole too, because the cut does not walk the content of a scroll pane, which
   `pred_arguments` gives as a positional argument. A held file in a scroll pane or a transform
   pane is written the same way.
3. **One marker has two meanings.** `file("…")` names a file and the root node of a file, and the
   load always takes the root node. A held file comes back as its content.
4. **A held file in a named tuple is not cut and not spliced.**
5. **A marker of an editor save names its own file by its absolute path**, which no load of one
   file finds.
6. **No load gives the opened files of the editor.** A held file of a loaded file stays a leaf, and
   a reload of the holder leaves it a leaf too.
7. **The open reads a file at once, on the editor task.** The make of a page and the start of its
   watch hash the text of the file (§2). No page can wait for its first read. G4 step 2 makes the
   text of a page a background cell.

## 4. Design

Proposed by the assistant, inside the decisions of the owner (D0, D1, D2, D6, D7, D8). §5 gives the
reason and the rejected alternatives of each part.

### 4.1 `file("…")` names the file

The splice puts the file document into the slot, wherever `file("…")` stands. A reference to the
root node of a file is `node(file("…"), "")`: the node at the empty path. So a save writes
`node(file(…), path)` for every node that it names by a marker, the root of a file too, and
`file(…)` only for a held file. The special rule of `FileSplice.jl:244-247` goes, and `node(…)`
takes the empty path (D1).

### 4.2 The save alone writes a held file as `file("…")`

The cut of a file saved alone writes the reference leaf of its format for each held file:
`file("commits/9b919d0c46/qos/jitter_qos.png")` in a `.pred` file, a marker string in a JSON file.
It does not walk into the held file, and it writes nothing of it. The path is the path of the held
file relative to the base folder of the save, with `..` for a file outside it (D2). The same rule
names the file itself in a marker into itself, so a file that an editor saves splices its own
markers again. A held file with no name refuses the save, and the log says why (D3).

The cut of a `.pred` file walks each field that the file writes, as a keyword or as a positional
argument of `pred_arguments`. `is_written_in_file(::PredFile, node, name)` then also answers `true`
for a field whose value is one of the positional arguments, by identity, and holds a document. So a
held file in a scroll pane or a transform pane is a reference too (D12).

The project save keeps its names: a marker names a file by the name that the file gives.

### 4.3 A page saves as the file that it shows

`find_held_file(node)` is a new function of the contract of a file type. It answers the file document
that `node` stands for when a document holds it, or `nothing`. The default answers `node` for a file
document. The file-format slice adds `find_held_file(page::FilePage) = find_page_file(page)`. Every
walk of the cut stops at a node that it answers for, and the cut writes `file("…")` there (D4). The
slot of a card holds the page (open question 5), so this method covers it. The view of the card sits
in a slot that no walk enters (G4 D3), so the save writes no view. A page that is not read yet
answers its file too, with its path, so a holder saves `file("…")` for a page that no view drew. A
tab of G4 step 1a holds a view of a page, and `save_user_interface` saves the tabs, so that view
needs a method of `find_held_file` too (open question 8).

### 4.4 A held file in a tuple or a named tuple

The cut goes into a tuple and a named tuple, at any depth, and writes the reference leaf for a held
file there. Any other value in it stays as the `.pred` writer writes it now. The follow, the splice
of a load and the walk of §4.6 go into a tuple and a named tuple too, and build the tuple again with
the new value (D5).

### 4.5 The load without an editor

`load_file` and `import_document` read no other file. A held file stays its reference leaf: a
`PredReference` in a `.pred` file, a marker string in a JSON file. A save alone writes that leaf
back as it is, so the text does not change. A script that wants the held files calls
`load_project(base, [name]; follow = true)`. After step 1, that load gives the file documents in
their slots, with names relative to `base`.

### 4.6 The open in an editor gives each held file its file document (D6)

The serialization slice gets one walk, and the file-format slice gets one generic function:

- `splice_held_files!(content, base_dir, find_file)` replaces each reference leaf of `content`
  whose marker is a whole `file("p")` with what `find_file(path)` answers for the absolute path of
  `p` against `base_dir`. It asks `find_file` once for each path, so two slots of one file get one
  answer. An answer `nothing` keeps the leaf. A `node(…)`, a `section(…)` and any other verb stay
  leaves. The walk goes into a tuple and a named tuple (§4.4). It reads no disk, and it changes no
  state outside `content`.
- `open_file_document!(path; editor)` answers the file document that a held file at `path` gets
  in `editor`, or `nothing`. The file-format slice declares it with its docstring, and its default
  answers `nothing`, so a load with no editor keeps each leaf. The file-system slice adds the method
  for an `Editor`, which answers the editor's one file document of the file:
  `find_open_file_document(path; editor)`, else a new file document that reads nothing
  (`make_unread_file`, G4 step 2), with the history around its content that `_make_opened_file`
  puts there. The method adds the new file document to the open files of the editor at once, so two
  holders that load before either is shown get one file document, not two. The text cell of that
  file (G4 D4) has no answer yet, so the method reads no file. The owner decided the name on
  2026-11-05 in two answers: first `open_held_file!`, because the function can make a document,
  which `find_` must not do, and it changes the open files of the editor, so it ends with `!`; then
  `open_file_page!(path; editor)` with the mark `For the assistant.`, because the assistant gets the
  editor's one document of a file through it, with no tab (G3 open question 11). G4 D10 removed the
  page, so the name is `open_file_document!` (the header of this plan, 2026-11-06). `open_file!`
  stays the open of a person: a file document and a tab. Rejected: `find_held_file_page`, and the
  name `open_held_file!` for a function that also serves the assistant. This is the seam of
  `find_url_document` of G8: a generic function with a default in the lower slice, and its method in
  the slice that can open a file (D7).

Each load of a file into an editor splices what it read, on the editor task, before the content
goes into its file. The base folder is the folder of the file, as for every editor save (§2):

1. The evaluation of `ReloadFileOperation`. F5, "Load it" of the band, and
   `ApplyFileTextOperation`, which stores the answer of the text cell of a file (G4 step 2),
   evaluate it (§4.7).
2. The open of a file that a person or the assistant opens, where that open reads the file at once:
   `_make_opened_file`, which `OpenFileOperation`, `open_file!` and the acquire of a
   `FileSystemFile` (through `_read_opened_file`) use. The splice runs before the history wraps the
   content, so the history gets no step.
3. The load of the explorer content, with the folder of the window as the base folder (§4.8).

A new file document reads nothing at the open. When a view draws it, its text cell reads the file
after the frame, and `ApplyFileTextOperation` loads it through `ReloadFileOperation`. That load
splices the held files of that file in the same way. So a held file of a held file gets its file
document only when its holder is read, and the editor reads no file that no view draws. Until its
read, the view of the file shows that it reads, and the file refuses a save (G4 D4). G4 step 2 made
the refusal; the view that shows the read comes with step 5, because step 5 makes the first file
that a person sees before its read.

A slot holds the editor's one file document of the file, and a card shows its own view of it
(open question 5, G4 D2). Each held file document is watched while a holder holds it (G4 D10). No
reader and no computation calls the splice. The editor is its argument, and its list of open files
is its own session document (D0).

### 4.7 A reload is a load (D7)

The evaluation of `ReloadFileOperation` splices the new content as §4.6 says, before
`replace_wrapped_document!` puts it into the file. So a reload of a holder gives each `file("…")`
the editor's one file document of that file. That is the file document that the old content held,
which the open files of the editor list while the holder holds it, or a new file document that is
not read yet. A card that another program adds to the holder shows its file when a view draws it,
and no reference leaf stays in a document of the editor. The reload reads no held file. The
file-format slice holds the reload and calls `open_file_document!`, and the method of the
file-system slice makes the file document. So the reload needs no opener of a higher slice.

### 4.8 The explorer content

`save_explorer_content!(content, path; folder, editor)` saves the section as a `.pred` file saved
alone, through `save_file_text!`, with `folder` as the base folder of its names (D8). The
application gives the folder of the window, `root`. The `PredFile` of the section has the path of
the state file as its name, so the save writes that file. `load_explorer_content(path; folder,
editor)` reads it with `load_file(folder, relpath(path, folder))`, which splices the markers into
the file itself, and then splices its held files with `folder` and `open_file_page!` (§4.6). A
card of a dashboard in the explorer content of `/work` that holds the page of `/work/notes.md` then
saves as `file("notes.md")`. The next start gives the card the page of a tab of `notes.md`, else a
page that reads its file when a view draws it.

### 4.9 The save check of D15

No step changes the check. The page of the holder checks its own file and writes only that file
(`FilePage.jl:186-202`). The save of a holder writes no held file. So the hash and the band of a held
page do not change, and a held file keeps the edits that no save wrote (D9). A page that is not read
yet refuses its own save (G4 D4, G4 step 2), and the save of its holder writes only `file("…")` for
it.

### 4.10 Where this plan meets G3, G4 and G5

Steps 1 to 4 need no other plan. Step 5 needs G4 step 2, and step 6 needs step 5 (D6). Open
question 9 asks the owner for the order of the plans.

| Plan | What it needs of this plan | What this plan needs of it |
| --- | --- | --- |
| **G3, the picture** | A card, a tab and a row hold the opened picture (G3 D1). Steps 1 and 2 save it as `file("…")`. Step 5 gives the card back the editor's one page of the picture. No step of G3 saves a dashboard. | A picture is `ImageFile <: FileDocument`, a file that a person does not edit, and its content is `Image <: ImageDocument` (G3 D1, D9). The default of `find_held_file` covers it, because it is a file document. Its pixels are a background cell (G3 D2), and the watch only reports a change (G3 D12). So the open of a held picture makes its page and reads nothing: no pixel, and no time or size. The card draws the page, the page draws its file, and the file draws its picture (G3 §3.8). |
| **G4, a tab and a card of one page** | The card holds the page and keeps its view in a slot that no walk enters (G4 D2, D3), so the save writes no view. Steps 1, 2 and 3 save the card as `file("…")`. Step 5 gives the card back the page of a tab of the file, and step 6 does the same for the explorer content. G4 D7 leaves the save to this plan, and no step of G4 saves a dashboard. | G4 step 2: the text of a page is a background cell, the watch only reports a change, a page that is not read yet refuses a save (G4 D4), and a page can be made with no read. Step 5 needs it, and G4 step 2 says that the reload of this plan goes through the same cell. G4 step 1: a dashboard holds its cards, so a held page is shared with a tab only while the dashboard holds it. G4 D8: no bare file is watched, so the editor's one page of a file is a page. G4 step 1a: a tab holds a view of a page, and `save_user_interface` then needs `find_held_file` for that view (open question 8). |
| **G5, the table of records** | A record is a named tuple with a picture in a column (G5 D2). Steps 1, 2 and 4 save it as `file("…")`. Without step 4 the `.pred` writer writes the held file whole in the record. Step 5 gives the record the page of the picture. | Nothing. A cell of a roster draws a picture only for an `ImageFile` (§2), so a record that holds the page of a picture shows text until G3 or G5 draws the picture of a page (open question 10). |

## 5. Decisions

**D0. The fix is option A.** Decided by the owner on 2026-11-05.

- A picture is a file document that a person does not edit: `is_editable_file_type` answers
  `false`. A dashboard card, a tab and a row of a table hold the opened file (G3 D1).
- A file saved alone writes `file("…")` for each opened file that it holds, with the path relative
  to the folder of the saved file, and does not write the held file. Edits of the held file that are
  not saved stay until the person saves that file. An open of the saved file opens each named file
  through the opened files of the editor, so a tab and a card share one opened file. The fix is for
  every file kind, not for pictures only.
- Rejected by the owner, option B: save the holder as a project of all files that it holds. That
  writes each held file, edited or not, and tries to write picture files that only another program
  writes.
- The example: a dashboard in `/work/evolution.pred` with `DashboardCard("qos/jitter_qos", <the
  opened file /work/commits/9b919d0c46/qos/jitter_qos.png>)` saves as
  `DashboardCard("qos/jitter_qos", file("commits/9b919d0c46/qos/jitter_qos.png"))`.
- Rules of the owner from earlier: no global state, and the session documents and the registries
  belong to the editor; a reader reads no disk; outside state is read on a task, not in a
  computation; the editor is lazy, so a value that is not visible is not computed.

The owner decided D1, D2, D6, D7 and D8 on 2026-11-05. The assistant proposed D3, D4, D5, D9, D10,
D11 and D12, and the owner approved them with the plan on 2026-11-05, when the owner approved its
implementation.

**D1. `file("…")` names the file in every place, and `node(file("…"), "")` names its root node.**
The owner decided this on 2026-11-05 (open question 1), with no regard to backward compatibility.
The owner's example spells a held file `file("…")`, and today that marker loads as the content of
the file (§2). With one meaning for each verb, the load gives back what the save cut. The two
loaders of omnet-julia that search the set for the file again then get the file at once.
Rejected:

- Keep `file("…")` for the root node, and give a held file a verb of its own, such as
  `opened_file("…")`. Every file on disk keeps its meaning, but the spelling of the owner's example
  changes. Open question 1.
- Choose by the declared type of the slot. A slot of type `Any`, such as the content of a card,
  takes both.
- Choose by the kind of the file, such as a file that a person does not edit. The owner decided that
  the fix is for every file kind.

**D2. A path in a marker is relative to the base folder of the save, with `..` for a file outside
it.** The owner decided this on 2026-11-05 (open question 2, option A). Every editor save gives the folder of the saved file as the base folder (§2), so there the path
is relative to the folder of the saved file, as the owner decided. `load_file(base_dir, filename)`
reads the names of a file against `base_dir`, so the save and the load agree also for a file name
with a folder in it. A held file with a relative name is relative to the base folder too, as a file
of a project is. Rejected:

- An absolute path for a file outside the folder. The text then changes with the machine and the
  checkout, and a diff shows it. Open question 2.
- An absolute path always, for the same reason.
- The folder of the file, also when the file name holds a folder. Then `load_file(d, "sub/a.pred")`
  reads the names against another folder than the save wrote them for.
- The same rule for the project save. `save_user_interface` gives the files their absolute names,
  and a tab that it loads saves through that name (`UserInterfaceFile.jl:34-44`,
  `DocumentFile.jl:246-247`). That change belongs to its own plan.

A file on another drive of Windows has no relative path, and the save writes its absolute path then.

**D3. A held file with no name refuses the save.** The log names the holder, the path of the slot
and the reason: the held file has no name, so save it first with "Save as". The save answers
`false` and writes nothing, as a save that can not cut does now. Rejected: write the held file in
the holder, because the next load then makes a second document of that file. Rejected: write
`nothing`, because the save then loses a part and says nothing.

**D4. A page saves as the file that it shows, through `find_held_file`.** A page keeps the state
of one file against the disk and the scroll pane of its tab, and a save of content writes no view
state (`architecture-rules.md`, "Content documents and view documents"). A new function with a
default widens the contract of a file type, as `is_written_inline` and `is_editable_file_type` did.
Rejected:

- Follow `get_edited_field` to a file document for every node. A tab, a navigator and an
  arrangement name a field too (§2), so a tab would save as its file and lose its title.
- `is_file_document(::FilePage) = true`. A page has no file name and no content of its own, and
  every walk that takes a file document would take it.
- A `pred_arguments` of `FilePage` that writes its file only. The load then builds a second page
  of one file, which G4 D2 rejected (B).

**D5. The cut and the splices go into a tuple and a named tuple, for a held file only.** A record
of G5 is a named tuple, and its picture is a held file. Rejected: own and cut every node in a tuple.
A node there that no file owns is then an orphan, and a save that writes now would refuse. Rejected:
no change. The writer then writes the held file whole, and a load never splices it (§2).

**D6. The load reads no other file, and the open of a file in an editor opens what it holds.**
The owner decided on 2026-11-05 (open question 4, option B) that the open is lazy: the open of the
holder makes the page of each held file, of the same type as an eager open makes, but it does not
read the file. The text of the page is a background cell (G4 D4, decided on 2026-11-05): when the
page is drawn, a task reads and parses the file after the frame, and the `apply` stores it. So the
read runs off the editor task and only for a page on the screen. Until the read ends, the page
shows that it reads, and a save of it is refused, so an empty page never writes over its file.
Rejected: the eager open below, which reads each held text file at the open on the editor task.
§4.6 and the steps must follow this decision.

The splice runs where a file goes into the editor: in the evaluation of an open or of a reload, or
at the start of the application, on the editor task. The editor is its argument, and the open files
are its own session document. The splice makes pages and reads no file. Rejected:

- The eager open, which the assistant proposed first: the open of the holder reads each held text
  file at once on the editor task, and opens the held files of each held file in the same way. A
  dashboard of 17 Markdown pages then reads 17 files at its open, also the cards below the screen.
  Open question 4.
- A placeholder of another type: the load puts a document that holds the path, and its acquire takes
  the opened document, as `FileSystemFile` does. The placeholder puts a fact of storage into the
  document, against `FileCut.jl:4`, and the holder holds another type than it saved. G3 rejected the
  same for the picture (model A). The page of D6 is the type that an eager open makes, so it has
  neither fault.
- Resolve the leaf in a reader or a computation. A reader reads no disk.
- A table of open files outside the editor. The open files belong to the editor.
- Give the slot the file document and not the page. A card then shows an editable file with no page,
  so a change on disk is only logged (`FilePage.jl:337-345`), and G4 D2 wants one page for a tab and
  a card. Open question 5.

**D7. A reload is a load.** The owner decided on 2026-11-05 (open question 7) that a reload of a
holder does what its first load does: the same splice of each `file("…")` to the editor's opened
page of that file, or to a new page that is not read yet (D6), and the same lazy read. One generic
function serves both: the file-format slice, which holds the reload, declares it, and the
file-system slice, which opens a page with the history of the settings, adds its method, as
`find_url_document` of G8 works. So a new card in a rewritten holder shows its file, and no raw
marker stays in a document. §4.6 names that function `open_file_page!(path; editor)`. The
rejected proposal says that the reload can not open a page, because only the file-system slice
opens a file with the history of the settings. The method of the file-system slice removes that
limit. The text below is the rejected proposal.

**Rejected D7. The reload keeps the held files of the content that it replaces.** The reload belongs to the
file-format slice, and only the file-system slice above it opens a file with the history of the
settings. Rejected: open a new held file in the reload, which needs the opener of a higher slice.
Rejected: resolve in the watcher, which runs on its own task and reads no state of the editor.
Open question 7.

**D8. The explorer content saves as a file saved alone, with the folder of the window as the base
of its names.** The owner decided this on 2026-11-05 (open question 3, option A). One way to save holds for every file, and the explorer content stops writing copies
of held files. Rejected: let `print_pred_text` write `file("…")`. It has no base folder, and it also
shows a part to the assistant (`PredFile.jl:301-331`). Rejected: names relative to the state folder.
A file of the work then has five `..`, and the text depends on `XDG_STATE_HOME`. Open question 3.

**D9. The save check of D15 does not change.** §4.9 says why. No step changes `FilePage.jl:186-219`,
`receive_file_change!` or `FileChangeStore.jl`. G4 step 2 changes them for G4 D4.

**D10. A node inside another file stays as the save alone writes it now.** The owner's decision
names opened files, not nodes in them. A save alone writes a node of its own domain in its own text,
also a node that another opened file holds, so the load gives a copy. It writes a node of a text
format inline when it can, as a `.pred` file does, and refuses any other node with the reason in the
log. Rejected: write `node(file("b.json"), "entries[1]")` for a node that an open file holds. The
save then needs the editor, and a search of every open file for the node, whose cost grows with the
size of each open file. A script saves with no editor. Open question 6.

**D11. A cycle through held files ends at the first held file.** A held file can hold its holder
back: `a.pred` holds `b.pred`, and `b.pred` holds `a.pred`. The save of `a.pred` stops at `b.pred`,
because every walk of the cut stops at a held file (`FileCut.jl:169`, `:189`, `:269`, and the walks
of step 3). The load of one file reads no other file. A load with `follow = true` reads each file
once and splices after it has read all of them (`FileSplice.jl:94-116`), so the cycle is a cycle in
memory. The open in an editor reads no held file (D6), so it never follows a cycle. The page of
`b.pred` splices its own held files only when a view draws it and its file is read. Its slot of
`a.pred` then gets the page of `a.pred` from the open files of the editor. One splice asks for each
path once, so two slots of one file in one holder get one page. Rejected: a limit on the depth,
which cuts a long chain that has no cycle. Rejected: refuse a cycle, because a cycle is a graph that
the editor holds in memory now, and the save of one file can write it. Rejected: a table of the
files of one open, with the holder first, which the rejected eager open of D6 needed.

**D11, the display. A place where a file repeats on its own path draws collapsed.** Decided by
the owner on 2026-11-08 ("Infinitely recursive documents should not be printed by keeping the
recursion points collapsed", then "Yes"). Step 5 found that the display has no end for a cycle:
the window draws `a.pred`, its card of `b.pred`, its card of `a.pred`, and so on, until the
memory runs out. The print decides at each place, and nothing stores which places are collapsed.
Each print gets the path from the window to its place (`ctx.reference` of the `PrinterContext`).
A view of a file whose file already appears on that path is a repeat, and it draws as a closed
card: the chevron points right, and the card shows its title and the path of its file, and not
its content. The open state of a repeat belongs to that one place: it is the transient
`collapsed` cell of the `WidgetCard` that the print makes there, as for any card. It is not on the
card document, because one card document stands at every second level of a cycle, and a state on
it would open every level. An opened repeat shows one more level, and the next repeat inside it is
collapsed again, because its path holds the file twice. Two places of one file side by side are no
repeat, and a long chain with no cycle shows whole. Rejected: a limit on the depth, for the reason
above.

**D12. The cut of a `.pred` file walks a positional argument of `pred_arguments` too.** Today the
cut walks only the keywords (`PredFile.jl:148-153`), so the content of a scroll pane and of a
transform pane is never cut, and a held file there is written whole with a copy of its text (§2,
measured). A field is written when its value is a positional argument, by identity, or the value of
a keyword with its name. Rejected: rely on `find_held_file` of the page alone. It covers a page, but
not a card that holds a scroll pane or a transform pane around a file, such as the zoom of a
picture. Rejected: give each such pane a `pred_arguments` of keywords only. Each pane with a
positional content then needs a change, and the next one has the same gap.

## 6. Steps

Each step runs in a worktree, ends with one commit in each repository that it changes, and names
its narrowest test. A test under
`test/platform/` runs in `package/ProjecturedPlatformTest`, any other test in `environment/all`, each
through `workspace/bin/bounded-run`. A step that changes an export also runs
`test_platform_layering()`. No file that a step changes is in `SEALING.md`.

The dependencies: steps 1 to 4 need no other plan, and each needs the step before it. Step 5 needs
step 4 and G4 step 2 on main. Step 6 needs step 5. The first form of this plan had seven steps: the
open and the reload were two. They are one step now, because the first read of a held page goes
through the reload (D7), so no test can check the open without the reload.

1. **`file("…")` names the file (D1).** **Done on 2026-11-05.** `FileSplice.jl`: the splice puts the file document into
   the slot (`_splice_target`, `:244-247`), also for a file whose whole content is a reference
   (`_splice!`, `:176-190`), and `node(…)` takes the empty path for the root
   (`_evaluate_path_text`, `:338-350`). `FileCut.jl`: `_reference_marker` writes
   `node(file(…), path)` for every node, the root too (`:366-370`). The text that says that
   `file(…)` names the content: `FileProject.jl:29`, `serialization.md`, the docstring of
   `save_user_interface` (`UserInterfaceFile.jl:25-32`) and `pane.md:242`, which also lose the claim
   that the save aborts. In omnet-julia, `load_catalog_shell` takes the file document from the slot
   (`CatalogShell.jl:420-428`). That commit lands on main together with this one, and it has no plan
   of its own (open question 1). Found in the implementation: `finish_omnet_project!`
   (`OmnetProject.jl:117-147`) also takes the file from the slot, and `_file_holding` goes. After
   step 1 its search finds no file whose content is a file document, so it answered the slot value
   and did nothing; its docstring said that `file("mm1k.jl")` names the content, which is no longer
   true (D1: both loaders "then get the file at once"). Test: a
   new set in `test_file_project()` (`test/projectured/serializer/FileProjectTest.jl`), "a file
   document that a node holds loads back as that file, and the root of a file is
   node(file(…), \"\")". The sets that assert `file("…")` for a root change:
   `FileProjectTest.jl:163`, `:197`, `:215-216`, `:265`, `:354`, `:405`, `:420-421`, `:439-448`,
   `:599`, `:610`. `test_user_interface_file()` asserts that the tab holds the `JsonFile` again.
   `test_research_assistant_api()` saves a study folder whose report is the root of `study.md`, and
   reads it back to the same graph with no byte changed at the second save. Also
   `test_research_combinations()`, `test_marker_vocabulary()`, and `test_marker_language()` with
   `test_pred_file()`. In omnet-julia: `test_demo_catalog()` (`test/presentation/DemoCatalogTest.jl`)
   and `Pkg.precompile()`.

   What the implementation found:
   - The new set of `test_file_project()` takes the root of the other file from another domain (an
     XML element), because a node belongs to the first file of its own domain that reaches it. A
     JSON root of `other.json` is written inline by `root.json`.
   - Three more tests asserted a root with a bare `file("…")` and now assert
     `node(file("…"), "")` exactly: `PredFileTest.jl:152`, `WorkflowConversationTest.jl:42`, and the
     hand-written markers of the tolerant load and of the list of `TestBag` in `FileProjectTest.jl`.
   - `test_user_interface_file()` reads the object through `get_file_content` of the `JsonFile`
     that the tab holds again.
   - In omnet-julia, the catalog pages embed `<<file("pages/….pred")>>` and now hold the file
     document. `test_demo_catalog()` passes with no change to a page.
   - Results: the projectured-julia sets pass, with one error that main has since `961df53cb`
     (`MarkerVocabularyTest.jl:88`, the section of a Markdown page) and the known broken set of a
     Julia file. In a scratch environment with both worktrees, omnet-julia `Pkg.precompile()`
     builds 94 packages, and `test_demo_catalog()`, `test_project_load()`, `test_project_reload()`,
     `test_project_errors()` and four workbench sets pass, 408 tests. Of the recorded calls of
     omnet-julia that no longer resolve, 2 name `_file_holding`, which this step removes; the
     others come from main since the lists were recorded on 3 November.
2. **The save alone writes a held file as `file("…")` (D2, D3, D12).** **Done on 2026-11-05.** `FileCut.jl`: `_cut_copy`
   (`:267-285`) and `_cut_leaf` (`:293-299`) write the leaf in both saves, the cut takes the base
   folder of a save alone (`cut_file_text`, `:403-408`), and a marker of a save alone names a file
   relative to it (`_reference_marker`, `:366-370`). An unnamed held file refuses (D3).
   `PredFile.jl`: `is_written_in_file` takes the positional arguments too (`:148-153`, D12). The
   docstrings of `save_file!`, `save_file_text!` and `cut_file_text`, and `serialization.md`. Test:
   a new set in `test_pred_file()`, `test/platform/serialization/PredFileTest.jl`. A `PredFile`
   that holds a `TextFile` writes `file("notes.txt")`, and `file("../other/notes.txt")` for a file
   outside the folder, and the folder holds no new file. A `WidgetScrollPane` around the held file writes
   `WidgetScrollPane(file("notes.txt"), …)`. A held file with an absolute name gives the same text.
   An unnamed held file logs the reason and answers `false`. A `PredFile` with an absolute name that
   holds one document at two places loads back with one object. `test_file_project()` keeps its set
   "a foreign node is rejected".

   What the implementation found:
   - The cut carries one value, `_FileCut`: the owners, the nodes that the copy wrote, the mode and
     the base folder. The cut functions had six positional arguments, and the base folder would
     have been the seventh. `_cut_leaf` goes: in a save alone the set holds one file, so no node
     has another owner, and its only refusal was the held file. `_reference_marker` is
     `_make_reference_marker`, and `_compute_marker_file_name` gives the name of a file in a marker.
   - A held file with no name refuses in a project save too, because `file("")` names no file.
   - The refusal of a foreign node keeps its words: such a node needs a reference into a file of
     its domain, and a save alone has none.
   - A limit: `make_inline_leaf` of a `.pred` file cuts the text of an inline node with the working
     folder as the base, so a file document inside a JSON value that a `.pred` file writes inline
     is named relative to the working folder. No document makes that case now.
   - Results: the sets of step 1 and `test_text_file()` pass, 475 tests, with the error that main
     has at `MarkerVocabularyTest.jl:88` and the known broken set of a Julia file.
3. **A page saves as the file that it shows (D4).** **Done on 2026-11-05.** `find_held_file` with its default in
   `FileCut.jl`, its export in `SerializationModule.jl`, and its row in the table of defaults of
   `serialization.md`. The walks `_own_walk!` (`:189`), `_own_inline_walk!` (`:169`),
   `_collect_fixed_nodes!` (`:226`) and `_cut_copy` (`:269`) ask it in place of
   `is_file_document`. `FilePage.jl` adds the method for a page (`find_page_file`, `:76-85`), and
   `fileformat.md` says it. Test: a new set in `test_explorer()`
   (`test/platform/explorer/ExplorerTest.jl`): a `.pred` dashboard whose card holds the page of a
   text file saves alone as `DashboardCard("notes", file("notes.txt"))`, with no hash and no scroll
   pane. A new set in `test_file_change_store()` (`test/platform/filechange/FileChangeStoreTest.jl`)
   for D15: the save of the page of the holder writes only the holder, the held page keeps its hash
   and its band, the held file keeps its bytes on disk, and its history keeps the edits that no save
   wrote. A page that is not read yet comes with G4 step 2, and step 5 tests its save.

   What the implementation found:
   - The module `FileChangeTests` of `ProjecturedPlatformTest` imports `Dashboard` and
     `DashboardCard`, because the new set holds the page in a card.
   - Between this step and step 5, `save_user_interface` writes a tab that holds a page as
     `file("…")`, and `load_user_interface` gives that tab the file document with no page. No code of
     projectured-julia or omnet-julia calls the two functions; only tests and scripts do.
   - Results: the sets of step 2, `test_explorer()`, `test_filechange()` and `test_file_tab()` pass,
     964 tests. `test_platform_layering()` fails at "every file imports what it extends"
     (`CheckLayering.jl:889`), as on main since `550163da1` and in the baseline of main `6e482a59c`;
     no entry of its list names a file of this step. The error of `MarkerVocabularyTest.jl:88` and
     the broken set of a Julia file are the known ones.
4. **A held file in a tuple or a named tuple (D5).** **Done on 2026-11-05.** `FileCut.jl`: `_cut_field` (`:329-349`) and
   `_cut_copy` go into a tuple and a named tuple for a held file. `FileSplice.jl`:
   `_collect_references!` (`:137-160`) and `_splice_walk!` (`:195-226`) go into them and build them
   again. Test: a new set in `test_pred_file()`: a holder with
   `records = [(number = 1, picture = <a held TextFile>)]` saves alone as `picture = file("p.txt")`,
   and `load_project(…; follow = true)` gives the `TextFile` in the named tuple. A plain value in the
   tuple stays as it was.

   What the implementation found:
   - A record of a list is an element of a vector, so `_cut_copy` goes into a tuple too, not only
     `_cut_field`. The rule of the fields of a `.pred` file, `_holds_document`, looks into a tuple, a
     named tuple and a vector at any depth, or the cut would not walk a list of records.
   - The `.pred` writer and parser need no change: they write and read a `file("…")` in a named
     tuple as a `PredReference` already, and a list reads as `Any[]`, so the splice can put a new
     tuple into it.
   - The test also holds a plain tuple and a named tuple in a named tuple, checks that two places of
     one path hold one file after the load, and that a load of the file alone keeps each reference
     and saves it back unchanged.
   - Results: the sets of step 3 pass, 984 tests, with the same three known results.
5. **A load into an editor gives each `file("…")` its file document (D6, D7, D11).** **Done on 2026-11-07.** Needs G4
   step 2 on main (landed 2026-11-07, `140ae8853`). `FileSplice.jl`: `splice_held_files!`, with
   its export in `SerializationModule.jl`. `OpenFileList.jl`: the generic function
   `open_file_document!` with its docstring and its default, beside `find_open_file_document`
   (`:92-119`), and its export in `FileFormatModule.jl`. Its docstring has an example
   (`file = open_file_document!(path)`, then `insert_elements!` of `make_file_view(file)` into a
   card) and ends with the line `For the assistant.`, and the tests of this step also run
   `test_assistant_documentation()` and `test_assistant_verbs()`. `DocumentFile.jl`: the
   evaluation of `ReloadFileOperation` (`:568-573`) splices the new content before
   `replace_wrapped_document!`. `FileSystemDocument.jl`: the method of `open_file_document!` for an
   `Editor`, which makes a file document with `make_unread_file` and the history of
   `_make_opened_file`, and the splice in `_make_opened_file` (`:243-247`), where the open reads the
   file at once. `FileViewToWidget.jl`: the view of a file that is not read yet
   (`loaded_count < 0`) shows that it reads, as the folder of the Files tree shows its read, and
   the content below it is the seed of the extension. `find_held_file(view::FileView)` exists
   (`FileView.jl:55`), so open question 8 needs no code. Update `serialization.md`,
   `fileformat.md` and `filesystem.md`. Tests:
   - `test_pred_file()`, a new set for the walk, with an answer from a dictionary. A whole `file(…)`
     takes the answer, a `node(…)` stays, and an answer `nothing` keeps the leaf. Two slots of one
     path ask once and hold one object. A slot in a named tuple takes its answer. `file("../b/c.txt")`
     asks for the absolute path against the base folder.
   - `test_explorer()`, a new set with an editor and a `FileChangeStore`. An open of a `.pred`
     dashboard whose card holds `file("notes.txt")`, while a tab shows `notes.txt`, gives the card
     the file document of that tab (`===`). With no tab, the card holds a new file document, and its
     text cell counts no read until a view of the card is drawn, then one read after that frame.
     Before that read, the view shows that it reads, a save of the file answers `false`, and
     `notes.txt` keeps its bytes. A save of the dashboard then writes `file("notes.txt")` for that
     file document.
   - `test_file_change_store()`, a new set with an editor and a tab of the holder. Another program
     rewrites the holder with another title, the held path of before and one new held path. After
     the read of the holder (the report, a frame and `ApplyFileTextOperation`), the slot of the old
     path holds the same file document, the slot of the new path holds a new file document that is
     not read yet, and no slot holds a reference leaf. F5 gives the same. The file document of the
     new card is held and watched once the dashboard holds its cards (G4 step 1); if it is not,
     because a load writes the content with no hold, the test records that as the known limit of G4
     open question 10 and does not hide it. A dashboard `a.pred` in a tab holds `b.pred`, which
     holds `a.pred`: the open reads `a.pred` only, and after a view draws the card of `b.pred` and
     its read, the slot of `a.pred` in `b.pred` holds the file document of the tab (`===`). With no
     editor, `evaluate_operation(nothing, ReloadFileOperation(file))` keeps each leaf.

   Then `test_filechange()`, `test_file_tab()`, `test_user_interface_file()` and
   `test_platform_layering()`.

   **5b. The display of a cycle (D11, the display).** **Done on 2026-11-08.** Added on 2026-11-08 after the owner decided
   it. The view of a file whose file already appears on the path of its place draws as a closed,
   collapsible card with its title and the path of its file, and prints no content while it is
   closed. Every printer that draws the content of a held file inside another document follows
   the rule (the view of a file, and `FileToContent` if it draws a held file without a view).
   Tests: the tab of `first.pred`, which holds `second.pred`, which holds `first.pred`, as the root
   of an editor with the headless backend: after `second.pred` reads, frames end and the memory
   stays bounded; the card of `first.pred` inside `second.pred` is collapsed and its content is not
   printed. A click on its chevron (`ToggleCollapseOperation`) shows one more level, and in it the
   card of `second.pred` is collapsed. Two cards of one file in one dashboard both show it. A chain
   `a.pred` → `b.pred` → `c.pred` with no cycle shows whole. Then the tests of step 5 again.

   What the implementation found (5b):
   - The cycle is not in `FileViewToWidget`: a card of a dashboard holds the file document itself
     before its view exists, so the cards print through `FileToContent`, and the view of a file
     prints its file in its scroll pane through `FileToContent` too. The rule is in `FileToContent`
     alone (`FileToContent.jl`); a view follows it with no code of its own. A file type that
     registers a projection of its own for its file does not follow it.
   - Which way finds the files on the path: the per-print value in `ctx.properties`
     (`:path_files`, a tuple of files, outermost first). The path `ctx.reference[]` is not usable:
     measured, it is a path through the output of the print (`::VerticalLayout.children::CellVector[1]
     ::PredFile.content::UndoBuffer.content::VerticalLayout...::WidgetCard`), not a path from the
     root document. It names the type of each file and not the file, and `evaluate_reference` on the
     root of the editor raises `ReferenceTypeMismatchException`. `FileToContent` prints the content
     of a file through `print_child` with a context that it extends with `with_property`, and the
     prints of the widget stage below it inherit the properties, so the value is there at every
     level of the cycle. Nothing is stored in a document, and no kernel file changed.
   - A `WidgetCard` prints its content once, when it is made, whatever `collapsed` says
     (`print_document(::WidgetCardToGraphicsCanvas)` calls `print_child` on `w.content` before
     `_card_build` reads `collapsed`), so a closed card with the file content as its content would
     print the cycle without end. Measured: a content computed from `collapsed` is read once and
     does not follow a toggle. The card holds a `VerticalLayout` whose children are a reactive
     `CellVector` that is empty while the card is closed, which is the reactive-list form that the
     card comments name. A toggle fills the list and the content prints then.
   - Measured with the reproduction script: before, the process reached 8 GB (killed, OOM) in 4
     minutes in `_run_frames_until`; after, it ends in 22 seconds with 100 MB live, and five more
     frames and a hand draw take 0.0 s each.
   - The press on the chevron (second commit of 5b). The first test toggled with
     `ToggleCollapseOperation` because a press in a headless editor with no window did not fold
     even a plain collapsible card: with no window a dashboard has no hit region (measured; a plain
     card in a `Dashboard` takes the press only in a window, `_explorer_window_editor`). In a
     window, the press on the chevron of a repeat reaches the card by the coordinates of the
     pointer, through the readers of the layouts and the cards above it. Measured with a debug
     print in `_read_card_click`, in a window, before and after the change to the map below. So the
     first test hid a defect of its harness, not of the print.
   - A press on the repeat of a cycle of dashboards (a dashboard holds a card of a file that holds a
     dashboard) still does not arrive in a window, with a plain collapsible card in the same place
     and no file at all: a card of a dashboard that holds a dashboard takes presses only in the first
     ~70 pixels of its height (measured with presses at 20 to 160 pixels), so a chevron two
     dashboards deep lies outside the region that the card hits, and a person scrolls the inner
     page to reach it. That is the height of a dashboard in a card, and not the repeat; it is not
     changed here. The test of the press uses cards of files, which have no such clip.
   - The print of a repeat answers a `ContentIoMap` whose input is the file and whose inner map is
     the map of the card, as for a file that is not a repeat, so a parent that follows a route finds
     the file. `_is_repeated_file` tells the two (the inner map is not the map of the content of the
     file). A repeat reads a gesture with the reader of its card and maps no path, forward or
     backward, so the paths of the file are not mapped into an opened repeat: the caret does not
     enter it and a key does not edit it, because the card shows the content in a layout, and no
     map aligns the path of the file with a path in that layout. A press by coordinates works in an
     opened repeat (the second press of the test opens the repeat inside it). To make it editable,
     the content would show with no layout in between and a map of `content.<rest>` to the card, or
     the layout would get a map of `content` to `children[1]`; no one has asked for it. The owner,
     2026-11-08: a read-only opened repeat is "acceptable for now".
   - `get_path_files` is `_get_path_files` (one file; the name had two uses, so a text rename).
   - Tests: a set of `test_explorer()` has the tab of `first.pred` as the window (the frames end and
     one closed card shows), and a set presses the real pixel of the chevron in a window, with a
     file of a card that holds a file of a card that holds the first file: one press opens the
     repeat of `a.pred` (one more level; the repeat of `b.pred` in it is closed), and a second press
     opens that one (the repeat of `a.pred` in it is closed again). Two cards of one file, and the
     chain `a.pred` → `b.pred` → `c.pred`, show whole.
   - Results (projectured-julia): `test_explorer()` 379 pass (19 new); `test_pred_file()` 87 pass;
     `test_filechange()` 228 pass and 1 broken; `test_file_tab()` 31; `test_user_interface_file()` 22;
     `test_assistant_documentation()` and `test_assistant_verbs()` pass as before.
     `test_platform_layering()` fails the same two sets as main. omnet-julia: `test_demo_catalog()`,
     `test_workbench()`, the workbench tests, `test_fingerprint_store_document()` and
     `test_project_page()` pass.
   What the implementation found:
   - `_splice_walk!` and `_splice_tuple` of `FileSplice.jl` take a `resolve` function in place of
     `(project, index, tolerant)`, so `load_project` and `splice_held_files!` share one walk.
     `splice_held_files!` answers the content: the content itself, or the answer when the whole
     content is a `file("…")` leaf.
   - Decision: the generic function has two forms. `open_file_document!(path; editor =
     find_evaluation_editor())` is the one that the assistant calls, and it calls
     `open_file_document!(editor, path)`, whose default answers `nothing`. Julia can not dispatch on
     a keyword, so the method of the file-system slice is for `editor::Editor` in the positional
     form. It runs under `run_on_editor_task!`, because it changes the open files of the editor, so
     a call of the assistant from another task is posted, and a call from the evaluation of an
     operation runs at once.
   - Deviation from the plan text: the example in the docstring puts the file document in a card,
     `DashboardCard("notes.md", file_1)`, and not `make_file_view(file_1)`. A card holds the file and
     makes its own view (G4 D3); a view as the content of a card would be a view of a view.
   - `ReloadFileOperation` splices only when `editor isa Editor` and the file has a name
     (`_splice_open_files`), so a reload with no editor keeps each leaf and walks nothing.
   - `_make_opened_file` splices before `op.wrap` and the history, with `dirname(abspath(op.path))`
     as the base folder. The history wrap of the settings is now made by `_make_editor_history_wrap`,
     which `_make_opened_file` and the method of `open_file_document!` both use.
   - The view of a file that is not read yet (`loaded_count < 0`): the folder shows its read in
     three places, the tree row `WidgetTreeNode(:loader, "reading")`, the heading
     "<path> · reading" (`FileSystemDirectoryToWidget.jl:112`) and the condition `:running` of its
     decoration. The view uses the words of the heading: a row above the scroll pane that says
     "<name> · reading", built as a `LayoutConstraint` of a `WidgetLabel` with a height of its
     content. It takes the place of the band, so the scroll pane is the second child while a band
     or the row shows (`_get_file_view_scroll_steps`), and the row names no place. Decision: the
     decoration of the file got no `:running` condition, because the plan names the view only; a tab
     label of an unread file shows no loader.
   - A file in the open files before a holder holds it is not watched. After the reload of a holder
     in a tab, the new file document of a card is in the open files, and neither held nor watched,
     because nothing holds what the content of a file holds. The set in `test_file_change_store()`
     records that as `@test_broken` (G4 open question 10).
   - A cycle of files that hold each other can not be printed to its end: with the tab of the first
     file as the root of the editor, the frame ran out of memory (10 GB) once the second file had
     read and held the first. The test of the cycle puts a plain document at the root of the
     editor. The assistant reproduced it on 2026-11-08: the headless paint builds card, view, card
     without end, 8 GB in about 40 seconds, while the save, `search_documents` and `repr` of the
     same cycle end. Step 5b makes the display end (D11, the display).
   - `FileChangeTests` of `ProjecturedPlatformTest` imports `search_documents`. The explorer set
     defines its frame and draw helpers locally, because `ExplorerTest.jl` is in the main module of
     the test package and the helpers of the file-change test are in another.
   - A self-reference `file("a.pred")` inside `a.pred` gets a second, unread file document of
     `a.pred` while `_make_opened_file` reads it, since the file is not in the open files yet. The
     save writes a marker into itself as `node(file(…), …)` and the root as `file(…)` only for a
     held file, so a normal file does not write this.
   - Results (projectured-julia): `test_pred_file()` 87 pass; `test_explorer()` 360 pass;
     `test_filechange()` 228 pass and 1 broken (the hold above); `test_file_tab()` 31 pass;
     `test_user_interface_file()` 22 pass; `test_assistant_documentation()` 27, 196 and 2839 pass;
     `test_assistant_verbs()` 83 pass. `test_platform_layering()` fails in two sets, "qualified
     references name only exported symbols" (`AssistantList.jl` and `PaneModule.find_pane_tab_layer`)
     and "every file imports what it extends" (`CheckLayering.jl:889`); the main checkout fails the
     same two with the same entries, and no entry names a file of this step. The Julia process of
     `test_filechange()` and of `test_pred_file()` plus `test_filechange()` ends with a SIGSEGV of
     the compiler (LLVM) in a watcher thread after `END-OF-TESTS`; the tests had finished.
   - Results (omnet-julia at `ced3d0cdb` with this worktree): `test_demo_catalog()` 362 pass;
     `test_workbench()` 182 pass; the workbench tests of `OmnetWorkbenchTest.jl` and
     `OmnetWorkbenchToWidgetTest.jl` pass; `test_fingerprint_store_document()` and
     `test_project_page()` of `OmnetLegacyTest` pass (100 for the page). omnet-julia needs no change.
6. **The explorer content saves alone and splices its held files (D8).** **Done on 2026-11-10.** Needs step 5.
   `ExplorerContentFile.jl:60-70` and `:90-99`, with the keyword `folder`. `Application.jl:597-605`
   and `ApplicationExplorer.jl:87-94` give `root`. `explorer.md` says it. Test: the set of
   `test_explorer()` at `ExplorerTest.jl:777-818` grows. A card that holds the file document of a
   file of the work folder saves as `file("notes.txt")` and not as its text, and a file outside the
   work folder saves as `file("../…")`. The next editor, with a tab of `notes.txt`, loads the
   content, and the card holds the file document of that tab (`===`). With no tab, the card holds a
   file document that is not read yet. The line numbers of this step are from 2026-11-05; read the
   code again before the step starts.
   A section that holds one dashboard at two places loads back with one object. The session lists
   and the titles read back as now. Then `test_application()`, because `Application.jl` changes.

   What the implementation found (6):
   - `ExplorerContentFile.jl`: `save_explorer_content!(content, path; folder, editor)` makes a
     `PredFile` named `relpath(path, folder)` and saves it with `save_file_text!(file, folder)`, so
     a file document in a card writes `content = file("notes.txt")`, or `file("../outside/far.txt")`
     outside the work folder, and a node that the section holds at two places writes once, with a
     marker into the state file for the other place. `load_explorer_content(path; folder, editor)`
     reads with `load_file(folder, relpath(path, folder))` under the evaluation editor, then
     `splice_held_files!(content, folder, held -> open_file_document!(editor, held))`. `folder` is a
     required keyword: both callers set it. The save keeps its warning for an exception; a refusal
     of the cut (a held file with no name) is logged by `save_file_text!` and writes nothing.
   - `Application.jl` passes `folder = root` to the save, and `_restore_explorer_content!`
     (`ApplicationExplorer.jl`) takes the folder and passes it to the load. `ExplorerModule` uses
     `FileFormatModule` for `open_file_document!` (it is included before the explorer).
   - The plan text said `open_file_page!` and line numbers of 2026-11-05; the code has
     `open_file_document!(editor, path)` and the lines above.
   - The save writes no held file and the save check of the held file document is untouched (D9);
     the test checks that `notes.txt` and `far.txt` keep their bytes and that the work folder gains
     no file.
   - Test: a new set of `test_explorer()` ("the content of a folder saves a held file as
     file(\"…\") and loads it as the file document of the next editor"), and the set of the state
     folder passes `folder`. The next editor with a tab of `notes.txt` gives the card that file
     document (`===`); `far.txt` has no tab, so the card holds the open file document of the editor
     that is not read yet (`loaded_count < 0`, `read_count == 0`); a dashboard at two places loads
     back as one object; the session list is the list of the next editor.
   - Results (`d5e20db7d` before, this step after, one run each): `test_explorer()` 383 pass before,
     397 after (14 new assertions); `test_application()` 402 pass, 1 fail, 2 broken before and
     after (the fail is `ApplicationTest.jl:1008`, "a press on the bar of an agent starts it", which
     main has); `test_pred_file()` 87 pass before and after.
   - The load opens each held file with `open_file_document!`, so the explorer slice uses the file
     format slice: the row `"explorer"` of `PLATFORM_SLICE_EDGES` (`test/platform/PlatformSuite.jl`)
     and the list of slices in `explorer.md` name it. The file format slice uses no explorer, so the
     edge makes no cycle. `test_platform_slice_edges()` and `test_platform_layering()` give the
     findings of main and no other.

After step 6 the plan moves to `plan/done/`, and the code quality steward reads the change.

## 7. Risks

- **A new file document is in the open files before any holder holds it.** Since G4 step 1b the
  open files of the editor list a file from its acquire to the release of its last holder (§2).
  `open_file_document!` adds a new file document at once (§4.6), so a call that no hold follows
  leaves it in the list, not watched, until the editor closes. In the loads of step 5 a holder takes
  it in the same operation. A call of the assistant that puts the file into no card, and a load that
  writes a content with no hold, do not. This is the gap of G4 open question 10, which the owner
  deferred on 2026-11-07 to a plan of its own; a file that such a call left reads at its first draw
  when a later holder takes it, because it is not read yet.
- **The meaning of a whole `file("…")` changes for each file on disk.** A hand-written embed, such as
  `<<file("network.ned")>>` in a page of the omnet-julia catalog, then embeds the file document. A
  file document draws as its content through `FileToContent` (`fileformat.md`), so the page looks the
  same. The omnet-julia suites `DemoCatalogTest.jl` and `OmnetWorkbenchTest.jl` tell.
- **omnet-julia `load_catalog_shell` must land on main together with step 1.** Without that
  change, no file of the set has the file document as its content, and the load raises "`index`
  must name a page of this catalog". `finish_omnet_project!` still works, because `_file_holding`
  answers the document itself. `test_demo_catalog()` tells.
- **A study folder writes its report as `node(file("study.md"), "")`.** `test_research_assistant_api()`
  and `test_research_combinations()` tell.
- **The explorer content goes through the cut for the first time.** The cut builds each node of the
  section again with all of its fields, so a type with no constructor of all its fields fails the
  save. The save keeps `run_with_evaluation_editor` around the cut, for the marks of the session lists.
  `test_explorer()` tells.
- **A marker into the explorer content itself names the state file from the folder of the window.**
  A node that the section holds at two places saves as `node(file("../…/explorer/work-….pred"), "…")`,
  and that text depends on `XDG_STATE_HOME`. Step 6 checks that such a section loads back with one
  object.
- **Step 5 needs G4 step 2.** Today the make of a page hashes the text of its file
  (`FilePage.jl:111-117`), and the start of a watch hashes it again (`FileChangeStore.jl:44-49`),
  both on the task that makes or acquires the page. A page with no hash writes with no check
  (`FilePage.jl:191-192`), so a page with no read would write its empty content over its file. G4
  step 2 makes the text a background cell, makes the watch only report a change, and makes a page
  that is not read yet refuse a save. G4 step 2 must also give a way to make a page with no read,
  with the history of the settings around its content, for the method of `open_file_page!`.
- **A dashboard with no height reads each of its held pages.** With no height, a dashboard puts its
  cards in a plain grid (`DashboardToWidget.jl:84-91`), and the backend paints each element of a
  plain layout, also outside the clip (G3 §1). So each held page of such a dashboard can read its
  file after the first frame, also a card below the screen. On a page with a height, the rows of the
  cards are a list. The read runs off the editor task. This is against the words of D6, "only for a
  page on the screen", until the plan of G3 open question 9 makes a plain layout skip what lies
  outside the clip. G4 step 2 tests that a page below the screen of a dashboard reads nothing until
  a scroll shows it.
- **A search finds no text in a page that is not read yet.** `search_documents` and the assistant
  reach the page, but not its text, until a view draws it.
- **A bare file can still be the opened document.** `find_open_file_document` answers a file
  document that no page holds (`OpenFileList.jl:9-13`), and the acquire of a file document watches
  it (`FileChangeStore.jl:280-284`). A link of omnet-julia opens an INI file so
  (`LegacyIniFileEntryToWidget.jl:150-156`) until G4 step 6 changes that link. The slot then holds
  that file, not a page. This is against G4 D8, which decides that no bare file is watched.
- **A file that only another holder holds is shared only while that holder holds it.** Before G4
  step 1, a dashboard does not hold the contents of its cards, so a second open of such a file makes
  a second page, a second watch and a second hash.
- **A reload swaps the content of a holder.** The pages that the new content holds watch their
  files only when a holder of the new content holds them (G4 D3). Step 5 checks that the page of a
  new card is held and watched after the reload.
- **A path with `..` breaks when the holder moves and the held file stays.** The page of that path
  then reads the seed of the extension, as `make_file_tab` does for a path that does not exist.
- **The view of a page in a tab (G4 step 1a).** Without `find_held_file` for that view,
  `save_user_interface` writes the view whole, with a copy of its file. `test_user_interface_file()`
  tells. Open question 8.
- **A record of G5 that holds the page of a picture shows text.** A cell of a roster draws a picture
  only for an `ImageFile` (`RosterToGraphics.jl:138-145`). Open question 10.
- **The cut walks the content of each pane with a positional content** after step 2. A node of a
  text format there, such as a JSON object in a scroll pane, is then written as a tagged string of
  its format and no longer as its constructor, so the text of such a saved `.pred` file changes at
  its next save. `test_pred_file()` and `test_workflow_file()` tell.
- **A `.pred` file that an editor saved before step 2** keeps its absolute marker into itself, and
  its two places load as two objects, as now.
- **The new exports** move the layering guard: `find_held_file` and `splice_held_files!` in
  `SerializationModule`, and `open_file_page!` in `FileFormatModule`.
  `test_platform_layering()` tells. `find_held_file` and `splice_held_files!` carry no mark `For the
  assistant.`. `open_file_page!` carries it (D7), so step 5 can move the rank of `search_api`, and
  its tests run `test_assistant_documentation()`, `test_assistant_verbs()` and
  `test_referenced_document_editor()`.

## 8. Open questions for the owner

1. **The meaning of `file("…")`.** Answered by the owner on 2026-11-05: D1, `file("…")` always
   means the file. Decided by the assistant, as for G8 and G9: the change of `load_catalog_shell` in
   omnet-julia lands with step 1 in the same landing, with no sibling plan. The question was: the assistant recommends D1: `file("…")` names the file in every
   place, a root node is `node(file("…"), "")`, and omnet-julia gets its own plan for
   `load_catalog_shell`, which lands with step 1. The alternative keeps every file on disk as it is
   and spells a held file with another verb, such as `opened_file("…")`, in place of the spelling of
   your example. Which one?
2. **A held file outside the folder of the saved file.** Answered by the owner on 2026-11-05: a
   relative path with `..` (D2). The question was: the assistant recommends a relative path
   with `..` (D2). The alternative is the absolute path for a file outside the folder. Which one?
3. **The base folder of the explorer content.** Answered by the owner on 2026-11-05: the folder of
   the window (D8). The question was: the assistant recommends the folder of the window,
   so a card of the explorer content of `/work` names `/work/notes.md` as `file("notes.md")` (D8).
   The alternative is the folder of the state file, as for any other file. Which one?
4. **When a held file opens.** Answered by the owner on 2026-11-05: option B, a page that is not
   read until something that shows it acquires it (D6). The question was: the assistant recommends the open of the holder (D6). A text file that
   no tab shows is then read at that open, also when its card is not on the screen. The alternative is
   a placeholder that opens at its acquire, which is lazy, and puts a document that holds a path into
   the holder. Which one?
5. **What a slot holds after an open.** Decided by the assistant on 2026-11-05 from the owner's G4
   decisions (one file, one page; each place has its own view): the editor's one page of the file,
   and a card shows its own view of it (G4 D2). The question was: the assistant recommends the opened document of the editor:
   the page when a page shows the file (D6). Then a card of G3 holds the page of a picture, and a card
   of G4 makes its view from the page. The alternative is the file document. Which one?
6. **A node inside another file.** Decided by the assistant on 2026-11-05: no later plan now,
   because the walk does not need it (D10 stays). The question was: the assistant recommends no change: a save alone copies a node of
   its own domain, writes a node of a text format inline where it can, and refuses any other node
   (D10). Do you want a reference `node(file("…"), "…")` through the open files of the editor in a
   later plan?
7. **A new held file in a reload.** Answered by the owner on 2026-11-05: a reload is a load, with the
   same splice and the same lazy read (D7). The question was: the assistant recommends that a reload keep the held files that
   the content held, take the open files of the editor, and leave any other held file a leaf until
   the next open (D7). Must a reload also open such a file?
8. **The view of a page in a tab.** Decided by the assistant on 2026-11-05: G4 step 1a adds the
   method beside its view type and runs `test_user_interface_file()`, because the owner of a type adds
   its method. The question was: G4 step 1a makes a tab hold a view of a page.
   `save_user_interface` saves the tabs, so the cut must stop at that view with `find_held_file`, or
   it writes the view whole. G4 D7 says that G4 does not change the save, and G4 step 1a names
   neither the method nor `test_user_interface_file()`. The assistant recommends that G4 step 1a adds
   the method beside its view type and runs `test_user_interface_file()`. Else step 5 of this plan
   adds it. Which one?
9. **The order of the plans.** Decided by the assistant on 2026-11-05, as recommended: steps 1 to 4
   land before G3, G4 and G5, and steps 5 and 6 land after G4 step 2. The question was: steps 1 to 4 need no other plan. Steps 5 and 6 need G4 step 2 (D6).
   The header of G3 says that this plan lands before G3, and G3 needs only steps 1 and 2 to save a
   picture. The assistant recommends: steps 1 to 4 land before G3, G4 and G5, and steps 5 and 6 land
   after G4 step 2. Is that the order?
10. **A record that holds the page of a picture.** Decided by the assistant on 2026-11-05, from model
    B and "one file, one page": G3 step 2 makes the cell draw the picture of a page too, through
    `get_edited_document`, because `find_page_file` would make a cycle (the file-format slice depends
    on the roster slice, found by the G3 pass). The question was: after step 5 a record of a `.pred` table holds the
    page of its picture (open question 5). A cell of a roster draws a picture only for an `ImageFile`
    (`RosterToGraphics.jl:138-145`), and G3 step 2 keeps that test. The assistant recommends that G3
    step 2 makes the cell draw the picture of a page too, through `find_page_file`. Must G3 or G5 do
    it?
