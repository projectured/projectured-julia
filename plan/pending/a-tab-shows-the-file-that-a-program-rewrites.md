# A tab shows the file that a program rewrites

> **Kind:** design · **Status:** a plan, 2026-11-05, revised at `main` `6b93bfcf3`, and revised
> again on 2026-11-06 after the owner's decision D10: the file document watches its file and keeps
> the hash and the band, and the page goes away. Steps 1 and 1a are built on the branch
> `file-rewrites`; step 1b changes the view of step 1a into the view of a file. Steps 6 and 7, D1,
> §6 and open question 9 are revised on 2026-11-15 at `main` `11585943d` to the one file document
> of a path: a tab, a card, the explorer and a load all hold the editor's one document of a path
> (steps 5 and 6 of the plan of the save, G3), and the owner said "Yes" to the revision. · **Sibling plan:** G3
> [the-assistant-shows-a-picture-file.md](../done/the-assistant-shows-a-picture-file.md) · **Stands on:**
> [a-window-watches-its-open-files.md](../done/a-window-watches-its-open-files.md),
> [filechange.md](../../documentation/package/platform/filechange/filechange.md),
> [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md),
> [explorer.md](../../documentation/package/platform/explorer/explorer.md),
> [the-assistant-finds-its-names-by-reflection.md](../done/the-assistant-finds-its-names-by-reflection.md)

This plan closes gap G4 of the parent plan, inet-cpp
`plan/pending/ieee80211-chart-baseline-evolution.md` §9.3. A tab and a card of a dashboard show a
Markdown page and its pictures while a script rewrites them. The owner decided on 2026-11-05 to
close G4 before step 1 of the parent plan, in a plan of its own.

## 1. The goal

1. The assistant opens a file in a tab with `open_file!`, and puts the same file in a card of a
   dashboard. A tab pane alone shows and edits the file: no explorer is needed, and the explorer
   has no code of its own for a file (the owner, 2026-11-06).
2. A script rewrites the page and its PNG pictures many times, for about 5 hours.
3. After each rewrite, the tab and the card show the new text and the new pictures. No band shows,
   because the person made no edit.
4. Each view keeps its own scroll place, and the selection of the person stays where it can. The
   load adds no step to an undo history.
5. A picture path in the page resolves against the folder of the page.
6. When the person edited the page, the band "changed on disk" shows, as it does now.
7. A picture that is not on the screen is never read, and no print reads the disk.

## 2. What exists (checked at `6b93bfcf3`)

| Fact | Where |
| --- | --- |
| `make_file_tab_content(path)` with no `wrap` gives a page whose file keeps no history, and `has_unsaved_edits` answers `nothing` for its content (measured 2026-11-05). | `source/platform/fileformat/DocumentFile.jl:199-202`, `:281-283` |
| A page loads a change for a file that a person does not edit, or for a content whose history answers `false`. Else it shows the band. A test holds the band for a page with no history. | `source/platform/fileformat/FilePage.jl:324-335`; `test/platform/filechange/FileChangeStoreTest.jl:216-226` |
| A page of a file that a person does not edit keeps no hash after its make. A load from a report keeps the hash of the time and the size that the watcher reports. F5 hashes the whole text of the file. | `FilePage.jl:111-117`, `:204-213` |
| The open of a file gives the content a history only when the editor has settings. `OpenFileOperation` focuses the new tab, or the tab of a file that is open. A file in the Files tree of the explorer makes its page with the same rule. | `source/platform/filesystem/FileSystemDocument.jl:201-227`, `:81-86` |
| `open_file!` is on main. It makes the content as `OpenFileOperation` does, with the same rule for the history, does not focus, and answers the tab. For a file that a tab shows, it answers that tab. It finds the tab by `tab.content === page`. | `FileSystemDocument.jl:229-272` |
| The window of the application gives each file tab of its start a history: `make_application_document` passes `make_history_wrap(settings)`, and `settings` is `make_settings()` by default. | `source/platform/application/Application.jl:113-123` |
| A name reaches the assistant when the docstring of its generic function or of its type ends with the line `For the assistant.`. `make_editor_api` collects the marked names, and no list keeps them by hand. `open_file!`, `find_open_file_document`, `make_file_tab`, `make_file_tab_content`, `save_file_to_disk!`, `reload_file_from_disk!`, `insert_elements!`, `Dashboard`, `DashboardCard` and `find_explorer_content` carry the mark and are offered. `FilePage`, `make_file_page`, `make_document_view` and `OpenFileOperation` are not offered. | `Application.jl:361-362`; `source/kernel/tool/AssistantMark.jl:48-63`; the marks at `FileSystemDocument.jl:248`, `source/platform/fileformat/OpenFileList.jl:107`, `DocumentFile.jl:163`, `:197`, `FilePage.jl:242`, `:273`; measured with `make_editor_api()` in a process that loads `ProjecturedPlatform`, 2026-11-05 |
| The window text on main names `open_file!` and no builder. Step 6 of the reflection plan rewrote the texts and is on main (`0836ec536`, `97dee7cef`). | `Application.jl:406-407`; `documentation/guide/orientation.md:242-247` |
| `test_assistant_documentation` fails for a marked docstring whose example or "See also" line names a name that is not offered, and for a system text that names such a name. Two marked docstrings name the two builders: the example and the "See also" line of `get_file_content`, and the "See also" line of `Workspace`. | `test/projectured/editor/AssistantVerbsTest.jl:422-459`, `:469-474`; `source/platform/serialization/FileProject.jl:110-115`; `source/platform/filesystem/Workspace.jl:108` |
| A load puts the new document inside the file, and the history of the file forgets its steps. The scroll pane is outside the file. The drain gives the change to the page, and the page evaluates the load directly, so no history above the page records it. | `DocumentFile.jl:449-456`; `source/platform/undo/UndoDocument.jl:114-122`; `source/platform/filechange/FileChangeStore.jl:531-536`; `FilePage.jl:327-330` |
| A load writes no selection. A selection that names no part can make a printer fail at each frame, and the editor repairs it only after a failed operation. | `filechange.md`, "Limits"; `source/kernel/editor/FaultBarriers.jl:220-238` |
| `Dashboard` and `DashboardCard` have no `acquire_document!`. The content of a card is not acquired, so a page in a card does not watch its file. `insert_elements!` finds its operation through the readers of the editor. | `source/platform/explorer/Dashboard.jl:22-64`; `source/kernel/editor/DocumentEdits.jl:185-190`, `:226-229` |
| The explorer content file writes a page in a card whole: the file with a copy of its text, the scroll pane with its place, and the hash of the page (measured 2026-11-05 with `print_pred_text` of a section with such a card). | `source/platform/explorer/ExplorerContentFile.jl:60-70` |
| A watch hashes the file on the task of the acquire, and starts from the file as it is then. A page that is released and acquired again does not get a change that came between. | `FileChangeStore.jl:44-49`, `:138-152`, `:295-302` |
| The navigator makes the view of its page at each visit and at its acquire, and keeps it in a slot that a walk does not enter. A visit of the Back list keeps its view, and the view holds the page. The default `make_document_view` answers the document itself, and `FilePage` has no method. | `source/platform/navigator/NavigatorVisits.jl:234-266`; `source/platform/navigator/NavigatorDocument.jl:12-16`, `:128-136`; `source/platform/domain/DocumentView.jl:30-32` |
| A file in the Files tree takes the page that the editor holds open for its path, else its kept page, else a new page. Its release keeps a page with an edit or with a dormant selection, so the Back list can show that page again. | `FileSystemDocument.jl:50-79` |
| The image of a Markdown page calls `isfile(url)` in the printer and `decode_image(path)` in a cell computation, both on the loop. A relative path resolves against the current folder of the process. | `source/domain/markdown/MarkdownToSyntax.jl:472-483` |
| A link resolves a relative path against the file of the page, at the press. The part after `#` is not followed. | `source/domain/markdown/MarkdownLinkTarget.jl:85-92`, `:105-112` |
| A Markdown page does not print back to its text. Of 9 small pages, each lost its last newline. An ordered list printed as bullets, two lines of one paragraph joined, and three blank lines became one. | `print_natural_text(parse_markdown(text))`, measured 2026-11-05 |
| A context property passes a value of a print to the children (`with_property`). Each stage of a `ChainingProjection` gets the same context. `FilePageToWidget` prints no child. | `source/kernel/projection/PrinterContext.jl:65-74`, `:398-408`; `source/platform/projection/higherorder/Chaining.jl:72-82`; `source/platform/fileformat/FilePageToWidget.jl:9` |
| A background cell computes a value off the loop, and its `apply` stores the answer by an operation. A folder reads its entries so, with the source of the folder that holds it, so one task reads every folder that one frame asks for. A change of the folder adds one to its read count. | `source/kernel/editor/BackgroundCells.jl:182-232`; `FileSystemDocument.jl:305-321`, `:556-560` |
| omnet-julia opens an INI file from a link as a file document with no page and no history. Its project page watches the file of its fingerprint store with the file as the receiver. | omnet-julia `source/ide/LegacyIniFileEntryToWidget.jl:150-156`; omnet-julia `source/legacy/simulator/presentation/LegacySimulationProjectPage.jl:583` |

Facts found on 2026-11-06 at the branch `file-rewrites` (`0c1a04a23`), for D10:

| Fact | Where |
| --- | --- |
| 17 types are file documents: 11 in projectured-julia (`TextFile`, `PredFile`, `SourceFile`, `JsonFile`, `MarkdownFile`, `JuliaFile`, `XmlFile`, `MathFile`, `YamlFile`, `SqlFile`, `RstFile`) and 6 in omnet-julia (`LegacyResultFile`, `LegacyFingerprintStoreFile`, `LegacyEventLogFile`, `LegacyTestFile`, `IniFile`, `NedFile`). Each has the fields `filename` and `content`, and the generic code reads both with `getfield`. 7 test types are file documents too. | `source/platform/serialization/FileProject.jl:64`, `:92`, `:122-123`; the inventory of 2026-11-06 |
| The page holds what the file document does not: the band, the hash of the last load or save, the conditions `:conflict` and `:changed_on_disk` of its decoration, the facets of the roster of open files, the save with the check of the disk, the load and the keep. Its reader turns `SaveFileOperation` into `SaveFilePageOperation` and `ReloadFileOperation` into `LoadFilePageOperation`. The open files of the editor list a page in place of its file. | `source/platform/fileformat/FilePage.jl`; `FilePageToWidget.jl:151-156`; `OpenFileList.jl:115-168` |
| In the default open the history sits inside the file document, around its content, so the file reads it with `has_unsaved_edits(get_file_content(file))`. An open from a link of a navigator (`file_wrap = Navigator`) puts the history around the navigator around the file, so the file has no history inside and every rewrite shows the band. The navigator writes its own changes as view state, so that history records only the edits of the file. | `source/platform/filesystem/FileSystemDocument.jl:244-250`; `source/platform/navigator/NavigatorAddressEdits.jl`, `NavigatorVisits.jl:253-257` |
| No file type in `source/` answers `true` to `is_own_content`. | `FileProject.jl:142`, `DocumentFile.jl:170` |
| omnet-julia reads a page in three places: `LegacyBaselineFileView.jl:60` and `LegacyResultFile.jl:237` unwrap an open page with `find_page_file`, and `IdeNavigatorTest.jl` finds the file of a tab with it. | omnet-julia `source/ide/`, `source/legacy/result/presentation/`, `test/ide/` |
| A holder changes what it holds only on the paths that add the change. The pane tree adds it when it opens or closes a tab. After `replace_referenced_value!(tab, :content, view_of_b)` the new file is not held and not watched, and the old one stays held and watched. After `replace_referenced_value!(card, :content, page)` a card gets no view and the dashboard does not hold the page. | `source/platform/pane/PaneSurgery.jl:567`, `:696`; two probes of 2026-11-06 at `0c1a04a23` |

## 3. What the code does not do yet

- The open of a file gives a history only when the editor has settings. A page with no history
  shows the band at each rewrite.
- The mark of `make_file_tab_content` still offers a builder that gives a page with no history. The
  window text on main names `open_file!` and not that builder.
- A card of a dashboard does not acquire its content. Thus a page in a card does not watch its
  file.
- A tab and a card that show one page share one scroll place, because the page holds the scroll
  pane.
- A page that comes back into the window shows the text of before, until the next rewrite.
- A load can leave the selection on a part that the new document does not have.
- A file document does not know its state against the disk. A page around it knows, so code that
  shows a file must make a page, and a file that no page holds is not watched (D10 changes this).
- A picture path of a page resolves against the current folder of the process. The printer reads
  the disk, and a computation decodes the picture on the loop. A rewrite of a picture does not
  reach a page whose text stays the same.

## 4. The design

**Only the history of a file answers whether the file has edits (D1).** The owner decided this on
2026-10-15 (D15e of the done plan) and again on 2026-11-05. Every open of a file by a person or by
the assistant gives the file a history: `OpenFileOperation`, `open_file!` and a file of the Files
tree. With no settings, the history keeps the default capacity of `UndoBuffer`, 100
steps. The history sits inside the file document, around its content, in every open, also in an
open from a link of a navigator, so the file reads its own history (D13). The window of the application gives its file tabs a history already. The assistant opens a
file as a person does, with `open_file!`. `make_file_tab` and `make_file_tab_content` lose the mark,
because they make a file or a page with no history, and no gesture of a person does that.

**The file document watches its file, and keeps the hash and the band (D10, D11).** The owner
decided this on 2026-11-06. A file document that is held watches its file and is the receiver of
the changes that the watch reports. It keeps its state against the disk in one field `disk` of type
`FileDiskState`, which every file type has, as it has `filename` and `content`: the hash of the
text at the last load or save and the band, and after step 2 the text cell of D4. The field is view
state, so a save writes none of it and a walk does not enter it. The file decides what a change
means, with the check of today: it loads when it has no edits, and it shows the band when it has.
`SaveFileOperation` checks the disk before it writes, `ReloadFileOperation` takes the hash of the
text that it loads, and `KeepFileEditsOperation` keeps the edits. The decoration and the facets of
the roster say that the file changed on disk. `FilePage` goes away, with its operations and its
reader, and the open files of the editor list file documents only.

**One file is one file document in the window, and each place shows its own view of it (D2, D12).**
The tab and the card show the same file document, as a tab and the navigator share it.
One watch, one hash and one band serve every view. `make_document_view(::FileDocument)` answers a
`FileView(file, scroll)`, which keeps the scroll place of one place and draws the band of the file
above the file in its scroll pane. A tab, a card, the navigator and a file of the Files tree all
make their view with `make_document_view`, so no place has code of its own for a file, and the
explorer has none. `make_file_tab_content` answers the view of a new file. The assistant gets the
file with `find_open_file_document(path)` after `open_file!`, and puts it in a card with
`insert_elements!`.

**A dashboard holds what its cards show (D3).** Each card keeps the view of its content in a slot
that a walk does not enter, as a navigator keeps the view of its page, so a path into a card goes
through its content. The acquire of a dashboard makes the view of a card that has none, and holds
the view of each card. The view holds the file. The reader of the
dashboard adds a `ChangeHeldDocumentsOperation` to each edit of `cards`, as the tree adds one to
the open of a node. The Insert key, a paste, `insert_elements!`,
`delete_elements!` and an undo must all pass that reader, and the test of step 1 checks each one. A
picture of G3 in a card follows its file in the same way. Step 1 found that an edit of a dashboard
in an explorer does not pass that reader, so the change of the hold is added at four places, and an
edit of the content of one card adds none (§2). A tab has the same gap. One rule for every holder
is deferred to a plan of its own after the plans of this session (open question 10), so G4 lands
with the four places and the gap (§8).

**The text of a file is a background cell (D4).** The cell is in the `disk` field of the file
document (D11), and below "page" means that file. A page reads its file as a folder reads its
entries and a picture reads its pixels (`BackgroundCells.jl`). The input of the cell is the path
and a count of changes. Each change that the watch reports adds one to the count, as for a folder
(`FileSystemDocument.jl:556-560`). A read of the cell never waits. When the page is drawn and the
answer of the cell is out of date, the cell records a demand, and after the frame a task reads and
parses the file. The `apply` of the cell stores the answer with the check of today: the hash of
the new text equals the hash of the page, and nothing changes; the page has no edits, and it
loads; the page has edits, and the band shows. The watch only reports that a file changed. It reads
no text and computes no hash, for any kind of file, so the watcher knows nothing of editing (the
rule of the owner of 2026-10-15). The editor watches what is shown: a Back list of the explorer and
the undo history keep pages that are not shown. A page that shows again sees a count that moved
while it was hidden, and it reads again, as a folder does (the model of the owner of 2026-10-16).
Only a page on the screen is read. A page that the save plan opens and that is not read yet (its
D6) is the same cell with no answer: it shows that it reads, and it refuses a save until the
answer comes.

Each held file document is watched (D10, which replaces D8). Each watched file is the editor's one
file document of its path, so the `apply` of the cell always has the file and its history. The
project page of omnet-julia holds the editor's one file document of its fingerprint store file.

**A load keeps the selection, or the deepest part of it that remains (D6).** After
`ReloadFileOperation` puts the new document in the file, a selection that names no part becomes
the longest start of its path that names a part.

**A file keeps the editor's one file document of each picture that it shows (D5, D10).**
`collect_shown_file_paths(document)` answers the paths that a document writes for the files that it
shows, such as the images of a Markdown page. It reads no disk, and the default answers none. The
file resolves each path against its own folder. It keeps the editor's one file document of each
path in the field `shown_files` of its `disk` state. `open_file_document!(path; editor)` of the
plan of the save answers that file: the file that the editor has open for the path, or else a new
file that a person does not edit, which reads nothing when it is made. So a picture that
a page and a tab show is one file document, with one watch. Each picture has a `BackgroundSource` of
its own (G3 D10). The file holds each
of these files, so each watches its file while the holder is held. A load that changes
the paths changes `shown_files` and what the file holds.

**A picture is read only where it is drawn on the screen.** The pixels of a picture are a background
cell (`BackgroundCells.jl`). Each picture has a `BackgroundSource` of its own (G3 D10). A
read of the cell never waits and starts no work: it answers the last pixels, or none, and records a
demand. After the frame, the background work reads each picture that the frame demanded on a task
of its own, so the pictures decode in parallel, and the answers come back to the editor task.

The drawing is lazy in the backend when it reads the graphics domain (the owner, 2026-11-05), so
the cell of a picture is read only when the picture is on the screen. A picture that is never on
the screen is never read. A picture on the screen shows a box with its path in its first frame and
its pixels in the next. When a program rewrites a picture, the watch reports a new time and size,
the input of its cell changes, and only a picture on the screen is read again.

**The image of a page draws the picture that its file keeps.** The view of the file prints the file
as its own child, with the context property `:shown_files`. The image printer takes the picture of
its path from that property and puts the cell of its pixels into the graphics. It reads no disk.

**A dashboard with a file in a card saves through the plan of the save of a file alone (D7).** That
plan makes a file saved alone write `file("…")` for each opened file that it holds, with no throw.
Another agent writes it as a plan of its own on 2026-11-05. G4 does not change the save. Until that
plan lands, the explorer content file writes a file in a card whole, with a copy of its text (§2).
The view of a file answers `find_held_file` with its file, and the `disk` state is view state, so
the save of that plan writes `file("…")` and no band and no hash.

## 5. Decisions

A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. What says that a page has edits.** A, decided by the owner on 2026-11-05: only the history,
  as D15e says. Each file document that the editor makes has a history, with the default capacity
  when the editor has no settings. The editor makes one document of each path, for the first place
  that asks for it, so this holds for a tab, a card, the explorer and a load alike.
  `make_file_tab` and `make_file_tab_content` lose their mark, because no gesture of a person
  makes a file document with no history, or a second document of a path. B, rejected: the hash of a print against the hash of the last
  load. The owner said on 2026-11-03 that a save prints the tree with no print comparisons, and a
  Markdown page prints another text (§2). C, rejected: the page counts the operations that pass its
  reader. That copies the history, and an undo back to the saved step still counts as an edit.
- **D2. A tab and a card of one file.** A, decided by the owner on 2026-11-05: one page, and each
  place that shows it shows its own view of it. `make_document_view(::FilePage)` makes a view
  document that keeps the scroll place, and the scroll pane moves from the page into the view. The
  page keeps the file, the hash and the band once. Rejected: one page with one scroll place in
  both views, so that a scroll in the tab moves the card. B, rejected: a page for each view over
  one file document. The store has one receiver for each file,
  and two pages keep two hashes of one fact. C, rejected: a file document for each view. An edit in
  one view does not reach the other, and a save of one writes over the other. D10 keeps the choice
  and drops the page: one file document, and each place shows its own view of it (D12).
- **D3. How a dashboard holds its cards.** A, proposed by the assistant: the acquire and the reader
  of the dashboard, as above. Each card keeps the view of its content as a navigator keeps the view
  of its page (`NavigatorDocument.jl:12-16`, `:128-136`). B, rejected: each gesture and each verb
  adds the change of what is held. `insert_elements!` is generic and has no reference to a
  dashboard.
- **D4. A page reads its text through a background cell.** Decided by the owner on 2026-11-05 in two
  answers. First (option B of that question): a page that shows again must see a change that it
  missed, and the editor watches only what is shown. Then (option A of the next question): the
  text of a page is a background cell, as a folder, a picture and a git read are, so all outside
  reads use one mechanism, only what is on the screen is read, and the watcher reads nothing.
  Rejected: the first read of a watch that reports to its receiver, which reads each page that a
  view holds, also a card below the screen, and makes the watcher read text. Rejected: the watch
  starts from the hash of the receiver, which puts the hash of the last load or save into the
  watcher, against the rule of the owner of 2026-10-15. Rejected: the page reads its file at its
  acquire, a second read beside the watcher. Rejected: a watch of every page that the document
  holds, also in a Back list or in the undo history, so that the count of watches grows with no
  limit.
- **D8. No bare file is watched.** Replaced by D10 on 2026-11-06: each held file document is
  watched, and no page exists. The text below is the decision of 2026-11-05.
  Decided by the owner on 2026-11-05 (open question 7, option A).
  Each watched file is the editor's one page of that file: a holder finds the opened page
  (`find_open_file_document`) or opens a new one, and holds it. The holders of a document are
  counted (`add_document_holder!`), so the watch of a file stops at the release of its last holder.
  The case on main is the fingerprint store of the simulation project page of omnet-julia
  (`LegacySimulationProjectPage.jl:577-586`): the project page holds the page of the store file and
  shares it with a tab of the store. omnet-julia changes in the same landing as step 2. Rejected: a
  bare file whose `apply` loads a file type that a person does not edit and logs a warning for any
  other type.
- **D5. Where the pictures of a page live.** Decided by the owner on 2026-11-05: the page keeps an
  unread picture for each image, and the pixels of a picture are a background cell that only a
  draw on the screen demands, as above. The owner's reason: a picture that is not on the screen
  must not be read, and the printer must not read the file. Rejected: the page reads every picture
  of its file off the loop when it opens. A page of 60 pictures then reads 60 files, also the
  pictures that are not on the screen. B, rejected: the printer reads the disk, as now. A printer must read no disk. C, rejected:
  the Markdown tree holds them. The tree represents its file, and a decoded picture is not text of
  the file. D, rejected: a picture store of the editor that the printer reads. A printer has no
  reference to the editor.
- **D6. The selection after a load.** A, proposed by the assistant: keep it, or the deepest part
  that remains. B, rejected: select the whole file, as F5 does. Then each rewrite moves the place of
  the person.
- **D7. The save of a page in a card.** Decided by the owner on 2026-11-05 in G3 (its D1, option
  A): a file saved alone writes `file("…")` for each opened file that it holds, with the path
  relative to its own folder, and does not write that file. It is a plan of its own. G4 does not
  implement it, and no step of G4 saves a dashboard.
- **D9. A dashboard prints only the cards on the screen, in every place.** Decided by the owner on
  2026-11-05 (the layout plan, its open question 2, option A). The dashboard reads
  `get_visible_height` (layout-rules §3c) in place of `get_exact_height`, so its rows are always a
  list. In a scroll area that grows, the dashboard takes the height of the view and scrolls by
  itself, as a `WidgetTable` whose rows are a list does. Rejected: a grid of a vector in a place
  with no height. Its print reads the text of the page of each card, also below the screen.
- **D10. The file document watches its file, and the page goes away.** Decided by the owner on
  2026-11-06 ("Yes"), after the owner asked why the file document does not watch its file. The page
  came from D15b of the done plan (2026-10-15) for two reasons: the band had to stay above a file
  that scrolls, and the scroll pane was then around the file in the tab; and one layer served
  every file type with no change to any. Step 1a moved the scroll pane into the view, so the view
  draws the band above its scroll pane for any file, and the first reason is gone. The second is an
  amount of code, which is no reason (the owner, 2026-11-04). So the file document watches its
  file, keeps the hash and the band, and decides what a change means; each held file document is
  watched (in place of D8). Rejected: the page as today, a layer that every place must make around
  a file, so code that shows a file must know of it, and a file that no page holds is not watched.
- **D11. Where a file keeps its state against the disk.** Proposed by the assistant: one field
  `disk::FileDiskState` in every file type, read by `get_file_disk_state(file)`, as `filename` and
  `content` are read by every file type. `FileDiskState` is a document with `file_hash` and `band`
  in step 1b; step 2 adds the stamp, the counts and the text cell, and step 4 adds `shown_files`.
  The field is view state for every file document (`get_view_state_fields`), so a save writes none
  of it and a walk does not enter it. Rejected: the fields themselves in every type, which repeats
  five or more fields in 17 types and their tests. Rejected: one concrete file type with the kind
  of file as a value, because each kind of file is a document type with its own fields and methods,
  such as `SourceFile.server_text` and `LegacyResultFile.tables`.
- **D12. The view of a file.** Proposed by the assistant: `FileView(file, scroll)` in
  `source/platform/fileformat/FileView.jl`, the view of step 1a with the file in place of the page.
  `make_document_view(::FileDocument)` answers it, `make_file_view(file)` makes one that follows the
  selection of the file, and `FileViewToWidget` draws the band of the file above the scroll pane. The
  view holds its file and answers `find_held_file` with it. A tab, a card, the navigator and a file
  of the Files tree make the view with `make_document_view`, and the finder of the tab of an open
  file follows the edited fields of the content of a tab to the file, with no test of a type.
- **D13. Where the history of a file sits.** Proposed by the assistant: inside the file document,
  around its content, in every open. An open from a link of a navigator makes
  `Navigator(file)`, and the file has the history inside, so the file reads it and each file that
  the navigator visits has a history of its own. The history around the navigator records only the
  edits of the file today (§2), so nothing that it records is lost. Rejected: the history around
  the navigator, as today, where the file can not read it, so every rewrite of such a file shows the
  band.
- **D14. A picture is held by the image that shows it, as by a tab.** Decided by the owner on
  2026-11-08: "The explorer and the pages are not special in any way. An image file could just as
  well shown in a tab pane. Then it should watch the file. A picture file should be watched only
  once and read once." Then "Yes" to the model: the image in a page holds the file document of its
  picture in the same way as a tab holds the file document that it shows, and the page keeps no
  table of its pictures. The editor keeps one file document for each file, so a picture that a tab
  and a page show has one watch and one read. An edit that adds an image holds its picture, and an
  edit that removes it releases it, with no code for pictures in a load or in an edit. This
  replaces the part of D5 by which the page keeps a picture for each image (the pixels as a
  background cell that only a draw demands stay). Consequences:
  - Step 4 as built (the table `shown_files` of the page, filled at a load, and its hold in
    `acquire_document!(::FileDocument)`) follows the replaced model, so it does not stay.
  - A hold that follows an edit needs the general hold rule of the lifecycle of a document (Q10).
    The owner on 2026-11-15: "Do step 5 and 5a, question 10 can wait". So steps 5 and 5a come
    before the plan of Q10, and a page holds its pictures at its open and at each load only.

## 6. How the names reach the assistant, and the order of the plans

G4 adds no name for the assistant. A tab uses `open_file!`, and a card uses
`open_file_document!`, `insert_elements!`, `DashboardCard` and `find_explorer_content`. Each of
these carries the mark on main.

- **The rule.** Steps 1 to 4 of the reflection plan landed on main at `2bbc18fb5` on 2026-11-05. A
  name reaches the assistant when the docstring of its generic function or of its type ends with
  the line `For the assistant.`. No list keeps the names by hand. G4 uses only the mark, and it adds
  no name to `make_editor_api`.
- **What G4 changes.** Step 1a changes the marked docstring of `make_file_tab_content`, because the
  function answers a view. Step 6 removes the mark from `make_file_tab` and
  `make_file_tab_content`. It changes the marked docstrings that name them, `get_file_content` and
  `Workspace`, so that their example and their "See also" line name only offered names. It changes
  the marked docstrings of `open_file!` and `open_file_document!`: each place that holds the file
  follows a rewrite while the file has no edits. Step 1b
  changes the marked docstring of `make_file_tab_content` again, because it answers the view of a
  file, and of `find_open_file_document`, which answers a file document and never a page.
  `FileView`, `FileDiskState` and `collect_shown_file_paths` carry no mark.
- **Order.** The owner decided the order on 2026-11-05: steps 1 to 4 of `reflection-api` land on
  main first, after a rebase, its tests and the approval of the owner. They landed at `2bbc18fb5`
  (omnet-julia `991a89b4f`), and `origin/main` holds them. G4 starts from main. Steps 5 to 7 of the
  reflection plan are on main too (`0836ec536` to `40fca6884`). Step 6 rewrote the window texts,
  which name `open_file!` and not the two builders, so G4 changes no window text. On main the text
  names no builder (`Application.jl:406-407`), and `test_assistant_documentation` fails when the
  text names a name with no mark. Thus G4 step 6 has the texts it needs. Open question 8 asks the
  owner. G4 step 6 does not change `Application.jl`.
- **Where G4 meets G3.** G3 owns the picture document. The owner decided on 2026-11-05 that a
  picture is a file document that a person does not edit (G3 D1, model B). G4 needs six properties
  of it:
  1. The file type of a `.png` path is registered, so `make_file_tab`, an open of the file and a
     page make the picture. Nothing reads the file when the picture is made.
  2. The pixels are a background cell. A read of the cell records a demand, and the decode runs in
     the background work after the frame, never in a print, a computation or the watcher.
  3. `is_editable_file_type` answers `false`. A person never edits the picture. The watch only
     reports a change, as for every file kind (D4, G3 D12).
  4. A change that the watch reports adds one to the count of changes of the picture, which is the
     input of its pixel cell, so the next draw on the screen reads the picture again. A picture that
     is not on the screen reads nothing.
  5. Each picture has a `BackgroundSource` of its own (G3 D10, decided by the owner). A picture
     page that a tab and a Markdown page share belongs to neither, and the pictures of a frame
     decode in parallel.
  6. The rendered Markdown draws the cell of its pixels in a `TextGraphics`.

  G4 needs nothing of the view of a picture in a tab: the fit, the zoom and Ctrl+1 for the natural
  size belong to G3. G3 lands before step 5. Steps 1 to 4 use a test file type and need no G3.
  Step 1 also makes a picture of G3 in a card follow its file.

## 7. Steps

Each step is one commit with its test. `SEALING.md` lists only files under `source/kernel/`
(checked at `6b93bfcf3`), and no step changes a file there, so no step changes a sealed file.
`workspace/bin/bounded-run` runs each test: a test under `test/platform/` in
`package/ProjecturedPlatformTest`, any other in `environment/all`.

The dependencies: step 1a needs step 1, and step 1b needs step 1a. Step 2 needs step 1b. Step 4
needs step 5 of the save plan, which adds `open_file_document!` (its `open_file_page!` before D10).
Step 5 needs G3 on main. Step 6 needs step 6 of the reflection plan, which is on
main since `0836ec536`. A saved dashboard with a page in a card needs the save plan (D7), and no
step saves one.

**Order:** step 5 of the save plan needs step 2 of this plan on main, and step 4 of this plan needs
step 5 of the save plan. The owner decided the order on 2026-11-06 ("Yes"): steps 1 to 3 of this
plan land, then step 5 of the save plan, then step 4 of this plan. Step 6 of the save plan keeps
its place after the plan of the layouts. Steps 1a and 1b belong to the steps that land first.

- [x] **1. A dashboard holds the content of its cards (D3).** **Done on 2026-11-06.** `acquire_document!` and
      `release_document!` of `Dashboard`, and a `read_intent` of `DashboardToWidget` that adds the
      change of what is held (`source/platform/explorer/Dashboard.jl`, `DashboardToWidget.jl`).
      The print of the dashboard reads `get_visible_height` and always makes the grid of a list
      (D9). Update `explorer.md`. Test: `test_explorer()` in `test/platform/explorer/ExplorerTest.jl`, a
      new set with an editor and a `FileChangeStore`. The content of a card is held after the
      acquire, after Insert, after a paste and after `insert_elements!`, and a page in a card
      watches its file. The hold stops after `delete_elements!` and after the undo of the insert.
      A dashboard of 60 cards in a scroll area that grows prints only the cards on the screen.
      Then `test_dashboard_render()`.
      What the implementation found:
      - A card keeps the view of its content in a new field `content_view` of `DashboardCard`, a
        `NavigatorViewSlot` of the navigator slice (the slice already uses it). The field is view
        state (`get_view_state_fields`), so a save leaves it out and a walk does not enter it. The
        helpers `_get_card_view` and `_make_card_view_slot` repeat the shape of the private helpers
        of `NavigatorVisits.jl`, which another module cannot call.
      - The reader of `DashboardToWidget` alone does not see the edits. `insert_elements!` and
        `delete_elements!` reach the dashboard of the explorer by the path of its node in the tree,
        `tree.root.entries[k].cards`, and that route goes through the tree and never through the
        page; Insert and a paste on the row of the tree do not pass the page either (Insert on the
        row opens the menu of the kinds). So one function, `_add_card_holds(root, operation)`,
        adds the change of what is held, at four places: the answer to Insert and the answer to a
        paste, which are built in `Dashboard.jl`; the reader of `ExplorerToWidget`, for an edit that
        a verb routes through the tree; and the reader of `DashboardToWidget`, for an edit that a
        verb routes to `cards` of a dashboard outside an explorer. A dashboard whose hold an
        answer changes already is left alone, so a paste at the caret on the page adds one change.
        The slot that a new card needs is view state, and the change of the hold is recorded, so
        an undo of the insert releases the view and a redo acquires it.
      - The grid is a list in every place. `_make_card_steps` and `_find_card_below` lost the
        argument `rows_are_list`, and `_get_grid_shape` became `_get_grid_columns`. The print
        reads `get_visible_height` and gives it to the pane as the `max_height` of its constraint.
        The growing-area case of `test_dashboard_render()` builds the rows that show with or
        without that bound, because the list form is what limits the rows; the bound is asserted
        by `max_height` in `ExplorerTest.jl`.
      - In an editor with no window size a press in a card reaches no card, because the page has
        no height. The first set of the dashboard in `ExplorerTest.jl` now runs its press and its
        Insert in an editor with a window (`_explorer_window_editor`); `_nav_texts` reads the
        first window of a screen.
      - The explorer suite passes with the new sets (330 Pass), `test_filechange()` passes (126
        Pass), and `test_dashboard_render()` passes (4 Pass).
- [x] **1a. Each place that shows a page shows its own view of it (D2).** **Done on 2026-11-06.** A method of
      `make_document_view` for `FilePage` and its view document in `source/platform/fileformat/`.
      The scroll pane leaves the page, `make_file_page` takes the file, and `make_file_tab_content`
      answers the view of a new page. `open_file!` and `OpenFileOperation` show a view in a tab,
      and find the tab of an open file through its view (`FileSystemDocument.jl:201-288`). A card
      keeps the view of its content in a slot, and the dashboard holds the view. The view type gets
      the method of `find_held_file` of the save plan, so a save of the tabs (`save_user_interface`)
      writes `file("…")` for the view and not the view whole (decided by the assistant on 2026-11-05,
      save plan Q8: the owner of a type adds its method). Update
      `fileformat.md`, `filesystem.md` and `explorer.md`. Also `test_user_interface_file()`. Test: `test_filechange()`, a new set
      with an editor. A tab and a card show one page. A scroll in the tab leaves the card where it
      is. A rewrite reloads the page once, and both views show the new text. The band shows in
      both views after an edit. Then `test_file_tab()`, `test_explorer()`,
      `test_file_watch_window()`, `test_assistant_documentation()` and
      `test_referenced_document_editor()`, because the marked docstring of `make_file_tab_content`
      changes.
      What the implementation found:
      - The view type is `FilePageView(page, scroll)`, in `FilePageView.jl`, with the constructor
        `make_file_page_view(page)`; both are exported, because `filesystem` and the tests make
        a view too. `FilePageToWidget` draws the view: the band of the page above `view.scroll`,
        and `scroll.content` is the file, which `page.content` holds too. A walk does not enter
        `scroll` (`is_field_walked`), so the file has one path, `page.content…`. The view answers
        the title and the decoration of its page, holds its page (`acquire_document!`), and
        answers `find_held_file` with the file of its page. A `FilePage` has no projection of
        its own: a page shows only through a view.
      - `make_file_page(content)` takes the file, or what an opener put around it. `make_file_tab_content`
        answers `make_file_page_view(make_file_page(make_file_tab(path, wrap)))`.
        `_make_opened_file_page` in `FileSystemDocument.jl` is the one place that makes the page of
        an open (with the history of the settings), and `_read_file_page` of a file in the Files
        tree calls it.
      - `open_file!` and `OpenFileOperation` give a tab the view of the page, a new view each time,
        also for a page that an explorer or a card holds; they find the tab of an open file through
        its view (`_is_document_in_tab`).
      - The plan did not name the page of a file in the Files tree. The navigator of an explorer
        shows the `FileSystemFile` of a file, and that file draws its page, so a bare page would
        draw with no scroll pane. `FileSystemFile` gets a view-state field `document_view`, set
        by its acquire as a card sets its slot, and draws that view. It holds the view directly:
        the filesystem slice has no navigator slot to put it in, and a walk skips the field.
      - The page reader of step 1 compared the route of the change with a tuple and the route
        is a vector, so its branch (a verb that routes to `cards` of a dashboard outside an explorer)
        never ran. It is fixed here, and the new set runs it: the dashboard is the tab of the
        editor, and `insert_elements!` holds the view of the page in the card.
      - A duplicate of a tab shares the view of the tab. No step asks for a view of its own for a
        duplicate, so none is made.
      - Tests that took a tab content for a page now take its view (`.page`, `.scroll`):
        `FileTabTest`, `ReferencedDocumentEditorTest`, `ApplicationTest`, `WorkflowListTest`,
        `SourceFileTest`, `ExplorerTest`; `_app_focus_first_file!` selects the file through `page`.
        The sets of `test_filechange()` build their page with `make_file_page`.
      - The new set of `test_filechange()` opens a file with `open_file!`, puts its page in a card
        with `insert_elements!`, and asserts: one watch, a scroll pane for each place over one file,
        a scroll in the tab leaves the card at its place, a second open finds the tab, a rewrite
        loads the page once, and after an edit the next rewrite shows the band in both views.
      - Results: `test_filechange()` 142 Pass, `test_explorer()` 333 Pass, `test_file_tab()` 33,
        `test_file_watch_window()` 16, `test_user_interface_file()` 22, `test_assistant_documentation()`
        27 + 196 + 2828, `test_referenced_document_editor()` 134, all Pass. The tests that this step edited pass too:
        `test_document_decoration()` 57, `test_text_file()` 40, `test_roster_facets()` 30,
        `test_workflow_list()` 27 and `test_source_file()` 51. `test_scroll_work()` fails
        2 of 16 (copies and drawn share of a Julia file in a tab) and fails the same way at the
        commit of step 1. `test_application()` has 1 failure at `ApplicationTest.jl:1008` (the
        usage text of an agent bar), which no file code touches.
- [x] **1b. The file document watches its file, and the page goes away (D10 to D13).** **Done on 2026-11-07.** One commit
      in each repository, which land together, because omnet-julia does not load with a file type
      that has no `disk` field. Before it starts, the uncommitted work of the first try of steps 2
      and 3 on the page (2026-11-06, in both worktrees) goes into a named stash, `g4-step2-on-page`,
      so the step starts from `0c1a04a23`; step 2 takes what it can from that stash.
      - `FileDiskState` (`file_hash`, `band`) and `get_file_disk_state` in
        `source/platform/serialization/FileProject.jl`, the field `disk` in each of the 17 file
        types and the 7 test types, and `get_view_state_fields(::Type{<:FileDocument}) = (:disk,)`.
        Check that two new files get two states, not one shared default.
      - From `FilePage.jl` to the file document: the decoration with `:conflict` and
        `:changed_on_disk`, the facets, the band and its choices, `receive_file_change!(editor,
        file::FileDocument, file_hash, content)` with the check of today, the check of the disk in
        `SaveFileOperation` (with `force`), the hash in `ReloadFileOperation`, and
        `KeepFileEditsOperation`. The hash of a file that a person edits is set where its file is
        read, as `make_file_page` sets it today. `FilePage`, `FileBand` in its old place,
        `make_file_page`, `find_page_file`, `SaveFilePageOperation`, `LoadFilePageOperation`,
        `KeepFilePageEditsOperation` and the reader that turns the save and the load go away.
      - `FilePageView.jl` and `FilePageToWidget.jl` become `FileView.jl` and `FileViewToWidget.jl`
        (D12). `make_document_view(::FileDocument)`, `make_file_view`, and `make_file_tab_content`
        answers `make_file_view(make_file_tab(path, wrap))`.
      - The watch: the acquire of a file document watches its file with the file as the receiver,
        and holds nothing (`FileChangeStore.jl`). The open files list file documents only
        (`OpenFileList.jl`).
      - The open (D13): `_make_opened_file` in `FileSystemDocument.jl` puts the history inside the
        file also for `file_wrap`; `OpenFileOperation` and `open_file!` show `make_file_view(file)`,
        or the wrap of the file, whose own view shows it; the finder of the tab of a file follows the
        edited fields of the content of a tab. `FileSystemFile` holds `make_document_view` of its
        file. The save as of `FileDialog.jl` and `WorkflowList.jl:125` take the file.
      - omnet-julia: the field `disk` in its 6 file types; `LegacyBaselineFileView.jl:60` and
        `LegacyResultFile.jl:237` take the open file as it is; `IdeNavigatorTest.jl` finds the file
        of a tab through its view. The project page keeps its watch of the store file as on main.
      - The example `make_file_page_document_example` becomes an example of a view of a file, and
        its row in `PlatformExamples.jl` follows.
      - Update `fileformat.md`, `filechange.md`, `filesystem.md`, `explorer.md`, `roster.md` and
        `architecture-rules.md`, and the docstrings that name the page.
      Tests: `test_filechange()`, `test_file_tab()`, `test_file_watch_window()`,
      `test_user_interface_file()`, `test_explorer()`, `test_roster_facets()`,
      `test_document_decoration()`, `test_text_file()`, `test_workflow_list()`, `test_source_file()`,
      `test_open_page_operation()` (the navigator open of a file), `test_referenced_document_editor()`,
      `test_assistant_documentation()` and `test_application()`, against the counts of `19e56d912`
      (`test_application()` 399/1/2, `test_scroll_work()` 14/2). In omnet-julia, through the scratch
      environment of the two worktrees: `test_ide_file_navigator()`, `test_project_page()`,
      `test_fingerprint_store_document()`, and a load of every package. A new set of
      `test_filechange()`: a tab pane with no explorer opens a file, a program rewrites it and the
      tab shows the new text, the person types a letter and the next rewrite shows the band, and the
      file document is the receiver of the watch (`===`).
      What the implementation found:
      - `FileDiskState` (`file_hash`, `band`), `FileBand` and `get_file_disk_state` sit in
        `FileProject.jl` of the serialization slice, because the file types of the domains
        declare the field and the fileformat slice depends on serialization. The operations
        that a choice of the band answers stay in `DocumentFile.jl`. The field is
        `disk::FileDiskState = FileDiskState()` as the last field of each file type; the
        default is evaluated for each construction, so two new files get two states
        (tested). `get_view_state_fields` and `is_field_walked` of `FileDocument` name `disk`.
      - `SaveFileOperation` has the field `force` and the check of the disk; `ReloadFileOperation`
        has the field `file_hash` (the hash of the file on disk now when none is given) and takes
        the band away; `KeepFileEditsOperation(file, file_hash)` is new. A save and a keep answer
        `DoNothingOperation` as their inverse, so a history inside the file records no step.
        F5 needs no reader: `ReloadFileOperation` keeps the hash itself.
      - `make_file_tab` records the hash of an editable file where it reads it. A file made some
        other way has no hash, so its first report loads (history says no edits) or shows the band.
        A file with no history (or a bare file in an editor) now shows the band; before, a file
        with no page logged a warning and kept what it held.
      - `FileView(file, scroll)` replaces `FilePageView`; its paths are `file.<rest>`, the file being
        the content of the scroll pane. `find_page_file` becomes `_find_shown_file`, private, and
        the verbs `save_file_to_disk!` and `reload_file_from_disk!` take a tab or a file.
      - The open puts the history inside the file also for `file_wrap`; a tab with a `file_wrap`
        shows the wrap (a navigator), whose page view is the `FileView` of the file. The tab finder
        walks the edited fields of the content to the file.
      - The open files list holds file documents only. The save as takes the file and answers
        `SaveFileOperation(file; force = true)`.
      - The example `make_file_view_document_example` has the row "view" in `PlatformExamples.jl`.
      - A save of a file that is gone from the disk shows the band (its hash differs from the hash
        of nothing), as the save of a page did; `IdeNavigatorTest.jl` forces that save.
        `make_file_tab_content` with a `wrap` for a file that is its own content (no such type in
        `source/`) answers the wrapped part with no view, because no content inside the file holds
        the history.
      - `OpenFileListToWidget.jl` had borrowed a step constant of the page view; it has its own now.
      - Results (projectured-julia): `test_filechange()` 160 Pass, `test_explorer()` 333,
        `test_file_tab()` 31, `test_file_watch_window()` 16, `test_user_interface_file()` 22,
        `test_roster_facets()` 26, `test_document_decoration()` 57, `test_text_file()` 40,
        `test_workflow_list()` 27, `test_source_file()` 51, `test_open_page_operation()` 95,
        `test_referenced_document_editor()` 134, `test_assistant_documentation()` 27 + 196 + 2828,
        all Pass. `test_application()` 399 Pass, 1 Fail (`ApplicationTest.jl:1008`), 2 Broken and
        `test_scroll_work()` 14 Pass, 2 Fail (`:127`, `:130`) are the counts of the base.
      - Results (omnet-julia, scratch environment of the two worktrees): `test_project_page()` 100,
        `test_fingerprint_store_document()` 27, `test_ide_file_navigator()` 50 Pass, 2 Fail at
        `IdeNavigatorTest.jl:50` and `:57` (the Julia and Markdown tabs, which fail on main too).
      - The recorded lists under `package/*/precompile/` still name `FilePage`; every package loads
        and warns that its recorded calls no longer resolve until they are recorded again.
      - omnet-julia: the `disk` field in its 6 file types; `LegacyResultFile.jl` and
        `LegacyBaselineFileView.jl` use `find_open_file_document` as it is; `IdeNavigatorTest.jl`
        reads `content.file` of a tab.
- [x] **2. The text of a file is a background cell (D4).** **Done on 2026-11-07.** The `disk` state of the file gets the
      cell, its `BackgroundSource`, and an `apply` that loads with the check of today
      (`receive_file_change!`). The watch in `FileChangeStore.jl` reports
      only a change and adds one to the count of the file, and it reads no text and computes no
      hash (`FileChangeStore.jl:44-49`, `:476-487`). The reload of the save plan goes through the
      same cell. The first try on the page, in the stash `g4-step2-on-page`, has the watch that
      compares time and size, the cell, the operation that applies its answer, the make of a file
      that is not read yet, and its tests; the step moves them to the file. Update `filechange.md`
      and `fileformat.md`. Test: `test_filechange()`, a new set
      with an editor. A file is released, it changes on disk, and the file loads the change at its
      next draw. An explorer visits a file and puts the caret in it, visits another file, the first
      file changes, and Back shows the new text. A file below the screen of a dashboard reads
      nothing until a scroll shows it. A file that is not read yet refuses a save. A change with an
      equal hash changes nothing and logs nothing. In omnet-julia, in the same landing, the project
      page holds the editor's one file document of its fingerprint store file, and its facts demand
      the text of that file (D10). Then, in omnet-julia, `test_project_page()` and
      `test_fingerprint_store_document()`.
      What the implementation found:
      - `FileDiskState` gets `file_stamp`, `read_count`, `loaded_count` and `text`. A `@document`
        field cannot hold a cell as its value, so `text` holds a one-field box (`_FileTextCell`)
        that `ensure_file_text_cell!` writes where a file enters the window (its acquire) and
        `make_unread_file` writes. The serialization slice is below the editor, so the cell is
        made in the fileformat slice, not in the constructor of the state. Each file has a
        `BackgroundSource` of its own, so the files of a frame read in parallel.
      - The watch compares `compute_file_stamp` (time and size) and notes the path. It computes
        no hash and parses nothing; the settle wait and the hash moved to the read on the task.
        `receive_file_change!(editor, receiver)` has two arguments; a file adds one to
        `read_count`, the default takes none. `ApplyFileTextOperation` stores the answer with
        the check of today.
      - `FileViewToWidget` demands the text in the computation that arranges the view
        (`demand_file_text`), so only a drawn file reads. A file that enters the window with
        another time or size than its `file_stamp` counts a change (`is_file_stale`); a file with
        no stamp claims nothing. `SaveFileOperation` refuses a file with `loaded_count < 0`.
        `ReloadFileOperation` counts every reported change as read and takes the stamp of the file.
      - `make_unread_file(path, wrap)` is the make of a file that reads nothing; a file that is its
        own content raises an `ArgumentError`, because no such type is in `source/`.
      - The headless backend draws every row of a dashboard, so the test of a file below the
        screen holds 40 files in a dashboard that nothing draws and draws two views by hand; the
        rows that show are the work of step 1 (`test_dashboard_render()`). The test of the Back
        list is in `ExplorerTest.jl`, where the explorer helpers are, and has no caret in the file.
      - omnet-julia: the project page holds the file of its store (the editor's open file of the
        same path, else its own, `_take_open_fingerprint_file!`), and its facts demand the text of
        that file.
      - The store file of the page has no history, so by D1 a write of an update task kept the old
        text and gave a band that no view of the page draws: the count stayed old (main: the same,
        with a warning). The owner decided on 2026-11-07 ("Yes") that the fingerprint store is a
        file that a program writes and a person does not edit:
        `is_editable_file_type(::Type{<:LegacyFingerprintStoreFile}) = false` (omnet-julia
        `df3525ac6`). Its file takes each write by itself, the count follows the file, and Ctrl+S
        writes nothing of it. The owner said that a file that code writes and the editor reads
        again to present it is a common behaviour to support explicitly; the type answer is that
        support, as for the result files and the event log.
      - The assistant also proposed the hash of a print against the hash of the last load for an
        editable file with no history, and the owner said "Yes" to it on 2026-11-07. That is
        option B of D1, which the owner rejected on 2026-11-05, so the owner dropped it on
        2026-11-07 ("Yes") and D1 stands: only the history says that a file has edits. Step 6
        gives every open a history, so every file that a person edits has one.
      - omnet results: `test_fingerprint_store_document()` 32, `test_project_page()` 100,
        `test_campaign_explorer_content()` 57, all Pass; `test_ide_file_navigator()` 50 Pass, 2
        Fail (`IdeNavigatorTest.jl:50`, `:57`, the counts of main).
      - Results (projectured-julia): `test_filechange()` 198 Pass, `test_explorer()` 340,
        `test_open_page_operation()` 95, `test_file_tab()` 31, `test_file_watch_window()` 16,
        `test_user_interface_file()` 22, all Pass; `test_application()` 399 Pass, 1 Fail
        (`ApplicationTest.jl:1008`), 2 Broken, the counts of the base.
      - [x] **Fix after the landing: a crash at the exit of `test_filechange()`.** Found on
        2026-11-08: Julia ends with a SIGSEGV in 3 of 3 runs after all tests pass, on 1.13.1 and
        on the fork; before step 2 (`3b4505b7c`), 0 of 3. The tests drive frames by hand, so the
        loop of an editor never ends and its stop step `close_file_change_store!` never runs. At
        exit Julia removes the folders of `mktempdir()`, a watcher wakes, the stamp of a removed
        file is `nothing`, and `stamp == watched.stamp` on a field of type `Any` compiles
        `==(::Nothing, ::Tuple)` for the first time, which crashes while the process exits. The
        application closes its stores at the end of its loop, so a quit does not hit it. The
        owner chose fixes A and B on 2026-11-08:
        - A: each test that starts a watcher stops it in `finally`: an editor built with
          `file_change = true` runs its stop steps, and a `FileChangeStore()` of a test is closed
          with `close_file_change_store!`.
        - B: `WatchedFile.stamp` is a `Union{Nothing,Tuple{Float64,Int64}}` and
          `WatchedFolder.stamp` a `Union{Nothing,Float64}`, the types that `compute_file_stamp`
          and `_get_folder_stamp` give, so a watcher compiles no method while it runs.
        **Done on 2026-11-08.** `test_filechange()` three runs: 264 Pass, 1 Broken, exit code 0 each; `test_explorer()`: 392 Pass, exit code 0.
        - Not done: a report to Julia (option C).
- [x] **3. A load keeps the selection where it can (D6).** **Done on 2026-11-07.** The evaluation of `ReloadFileOperation`
      in `DocumentFile.jl`. Remove the limit from `filechange.md`. Test: `test_filechange()`, a new set
      with an editor. The caret is in the third paragraph, and the file loses two paragraphs. After
      the drain, the selection names a part, and the fault log has no new entry.
      What the implementation found:
      - `_repair_selection!(editor)` runs at the end of `ReloadFileOperation`, so every load keeps the
        selection: the read of a watch, "Load it", `reload_file_from_disk!` and F5. A selection that
        still names a part is left alone; else it becomes `get_valid_reference_prefix`. It runs only
        with an `Editor`, so a load with no editor changes no selection.
      - The test builds a dashboard file with three cards, puts the caret in the third, rewrites
        the file with one card, and asserts a valid, shorter selection and no new fault entry.
      - `test_filechange()` 206 Pass. (In two runs the Julia process hung at exit after the summary, in the
        exit handler of the code generator while a watcher thread compiled; the tests all passed.)
- [x] **4. A file keeps the editor's one file document of each picture that it shows (D5, D10).** **Done on 2026-11-08.**
      **Replaced by D14 (owner, 2026-11-08):** the page keeps no table of its pictures; the image
      holds its picture as a tab does. The code of this step (`7164886f6`) is reverted on 2026-11-08,
      by the owner's choice before a push, and the plan of Q10 designs the hold of a picture.
      Needs step 5 of the plan of the save, which adds `open_file_document!`.
      `collect_shown_file_paths` in `FileFormatModule`, the field `shown_files` of `FileDiskState`
      with the file of each path, which `open_file_document!(path; editor)` answers, and the hold of
      each of these files. The view of the file prints the
      file as a child with `:shown_files`. Update `fileformat.md`. Test: `test_filechange()`, a new
      set with a test file type that a person does not edit, as `_ReadOnlyProbeFile` is, which keeps
      a background cell, as the picture of G3 does, and a work that counts its reads. A file of 60
      pictures with 3 on the screen reads 3 files, and a scroll reads the pictures that come on the
      screen. A picture that a tab shows already is the file of that tab (`===`). The file holds the
      file of each picture, and a rewrite of one picture on the screen reads only that picture
      again. The release stops the watch of each picture that no other holder holds. Then
      `test_explorer()`, which saves and reads a content with such a file: `shown_files` and the
      view of a card stay out of the saved content.
      What the implementation found, and what the assistant decided at implementation:
      - Every load goes through the evaluation of `ReloadFileOperation`: F5, the first read of an
        unread file (`ApplyFileTextOperation` evaluates one), and a rewrite. So the update of
        `shown_files` is one call there, `open_shown_files!(editor, file)` (a new public name, in
        `DocumentFile.jl` next to `_splice_open_files`): it collects the paths of the unwrapped
        content with `collect_shown_file_paths`, resolves each against the folder of the file,
        gets each file with `open_file_document!`, stores the new `shown_files`, and evaluates
        `ChangeHeldDocumentsOperation(file, released, acquired)` for the files that came and went.
        That operation does nothing for a file that is not held. `_make_opened_file` reads its file
        at once, not through a reload, so it calls `open_shown_files!` after `make_file_tab`. With
        no editor or no file name the call does nothing. A path whose extension names no file type
        has no file in `shown_files` (an error would break the load).
      - `shown_files` is a field of `FileDiskState` (view state, not walked, not saved): a
        `Dict{String,Any}` from each path as `collect_shown_file_paths` answers it to its file
        document, empty by default. `FileDiskState` has keyword constructors only, so no call
        changed.
      - `collect_shown_file_paths(document)` is a generic function of `FileFormatModule` with a
        default that answers no path; it reads no disk. Domains add methods in step 5.
      - The hold: `acquire_document!(editor, file::FileDocument)` also holds the files of
        `shown_files` (`hold_documents!`), and `release_document!` releases them
        (`release_held_documents!`). A subtype with an acquire of its own, such as `SourceFile`,
        holds none; that is acceptable.
      - The print sets `:shown_files` in `FileToContent.print_document`, next to `:path_files`, and
        not in the view. Reasons: `FileToContent` prints the content of every file with the file in
        hand (a view, a card, an opened repeat); and a history around the content keeps its
        identity over a load (`replace_wrapped_document!`), so `make_reconciled_child_iomap_cell`
        keeps the child print and its context. A plain value in the context would be stale after a
        load. So the value of `:shown_files` is a computed cell that reads
        `get_file_disk_state(file).shown_files`, and the public accessor `find_shown_file(context,
        path)` reads that cell, so a computation that calls it follows a load. The test loads a
        page under a history with a new path, and the printer gets the new file.
      - A new picture file document is in the open files list from `open_file_document!` on, before
        a holder holds it. That is the known gap of the lifecycle question Q10 (save plan §7 risk);
        step 4 does not fix it.
      - New public names: `collect_shown_file_paths`, `open_shown_files!`, `find_shown_file`
        (`FileFormatModule`).
      - The test picture reads its text with the background cell of the text of a file
        (`demand_file_text`), not with a cell of its content, because the picture of G3 is not on
        this branch; the cell has a source of its own for each file, as the picture of G3 will.
      - The headless backend reads every part of a frame (at most 200 new links of a list), so it can
        not tell the rows that show from the rows that do not. The test of `test_filechange()` has a
        backend of its own, `_ClippedBackend`, that reads only the graphics inside the clip of a
        viewport and ends the walk of a vertical list at the first row past the bottom edge, as the
        renderer of the SDL backend does. A page of 60 pictures with 3 rows on the screen reads 3
        pictures. A jump of the scroll position reads the rows between the old and the new screen as
        well, because a pane reaches the offset of a list along the rows that it has built
        (`_clamp_to_list_ends`); the test asserts that the new screen is read and no row below it.
      - Results: `test_filechange()` 264 Pass, 1 Broken (the marker of the open question 10), 0 Fail,
        0 Error (the process ends with SIGSEGV after the summary, as before); `test_explorer()` 392
        Pass; `test_pred_file()` 87 Pass; `test_file_tab()` 31 Pass.
- [x] **5. The image of a Markdown page draws the picture that it holds (D14).** Needs G3, which is
      on main. The owner on 2026-11-15: "Do step 5 and 5a, question 10 can wait". So a page holds
      its pictures when it opens or loads, and an edit changes no hold (§8). Proposed by the
      assistant on 2026-11-15:
      - **The picture.** `MarkdownImage` gets the field `picture`: the editor's file document of
        the picture that its url names, or `nothing`. It is view state, as the `document_view` of a
        file of the explorer is, so no save writes it, and the text of the page names only the
        url. The image keeps the url that named the picture with it, and draws the picture only
        while its url is that url.
      - **Who gives the picture.** `splice_held_files!` runs where a file enters the editor: at the
        open of a tab (`open_file!`), at each load (`ReloadFileOperation`, also the first read of a
        file that `open_file_document!` gave), and at the load of the explorer content. Its walk
        calls one new generic function of the serialization slice, `splice_named_file!(node,
        find_file)`, for each document. The default does nothing, and the Markdown domain adds a
        method for `MarkdownImage`. A path is against the folder of the file, as a `file("…")` is.
        A url with a scheme, such as `https:`, and a path whose file type is not a picture get no
        picture, so an image never holds a page (§8).
      - **Who holds the picture.** The image holds it, as a tab holds the file that it shows:
        `acquire_document!(editor, ::MarkdownImage)` calls `hold_documents!`. `MarkdownRoot` holds
        each image of its tree, in one walk at its acquire. A tab holds the root already, because
        it holds each layer that it shows. The acquire of a file document holds its edited
        document too, so a card and a navigator hold the root. A load moves the hold of the file
        from the document before the load to the new document (`ChangeHeldDocumentsOperation`).
        So the first read of a file in a card holds its pictures, and a rewrite that names a new
        picture holds that picture.
      - **The printer.** `_md_image_value` draws `get_shown_picture(picture)`, and calls no
        `isfile` and no `Image(url)`. An image with no picture shows its url as text. So a
        Markdown document that no file of an editor holds, such as a test document, shows its
        images as text, unless the code that makes it gives each image a picture.
      - Update `markdown.md`, and the docstring of `ImageFile`, which names a card and a tab as the
        holders of a picture.
      - Test: `test_markdown_image_leaf()` gives its image a picture. A new set in
        `test/domain/markdown/`: a Markdown file with an image of a relative path, in a tab
        (`open_file!`) and in a card (`open_file_document!`). The image holds the editor's one
        `ImageFile` of the path, and the file is watched once, also while a tab of the picture
        shows it. A rewrite of the PNG gives the new size of the picture. An image with a web url
        or with the path of a page gets no picture. The release of the last holder stops the
        watch. Then `test_markdown()`, `test_filechange()` and `test_explorer()`.
      - The owner on 2026-11-15 approved this design ("Sounds good") and asked if a picture that
        does not show is read. It is not, and the design needs no change for it. A held picture
        reads nothing until a layout or a print asks for its size: the size computation of
        `make_picture_span` asks for the read, and the read of an `ImageFile` gets only the time
        and the size of the file, on a task. The pixels are a background cell that only a paint
        asks for. `is_file_stale` answers `false` for a file that was never read, and the watch of
        a folder reads no file.
      - What the implementation found:
        - `make_picture_span(file::ImageFile; max_width = 640)` is in the fileformat slice
          (`DocumentFile.jl`), because it needs `TextGraphics` of the text slice and
          `demand_file_text`. The style slice is below both. The span asks for the read only in its
          size computation, and gets a default size of 720 × 460, cut to the maximum width, until
          the size is known.
        - The field `picture` holds `url => file`. `find_held_picture(picture, url)` answers the
          file only while the url of the image is that url, so an edit of the url shows the url
          as text and not the old picture. `find_held_picture` and `is_picture_file_path` are in
          `Image.jl` of the style slice, because the three domains use them.
        - `splice_named_file!(node, find_file)` gets a `find_file(relative)` that resolves the
          path against the folder of the file and keeps one answer per path in one splice.
          `get_view_state_fields(::Type{<:MarkdownImage}) = (:picture,)` keeps the field out of a
          save and out of the walk of the splice.
        - The acquire of a `FileDocument` holds its edited document (`_collect_file_held_documents`
          in `FileChangeStore.jl`), and the release lets it go first. The evaluation of
          `ReloadFileOperation` moves the hold to the new edited document with
          `ChangeHeldDocumentsOperation`. This move also closes a gap of open question 10: a reload
          of a `.pred` dashboard now holds the files of its new cards, so the `@test_broken` of
          `FileChangeStoreTest.jl` is a `@test` now.
        - The test of a page in a card and the test of a rewrite of the page ask for the read with
          `demand_file_text`, because nothing draws the page in a headless test.
        - The window holds its tabs at its first drain. A tab that opens before that drain gets a
          second hold, so its close does not release the page. Each new test drains before its
          first open.
        - A card and a navigator of a file now hold its root as a tab does. `Dashboard`,
          `FormulaEnvironment` and `ResearchStudy` have an acquire of their own, so the formula and
          the research suites ran too.
        - `test_markdown()` and `test_rst()` found a fail of the layering guard that step 6 put on
          main with `a284048c1`: `using ..NavigatorModule: find_edited_document_target` in
          `MarkdownModule.jl` and `RstModule.jl` (PAR-QUALIFIED-EXTENSION). `PlatformModule` exports
          that name already, so the two lines go. `FileChangeModule` names `ReferenceModule` bare.
        - Results on the branch from main `3a9b4fae4`: `test_markdown_image_picture()` 19 Pass,
          `test_markdown_image_leaf()` 124, `test_image()` 144, `test_filechange()` 242 Pass and
          0 Broken, `test_pred_file()` 87, `test_open_page_operation()` 103, `test_explorer()` 507,
          `test_research()` 386, the five navigator tests 69, 99, 32, 26 and 41,
          `test_background_work()` 21, `test_window_wrappers()` 74, `test_window_shell()` 152,
          `test_assistant_work()` 133. `test_markdown()` 310 Pass and 1 Fail, the layering guard;
          after the fix the guard passes 7 of 7, and `test_markdown_link_target()` 17. Known on
          main: `test_formula()` 310 Pass, 1 Fail, 1 Broken (the time guard of
          `FormulaFrameGuardTest.jl:67`, 4.33 here, 4.22 on main); `test_work_plan()` 83 Pass,
          2 Fail (`WorkPlanTest.jl:122` and `:125`, only with Markdown loaded);
          `test_platform_layering()` 5 Pass, 2 Fail, with the 10 entries of main and no new entry.
- [x] **5a. The images of Book and RST draw the picture that they hold.** Needs step 5. The same
      model for `RstImage` and `RstFigure` (`RstToSyntax.jl`) and for `BookPicture`
      (`BookToSyntax.jl`): the field `picture`, a method of `splice_named_file!` for each type, the
      hold of each image by `RstRoot` and `BookBook`, and the picture span calls no `isfile`. A
      `BookPicture` whose `content` is a picture file, as a `.pred` file gives it from
      `file("…")`, draws that file and needs no `picture`. Update `book.md` and `rst.md`. Test: the
      image tests of each domain, one set as in step 5 for an RST file and for a book in a `.pred`
      file, then `test_book()` and `test_rst()`. (The owner's rule that a printer reads no disk,
      G3 open question 10.)
      - What the implementation found:
        - `RstFigure` and `RstImage` get `picture`, and `RstFigure(path; …)` gives the new field
          its cell. `RstRoot` holds each figure and each image of its tree.
        - A `BookPicture` gets a picture only when its `content` is a string that names a picture
          file. `find_book_picture_file` answers the `ImageFile` of the content, or the held
          picture. A picture of a `GraphicsDocument` draws as before.
        - The test of a book writes its `.pred` file with `print_pred_text(book)`.
        - Results: `test_rst_to_syntax()` 22 Pass, `test_book_to_syntax()` 40, `test_book()` 55,
          `test_rst_link_target()` 16. `test_rst()` 139 Pass and 1 Fail, the layering guard of
          step 5; after the fix the guard passes 7 of 7, and `test_book_layering()` 7 of 7.
- [x] **6. The assistant opens a file as a person does (D1).** Needs step 6 of the reflection plan,
      which is on main since `0836ec536`. The editor holds one file document of each path: a tab,
      a card, the explorer content and a load of a saved file all get it, and the first place that
      asks for it makes it (steps 5 and 6 of the plan of the save, G3).
      - **The history.** Each file document that the editor makes has a history, with the default
        capacity when the editor has no settings. The two ways that make one take the history from
        `_make_editor_history_wrap` (`FileSystemDocument.jl:255`): `_make_opened_file`, the open
        of a tab by `open_file!`, and `open_file_document!`, for a card, the explorer content and
        a held file of a load. So the change is in that one function: when
        `find_editor_settings` answers `nothing`, it answers the history of the default settings.
        The window of the application gives a history already (`Application.jl:120-121`), so that
        call does not change.
      - **The marks.** `make_file_tab` and `make_file_tab_content` lose their mark. Each makes a
        new file document that the editor does not hold open. An assistant that called them would
        make a second document of a path that a tab or a card holds already, with no history. The
        assistant uses `open_file!` for a tab and `open_file_document!` for every other place.
      - **The docstrings.** The marked docstrings of `get_file_content` (its example and its "See
        also" line, `FileProject.jl:140-143`) and of `Workspace` (`Workspace.jl:108`) name
        `open_file!` and `open_file_document!` in place of the two builders. The docstring of
        `open_file!` says that the tab follows a rewrite while the file has no edits. The
        docstring of `open_file_document!` says the same of each place that holds the document.
      - **The guide.** "Work with files" of `documentation/guide/orientation.md` (`:245`) has an
        example of a file document in a card already, which G3 wrote for a picture (`:258-269`).
        Its sentence says that this holds for every file, not only for a picture. Update "The
        tool set" of `fileformat.md` (`:113`) and "Open a file" of `filesystem.md` (`:81`).
      - **omnet-julia, in the same landing (open question 9).** The INI link
        (`source/ide/LegacyIniFileEntryToWidget.jl:144-149`) gets the editor's document of the
        file with `open_file_document!`, in place of `make_file_tab(path)`. Thus the link and a
        tab of the INI file show one document and its history.
      - **Tests.** `test_application()`, `test_assistant_documentation()`, `test_assistant_verbs()`,
        `test_referenced_document_editor()`, `test_filechange()` and `test_explorer()`. The last
        two open files in an editor with no settings, and such a file now has a history. In
        omnet-julia: `test_ide_file_navigator()`.
      **Done in projectured-julia on 2026-11-15 (branch `file-open`):** the history, the marks,
      the docstrings, the guide and the tests. **Done in omnet-julia on 2026-11-15 (branch
      `file-open`, `6b6375c93`):** the INI link and its test. Not landed.
      What the implementation found (2026-11-15, branch `file-open`):
      - `_make_editor_history_wrap(editor)` is
        `make_history_wrap(something(find_editor_settings(; editor), Settings()))`. The file-system
        slice uses the settings slice for `Settings`, which comes before it in the include order.
        A `Settings()` holds only the groups that a call asks for, so it makes only
        `HistorySettings`, with its default of 100 steps.
      - Besides the docstrings that the step names, two more named the old state:
        `OpenFileOperation` said that the open gives a history only when the editor has settings,
        and the marked docstring of `ImageFile` named `make_file_tab`. Both are changed. The
        docstrings of `make_file_tab` and `make_file_tab_content` say that each makes a new
        document that no other place shares, and name `open_file_document!` and `open_file!`.
      - `ApplicationTest` asked for `:make_file_tab` among the names of the assistant. It asks for
        `:open_file!` now, and that neither builder is offered.
      - The new test set "each file that an editor with no settings makes keeps a history" in
        `FileChangeStoreTest.jl` opens a tab with `open_file!` and gets a card document with
        `open_file_document!` in an editor with no settings: each content is an `UndoBuffer` of
        100 steps whose `has_unsaved_edits` answers `false`, not `nothing`.
      - `test_explorer()` expected the selection path of a JSON file in an editor with no
        settings as `….document.content.entries[1]…`. The content of the file is its history now,
        so the path is `….document.content.content.entries[1]…` (`ExplorerTest.jl:377`).
      - `test_open_page_operation()` asserted that a file which a link opens in an editor with no
        settings has no history. The set "a target that names a file opens it with a navigator, in
        a history" now asserts a history in both editors (`OpenPageOperationTest.jl:315`).
      - Eight more test functions open a file in an editor with no settings, so they run too:
        `test_background_work()`, `test_open_page_operation()`, `test_window_wrappers()`,
        `test_assistant_work()`, `test_window_shell()` and `test_work_plan()` of the platform, and
        `test_markdown_link_target()` with `test_markdown_link_gestures()` of Markdown.
      - The results on the branch: `test_filechange()` 241 pass and 1 broken, as on main;
        `test_explorer()` 507 pass; `test_open_page_operation()` 103 pass; the other five
        platform functions pass; the two Markdown functions 14 and 18 pass;
        `test_assistant_verbs()` 98 pass; `test_referenced_document_editor()` 134 pass.
        `test_application()` gives 412 pass, 1 fail and 2 broken: the fail is the usage text of
        an agent bar (`ApplicationTest.jl:1016`), which fails on main too.
        `test_assistant_documentation()` gives 2889 pass and 4 errors: the three range functions
        of `ReferenceModule` and `describe_task`, which fail on main too.
      - The INI link of omnet-julia can not simply call `open_file_document!`. A new document of
        that call reads its file only when a view draws it, and the link finds its section with
        `find_navigator_target(file, section)` at the click, so an unread file has no section.
        On main the link reads the file in the gesture answer with `make_file_tab(path)`, which
        is a read of the disk in a reader. A listing does not call the answer, because the
        bindings of the link have no name. The owner chose option B (open question 13).
      - The finders of a section of a file did not look past the history (open question 14).
        The default `find_navigator_target(root, target)` now calls
        `find_edited_document_target(root, target)` (`NavigatorPageOpen.jl`): a layer, a node
        whose `get_edited_field` names a field, answers what the document in that field names,
        with the step of the field before each `Reference`; a node that is no layer answers
        `find_web_url(target)`, as the default did. So a file and the history inside it both
        are layers, and a file of a type with no method names the parts of its root. The
        Markdown and RST file methods call it first and then look for a file beside them; the
        `IniFile` method of omnet-julia did by hand what the default does, so it is removed.
        The navigator guide says the rule, and its sentence on the history of a file that a
        link opens names the history inside the file.
      - The INI link calls `open_file_document!(path)` and answers `DoNothingOperation()` when
        no editor opens the file. `LegacyPartPageTest.jl` presses its links in the evaluation of
        an editor with no settings: the file link opens the editor's one document, whose content
        is an `UndoBuffer`; the section link opens the file at its top before a read, and at the
        section after `ReloadFileOperation`.
      - Tests of the rule: `test_markdown_link_target()` and `test_rst_link_target()` each have a
        file whose content is an `UndoBuffer`, and the target answers
        `.content.content.elements[…]`.
      - The omnet results, in a scratch environment of the two worktrees:
        `test_legacy_part_pages()` 44 pass, `test_ini()` 47 pass, and `test_ide_file_navigator()`
        50 pass and 2 fail. The two fails are the Julia file (`IdeNavigatorTest.jl:50`) and the
        Markdown file (`:57`) of the folder, which fail on main too; the set of a NED and an INI
        file that open in a history passes 20 of 20.
      - The three omnet functions build no assistant (the file navigator test uses `llm = :none`),
        so they run with no network namespace: a `bounded-run` job is a user service, which can
        not make one. Ollama loaded no model in the run.
      - After the rebase on main (projectured-julia `8541a3592`, omnet-julia `9f698f89c`, no
        change to a `Project.toml`), the same functions give the same counts: `test_filechange()`
        241 and 1 broken, `test_explorer()` 507, `test_open_page_operation()` 103, the Markdown
        link targets 17 and gestures 18, the RST link targets 16, and the three omnet functions as
        above.
- [x] **6a. After a load, the caret takes keys (D6).** Found by the check of step 7 on
      2026-11-15. The owner on 2026-11-15: "Yes" to a step that fixes it, and then step 7 runs
      again in both windows. The selection is stored along its path: each document on the path
      keeps the rest of the path in its own `selection` field (`selection.md`, "Selection
      storage"). A load puts a new document in the file, and the nodes of the new document keep
      none. So the views draw no caret and the readers take no key, while the root still names a
      valid path. `_repair_selection!` writes the selection only when its path names no part.
      Proposed by the assistant on 2026-11-15:
      - After a load, a live selection that passes through the file (`get_stored_selection(file)`
        and `is_live_selection(file)`) is written again from the root with
        `ReplaceSelectionOperation`, with the types of the new document, so the new document
        holds its part of the path. A selection that names no part becomes the longest start of
        its path that names a part, as before. A dormant selection is left alone, because the tab
        writes it again when it takes the focus.
      - Update `filechange.md` (the limit of the selection after a load) and `fileformat.md`.
      - Test: the set of step 3 in `FileChangeStoreTest.jl` asserts where the new document holds
        the selection after a load, and that a typed letter goes in at the caret. Then
        `test_filechange()`, `test_explorer()` and step 7 again.
      - What the implementation found:
        - A `ReplaceSelectionOperation` of the same path writes nothing: `_sync_selection!`
          returns at the root when the stored path equals the new one, because it takes the
          chain below as whole. (In the live probe of step 7 it worked, because the stored path
          there differed above the file.) So `_repair_selection!(editor, file)` calls
          `set_selection!` at the root, which writes the rest of the path into each document on
          the path, as `_select_under!` of the conversation editor does. It runs inside the
          evaluation of the load, at the root of the editor, so it keeps
          PAR-SELECTION-WRITTEN-AT-ROOT.
        - `FileFormatModule` names `SelectionModule` bare now, so the list of the platform
          import check loses the entry `using ..SelectionModule: get_selection` (9 entries).
        - The card title of a dashboard takes no typed letter in the natural view, also with no
          load, so the key test types into a text file (`notes.txt`, `PrimitiveString`). The test
          editor needs `Keyboard`, `Mouse` and `Display`; with `devices = Device[]` it reads no
          key.
        - The set of step 3 asserts that the new card holds `.title{1}`, and the new set "after a
          load, the caret takes keys" asserts that the new text holds `.value{24}` and that a
          typed "w" goes in at offset 24. Without the fix the three assertions fail, with it they
          pass.
        - Results in a warm session of the worktree: `test_filechange()` 245 Pass, 0 Broken;
          `test_explorer()` 507; `test_pred_file()` 87; `test_open_page_operation()` 103; the
          navigator document 32 and gestures 26; `test_markdown_image_picture()` 19;
          `test_markdown_link_gestures()` 18; `test_platform_layering()` 5 Pass and 2 Fail with
          the 9 known entries and no new one.
- [x] **7. The check in the window.** No code. Needs steps 5 and 6. In a window of `projectured`
      and of `omnet_ide`, a script rewrites a Markdown file with three pictures 20 times, 2 s
      apart. The assistant opens the file with `open_file!`, and it puts the same file document in
      a card with `open_file_document!`. `take_picture` after the first and the last rewrite must
      show the new pictures in both views and no band. `describe_undo_history()` must have no new
      step. The caret must stay, and a scroll in the tab must leave the card where it is. Then the
      person types one letter, and the next rewrite must show the band in both views. Record the
      results here.
      - **The check in the window of `projectured` on 2026-11-15**, main `6a24a6db6`. The window
        ran in a Julia of the main checkout, with the editor of `run_application`
        (`_make_application_editor`, no settings file, no assistant), on the SDL backend under
        the offscreen driver, so no window opened on the desktop of the owner. The loop ran with
        `run_editor!(make; wait = false)`. A script in a second process wrote `guide.md` and its
        three PNG files `a.png`, `b.png` and `c.png` (ImageMagick) for each rewrite. The
        assistant functions ran from the script of the check: `open_file!`,
        `open_file_document!`, a dashboard "Check" with one card of the file in the Explorer
        (`insert_elements!`, `open_explorer_page!`), and `move_pane!`, so the card and the tab
        show side by side. The click, the wheel and the keys went to SDL as pushed events.
        `write_window_picture`, the writer of `take_picture`, took the pictures.
        - Rewrites 1 to 20, 2 s apart: after each rewrite, each picture read its file once and
          decoded it once (20 and 20), and both views showed the new pictures, with no band.
          The page and the tab kept the same three picture files, each watched once. The caret
          kept its path (offset 38 of the first paragraph). `describe_undo_history()` had no new
          step, and the history of the file had none.
        - The page loaded 37 times for 20 rewrites, because the shell writes `guide.md` in many
          small writes, and a read can see a part of them. Each picture file is written at once,
          and reads once.
        - A wheel of 3 notches in the tab scrolled it to 171 px. The card stayed at 0, also after
          the next rewrite.
        - After one typed letter, the next rewrite showed the band "guide.md changed on disk."
          with "Load it" and "Keep mine" in both views. The page kept the letter, and the
          pictures still showed each rewrite, because a picture file has no edits.
        - **Found: after a load, the caret takes no key.** A letter typed after rewrites 1 to 20
          made no edit, and the caret did not draw, although the selection kept its path. The
          letter went in after a new click. A test of each cause alone: with the caret scrolled
          out of view and no load, a letter goes in; after one load of the page, with the caret
          in view, a letter does nothing. A plain text file (`notes.txt`) does the same, so the
          fault belongs to each load of a file (step 3), not to the pictures of step 5. After the
          load, the selection is valid and equal (`==`) to the same path with fresh types. A
          `ReplaceSelectionOperation` with that same path makes the caret take keys again. So a
          load leaves the selection as it was, and the views do not map it to the new document
          until the selection is written again. The test of step 3 asserts only a valid selection
          and no fault, so it does not see this.
        - Step 6a fixes the caret, so the check runs again below.
      - **The check in the window of `projectured` again on 2026-11-16**, on `window-check` with
        step 6a (`833e73496`), in a new process of the worktree (so the bare import of
        `SelectionModule` loads), the same way as above. The caret came from one click at
        offset 38 before the rewrites.
        - Rewrites 1 to 20: 36 loads; each picture read and decoded 20 times; the same three
          picture files, each watched once; no band; the caret at offset 38 after each load;
          `describe_undo_history()` the same as before the rewrites; the history of the file
          empty.
        - The wheel in the tab after rewrite 19 scrolled it to 171 px, and the card stayed at 0.
          After rewrite 20 and after the letter, the tab was still at 171: the write of the
          selection after a load scrolls nothing.
        - A letter typed after the 20 rewrites, with no new click, went in at the caret ("The
          xcaret goes here."), and the history of the file had one step. Rewrite 21 showed the
          band "guide.md changed on disk." with "Load it" and "Keep mine" in both views, the page
          kept the letter, and both views drew the caret.
      - **The check in the window of `omnet_ide` on 2026-11-16**, omnet-julia main `6b6375c93`
        with projectured-julia `window-check` (`833e73496`). The IDE ran as
        `run_omnet_ide(<copy of the fifo sample>; backend = SdlBackend(), wait = false, llm = :none)`
        under the offscreen driver, in a copy of `environment/all` of omnet-julia whose paths name
        the worktree. `ollama ps` showed no model before and after.
        - The same steps as in `projectured`: the tab and a card of a dashboard "Check" in the
          Explorer side by side, a click at offset 38, then rewrites 1 to 20, 2 s apart.
        - The results are the same: 34 loads; each picture read and decoded 20 times, one picture
          file of each path, each watched once; no band; the caret at offset 38;
          `describe_undo_history()` the same; the wheel scrolled the tab to 171 px and the card
          stayed at 0, also after rewrite 20 and after the letter. The letter after the rewrites
          went in at the caret with no new click, and rewrite 21 showed the band in both views.
        - Found, outside this plan: the `Manifest.toml` of `environment/all` of the omnet main
          checkout is not in git and dates from 2026-11-11. It has no entry for `ProjecturedGit`
          and `ProjecturedGitExample`, which `Project.toml` names since 2026-11-14, so a load of
          `OmnetIde` in that environment fails until a `Pkg.resolve()`. The copy for this check
          got the two entries by hand.

## 8. Risks

- **Decode off the loop.** The background work of the pixels decodes a PNG on a task after the
  frame. The decode of the backend must be safe on such a task. The watcher never reads a file. G3
  measured 960 decodes on 16 tasks with results equal to a decode on the main task, and step 7
  shows it in a window.
- **The scroll pane moves into the view (D2).** A test or a caller that finds the scroll pane
  inside a `FilePage` fails. The tab finder of `open_file!` compares `tab.content` with the page
  (`FileSystemDocument.jl:262-288`). Step 1a runs `test_filechange()`, `test_file_tab()`,
  `test_explorer()`, `test_file_watch_window()` and `test_referenced_document_editor()`.
- **The page goes away (D10).** Step 1b changes 17 file types, the open, the watch, the open files,
  about 60 test lines in 11 test files, and five places in omnet-julia (the inventory of
  2026-11-06). A caller that is missed fails at its load or at its first call, so step 1b loads
  every package of both repositories. The recorded lists of the compiled calls
  (`package/*/precompile/`) name `FilePage` about 190 times; they are recorded again as
  `documentation/design/compile-ahead.md` says before the landing, not edited by hand.
- **The history inside the file of a navigator (D13).** An open from a link of a navigator had one
  history around the navigator. Each file that the navigator visits now has a history of its own,
  so an undo after a visit undoes only the edits of the file on the screen. Step 1b runs
  `test_open_page_operation()` and the navigator tests of the explorer.
- **The cost of a rewrite.** A page reads again only when it is drawn, and only the pictures on the
  screen (D4, D5), so a timeline page of 60 pictures with 4 on the screen costs 4 decodes. A dashboard on a page with a height reads
  only the cards on the screen already (measured by the layout plan: 6 of 60). A dashboard on a page
  with no height, and a plain layout over a vector, read all of their elements until the layout plan
  (`a-layout-paints-only-what-the-screen-shows.md`) lands.
- **An edit that passes no reader.** A direct write to `cards` changes no hold. The assistant writes
  through operations, so its edits pass the reader.
- **A write into the content of a tab or a card changes no hold** (a known limit of the landing,
  open question 10). After `replace_referenced_value!(tab, :content, make_file_view(b))` the file
  `b` is not held and not watched, and the old file stays held and watched. Main has the same gap
  for a tab today, so G4 does not make it worse. Only the open and the close of a tab, the four
  places of step 1, the navigator, the tree and the Files tree change a hold.
- **An edit of an image changes no hold** (steps 5 and 5a, accepted by the owner on 2026-11-15).
  An image that an edit adds, or whose url an edit changes, has no picture: it shows its url as
  text until the next load of its file. A picture whose image an edit or a rewrite removes stays
  held and watched until the last tab or card of the page closes, because a tab holds the root
  that it opened with. Both last a bounded time, and the plan of Q10 removes them.
- **The part under the pointer.** Step 3 repairs the selection only. The part under the pointer can
  name no part after a load, until the pointer moves.
- **A saved explorer content.** `shown_files` and the view of a card must stay out of the explorer
  content file. Until the plan of D7 lands, that file writes a page in a card whole, with a copy of
  the text of its file, and the next start reads that copy back. Steps 1 and 4 run
  `test_explorer()`, which saves and reads a content.
- **Search rank.** Steps 1a and 6 change marked docstrings, so `search_api` can rank other names
  first. `test_referenced_document_editor()` shows it.
- **A save of a page that the person did not edit.** A Markdown page prints another text (§2). If
  the person presses Ctrl+S, the file changes, and the script writes it again later. The plan of
  the Markdown print, which another agent writes in the Markdown domain, fixes this (Q6). G4 does
  not change it.

- **A file that is not read yet** (the save plan, D6, decided by the owner on 2026-11-05). The open
  of a saved holder makes the file document of each held file and reads nothing. The background
  cell of its text (D4) reads it when its view is drawn. Until then the view shows that the file
  reads, and the file refuses a save. Today a page with no hash saves with no check
  (`FilePage.jl:191-192`), so step 2 must close that for the file. Step 2 must also give a way to
  make a file that reads nothing, with the history of the settings, which step 5 of the save plan
  uses. Step 2 tests it: an unread file reads at its first draw, and a save before that read writes
  nothing.

- **A file that shows itself, or two files that show each other, hold each other** (found at the
  review of step 4, 2026-11-08). `open_shown_files!` gets the editor's one document of each path,
  so a page whose image names the page itself holds itself, and two pages whose images name each
  other hold each other. The release of the last tab then leaves each with a holder, so the file
  stays watched and in the open files until the editor ends. A picture shows no file, so this can
  not happen with the pictures of steps 4 and 5; it can happen only when an image names a file of a
  type that shows files. It belongs to the lifecycle of a document (Q10), so step 4 does not
  guard it.

## 9. Open questions for the owner

1. **D1.** Answered by the owner on 2026-11-05: yes (option A). The question was: keep D15e: only a history says whether a page has edits. Every open of a file gives a
   history, and `make_file_tab` and `make_file_tab_content` lose their mark. Recommended by the
   assistant: yes.
2. **D4.** Answered by the owner on 2026-11-05: B, the first read of a watch reports to its receiver
   (D4). The question was: can a watch start from the hash that its receiver gives once?
3. **Rule 4.** Answered by the owner on 2026-11-05: the three parts stay, but the page keeps unread
   pictures and reads only the pictures on the screen (D5). The question was: step 4 adds a context property `:shown_files`, a page field `shown_files` and a
   generic function `collect_shown_file_paths`. Are these acceptable, or do you want another way to
   the print? Recommended by the assistant: these three.
4. **D2.** Answered by the owner on 2026-11-05: each place shows its own view (D2). The question
   was: a page that a tab and a card show shares its scroll place. Is that acceptable, or must
   each card show a view of its own (`make_document_view`)? Recommended by the assistant: accept it
   for G4.
5. **Order.** Answered by the owner on 2026-11-05: yes, steps 1 to 4 land first (§6). The question
   was: do steps 1 to 3 of `reflection-api` land on main before G4? Recommended by the
   assistant: yes.
6. **The Markdown print.** Answered by the owner on 2026-11-05: a plan of its own in the Markdown
   domain, outside G4. An ordered list keeps its kind, and the printer rules follow the layout of
   most Markdown files of the repositories. The question was: a Markdown page does not print back to its text, so a save of a page with
   no edit changes the file. Is that a plan of its own? Recommended by the assistant: yes, outside
   G4.
7. **A file with no page under D4.** Answered by the owner on 2026-11-05: option A, no bare file is
   watched (D8). The question was asked again after D4 changed. The first form was: a file document with no page keeps no hash, so it can not
   compare the first report of its watch. A file that a person does not edit then loads at each
   acquire, and any other file logs a warning at each new watch. Is that acceptable? Recommended
   by the assistant: yes. After D1, every open of a person or the assistant gives a page, so only
   code that holds a file document itself makes such a file.
8. **The order of step 6.** Decided by the assistant on 2026-11-05: step 6 waits for step 6 of the
   reflection plan, which has the new window text already. Step 6 of the reflection plan is on main since `0836ec536`, so this
   step can start. The question was: the window text on main names `make_file_tab_content(path)`, and
   `test_assistant_documentation` fails when the text names a name with no mark. Must G4 step 6
   wait for step 6 of the reflection plan, or change that sentence itself? Recommended by the
   assistant: wait. The branch has the text already, and both plans change `Application.jl`.
9. **D1 in omnet-julia.** Decided by the assistant on 2026-11-05, as for G8 and G9: step 6 changes
   the INI link of omnet-julia (`LegacyIniFileEntryToWidget.jl:144-149`) in the same landing.
   Revised on 2026-11-15: the link gets the editor's document of the file with
   `open_file_document!`, and with it the history. `OpenFileOperation` opens a tab, but the link
   opens the file in the navigator, here or in a new tab, and the page of a file is gone. The question was: the INI link of omnet-julia opens a file with no page and no history. Must
   a plan of omnet-julia open it through `OpenFileOperation`, so that it gets a page and a
   history? Recommended by the assistant: yes, in a plan of omnet-julia after G4 step 6.
10. **One rule for what a holder holds.** Deferred by the owner on 2026-11-07 ("Yes") until after
    the plans of this session: it becomes a plan of its own, which starts with questions to the
    owner, and G4 lands with the gap as a known limit (§8). The owner said that a change of the
    kernel is acceptable but must be right, that the acquire and the release are a good interface
    that can serve other needs, and that the plan must find the states of a file that is in the
    document but not watched, such as a file in a long list that scrolls in and out of view. The
    assistant proposed a model to start from: the editor compares the old and the new value at the
    place of each write and acquires what joins and releases what departs; each holder type
    answers which parts it shows, so a page in a Back list or a closed node is not held; the counts
    of the holders stay. The states after step 2 that the assistant described: a file that is held
    is watched, a change only adds one to its count, it reads only when it is drawn and out of
    date, and a file that is not held keeps the time and the size of the version that it holds and
    compares them when it is held again. Open in that plan: whether a long list holds every element
    or only the elements on the screen (the assistant recommends every element, because a document
    and not its layout decides what it holds). The text of 2026-11-06 follows. Step 1 found that a holder
    changes what it holds only on the paths that add the change (§2): a dashboard at four places,
    the pane tree when it opens or closes a tab. An edit of the content of a card or of a tab adds
    no change, so the new file is not watched and the old one stays watched. The question: one
    rule for every holder, by which each holder answers what it holds now and the editor makes the
    holds match that answer after each edit inside the holder, written as a plan of its own before
    steps 1 to 3 land? Recommended by the assistant: yes. The four places of step 1 and the hold
    code of the pane tree then go away.
11. **The file document as the watcher.** Answered by the owner on 2026-11-06: yes (D10). The
    question was: change this plan so that the file document watches its file and keeps the hash
    and the band, the view draws the band, and the page goes away?
12. **A change of the shown paths by an edit.** Answered by the owner on 2026-11-08 with D14: the
    image holds its picture as a tab does, so no table of shown paths exists to change. The
    question was: An edit that adds or removes a
    shown path (step 5: a person adds an image to a Markdown page) does not change `shown_files`,
    which step 4 updates only at a load. Proposed by the assistant: the reader of the file adds the
    change of what it holds to such an edit, as the reader of a dashboard does for an edit of
    `cards` (`_add_card_holds`).
13. **The INI link of omnet-julia (step 6).** Answered by the owner on 2026-11-15 ("Agreed"):
    option B in this landing, and option C later, in a plan of its own that also covers a
    Markdown link to a heading of another file. The question was: the link gets the editor's
    document with `open_file_document!`, which reads the file only when a view draws it, so a
    first press finds no section. (A) keep `make_file_tab`, a second document with no history;
    (B) use `open_file_document!`, and a press on a file that is not read yet opens it at the
    top, as a Markdown link to a heading of another file does; (C) the navigator keeps the
    name of the section and finds it after the read, a new mechanism. Recommended by the
    assistant: B, then C.
14. **A section in a file whose content is a history.** Answered by the owner on 2026-11-15
    ("Yes"): fix the finders of the three file types in this landing, by one shared function of
    the platform. Found on 2026-11-15 at step 6: the
    finders of a section of a file, `find_navigator_target(file::IniFile, …)`,
    `(file::MarkdownFile, …)` and `(file::RstFile, …)`, read `get_file_content(file)` and expect
    the root of the domain there. With a history the content is the `UndoBuffer`, so they find
    nothing: `find_navigator_target(file, "#usage")` answers `.content.elements[3]` for a file
    with no history and `nothing` for the same file with a history. On main this holds for each
    file that the window opens, because the window has settings; step 6 gives a history in each
    editor. With option B of question 13, a press on a file that is read reaches its section
    only when the finder looks past the history.
