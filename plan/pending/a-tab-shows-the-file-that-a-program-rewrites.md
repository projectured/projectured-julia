# A tab shows the file that a program rewrites

> **Kind:** design · **Status:** a plan, 2026-11-05, revised at `main` `6b93bfcf3`. Nothing is
> built. · **Sibling plan:** G3
> [the-assistant-shows-a-picture-file.md](the-assistant-shows-a-picture-file.md) · **Stands on:**
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

1. The assistant opens a page in a tab with `open_file!`, and puts the same page in a card of a
   dashboard.
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
- A picture path of a page resolves against the current folder of the process. The printer reads
  the disk, and a computation decodes the picture on the loop. A rewrite of a picture does not
  reach a page whose text stays the same.

## 4. The design

**Only the history of a page answers whether the page has edits (D1).** The owner decided this on
2026-10-15 (D15e of the done plan) and again on 2026-11-05. Every open of a file by a person or by
the assistant gives the file a history: `OpenFileOperation`, `open_file!` and the page of a file in
the Files tree. With no settings, the history keeps the default capacity of `UndoBuffer`, 100
steps. The window of the application gives its file tabs a history already. The assistant opens a
file as a person does, with `open_file!`. `make_file_tab` and `make_file_tab_content` lose the mark,
because they make a file or a page with no history, and no gesture of a person does that.

**One file is one page in the window, and each place shows its own view of it (D2).** The tab and
the card show the same `FilePage`, as a tab and the navigator share a page now. One watch, one hash
and one band serve every view. `make_document_view(::FilePage)` makes a view document that keeps the
scroll place of that one view. The scroll pane moves from the page into the view: the page holds
its file directly, and the view draws the band of the page above the file in its scroll pane.
`make_file_tab_content` answers the view of a new page, so each tab gets a view, and the navigator
makes a view at each visit already. The assistant gets the page with `find_open_file_document(path)`
after `open_file!`, and puts it in a card with `insert_elements!`.

**A dashboard holds what its cards show (D3).** Each card keeps the view of its content in a slot
that a walk does not enter, as a navigator keeps the view of its page, so a path into a card goes
through its content. The acquire of a dashboard makes the view of a card that has none, and holds
the view of each card. The view holds the page, and the page holds its file. The reader of the
dashboard adds a `ChangeHeldDocumentsOperation` to each edit of `cards`, as the tree adds one to
the open of a node. The Insert key, a paste, `insert_elements!`,
`delete_elements!` and an undo must all pass that reader, and the test of step 1 checks each one. A
picture of G3 in a card follows its file in the same way.

**The text of a page is a background cell (D4).** A page reads its file as a folder reads its
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

No bare file is watched (D8). Each watched file is the editor's one page of that file, so the
`apply` of the cell always has a page and its history.

**A load keeps the selection, or the deepest part of it that remains (D6).** After
`LoadFilePageOperation` puts the new document in the file, a selection that names no part becomes
the longest start of its path that names a part.

**A page keeps the editor's one page of each picture of its file (D5, D8).**
`collect_shown_file_paths(document)` answers the paths that a document writes for the files that it
shows, such as the images of a Markdown page. It reads no disk, and the default answers none. The
page resolves each path against the folder of its file. It keeps the editor's one page of each path
in the view state field `shown_files`, not a bare file (D8). `open_file_page!(path; editor)` of the
plan of the save answers that page: the page that the editor has open for the path, or else a new
page of a file that a person does not edit, which reads nothing when it is made. So a picture that
a page and a tab show is one page, with one watch. Each picture has a `BackgroundSource` of
its own (G3 D10). The page holds each
of these pages, so each watches its file while the page is held. A load of the page that changes
the paths changes `shown_files` and what the page holds.

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

**The image of a page draws the picture that its page keeps.** The view of the page prints the file
as its own child, with the context property `:shown_files`. The image printer takes the picture of
its path from that property and puts the cell of its pixels into the graphics. It reads no disk.

**A dashboard with a page in a card saves through the plan of the save of a file alone (D7).** That
plan makes a file saved alone write `file("…")` for each opened file that it holds, with no throw.
Another agent writes it as a plan of its own on 2026-11-05. G4 does not change the save. Until that
plan lands, the explorer content file writes a page in a card whole, with a copy of the text of its
file (§2).

## 5. Decisions

A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. What says that a page has edits.** A, decided by the owner on 2026-11-05: only the history,
  as D15e says. The open of a file always gives a history, with the default capacity when the editor has no
  settings. `make_file_tab` and `make_file_tab_content` lose their mark, because no gesture of a
  person makes a page with no history. B, rejected: the hash of a print against the hash of the last
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
  one view does not reach the other, and a save of one writes over the other.
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
- **D8. No bare file is watched.** Decided by the owner on 2026-11-05 (open question 7, option A).
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

## 6. How the names reach the assistant, and the order of the plans

G4 adds no name for the assistant. A tab uses `open_file!`, and a card uses
`find_open_file_document`, `insert_elements!`, `DashboardCard` and `find_explorer_content`. Each of
these carries the mark on main (§2).

- **The rule.** Steps 1 to 4 of the reflection plan landed on main at `2bbc18fb5` on 2026-11-05. A
  name reaches the assistant when the docstring of its generic function or of its type ends with
  the line `For the assistant.`. No list keeps the names by hand. G4 uses only the mark, and it adds
  no name to `make_editor_api`.
- **What G4 changes.** Step 1a changes the marked docstring of `make_file_tab_content`, because the
  function answers a view. Step 6 removes the mark from `make_file_tab` and
  `make_file_tab_content`. It changes the marked docstrings that name them, `get_file_content` and
  `Workspace`, so that their example and their "See also" line name only offered names. It changes
  the marked docstring of `open_file!`: the tab follows a rewrite while it has no edits. `FilePage`
  and `collect_shown_file_paths` carry no mark.
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

The dependencies: step 1a needs step 1. Step 4 needs step 5 of the save plan, which adds
`open_file_page!`. Step 5 needs G3 on main. Step 6 needs step 6 of the reflection plan, which is on
main since `0836ec536`. A saved dashboard with a page in a card needs the save plan (D7), and no
step saves one.

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
- [ ] **2. The text of a page is a background cell (D4).** The page in `FilePage.jl` gets the cell,
      its `BackgroundSource`, and an `apply` that loads with the check of today
      (`receive_file_change!`, `FilePage.jl:324-345`). The watch in `FileChangeStore.jl` reports
      only a change and adds one to the count of the page, and it reads no text and computes no
      hash (`FileChangeStore.jl:44-49`, `:476-487`). The reload of the save plan goes through the
      same cell. Update `filechange.md` and `fileformat.md`. Test: `test_filechange()`, a new set
      with an editor. A page is released, its file changes, and the page loads the change at its
      next draw. An explorer visits a file and puts the caret in it, visits another file, the first
      file changes, and Back shows the new text. A page below the screen of a dashboard reads
      nothing until a scroll shows it. A page that is not read yet refuses a save. A change with an
      equal hash changes nothing and logs nothing. In omnet-julia, in the same landing, the project
      page holds the page of its fingerprint store file (D8). Then, in omnet-julia, `test_project_page()` and
      `test_fingerprint_store_document()`, because the project page watches a file with no page.
- [ ] **3. A load keeps the selection where it can (D6).** `LoadFilePageOperation` in
      `FilePage.jl`. Remove the limit from `filechange.md`. Test: `test_filechange()`, a new set
      with an editor. The caret is in the third paragraph, and the file loses two paragraphs. After
      the drain, the selection names a part, and the fault log has no new entry.
- [ ] **4. A page keeps the editor's one page of each picture of its file (D5, D8).** Needs step 5
      of the plan of the save, which adds `open_file_page!`. `collect_shown_file_paths` in
      `FileFormatModule`, the field `shown_files` of `FilePage` as view state with the page of each
      path, which `open_file_page!(path; editor)` answers, and the hold of each of these pages. The view of the page prints the
      file as a child with `:shown_files`. Update `fileformat.md`. Test: `test_filechange()`, a new
      set with a test file type that a person does not edit, as `_ReadOnlyProbeFile` is, which keeps
      a background cell, as the picture of G3 does, and a work that counts its reads. A page of 60
      pictures with 3 on the screen reads 3 files, and a scroll reads the pictures that come on the
      screen. A picture that a tab shows already is the page of that tab (`===`). The page holds the
      page of each picture, and a rewrite of one picture on the screen reads only that picture
      again. The release stops the watch of each picture page that no other holder holds. Then
      `test_explorer()`, which saves and reads a content with such a page: `shown_files` and the
      view of a card stay out of the file.
- [ ] **5. The image of a Markdown page draws the picture of its page.** Needs G3 on main.
      `collect_shown_file_paths(::MarkdownRoot)` gives the path of each image that names no web
      address, and `_md_image_value` takes its picture from `:shown_files` and reads no disk.
      Update `markdown.md`. Test: `test_markdown_image_leaf()` in
      `test/domain/markdown/MarkdownImageLeafTest.jl`, with the document in a page. A new set: a
      relative path names the picture beside the page, and a rewrite of the PNG gives the new size
      of the picture. Then `test_markdown()`.
- [ ] **5a. The images of Book and RST draw the picture of their page.** Needs step 5. The same
      model for `BookToSyntax.jl` and `RstToSyntax.jl`: a method of `collect_shown_file_paths` for
      each root, and the image span takes its picture from `:shown_files` and calls no `isfile`.
      Update `book.md` and `rst.md`. Test: the image tests of each domain, then `test_book()` and
      `test_rst()`. (Decided by the assistant on 2026-11-05 from the owner's rule that a printer
      reads no disk; G3 open question 10.)
- [ ] **6. The assistant opens a file as a person does (D1).** Needs step 6 of the reflection plan
      on main. The open of a file always gives a history, with the default capacity when the
      editor has no settings: `_make_opened_file_content` and `_read_file_page` in
      `FileSystemDocument.jl`. The window of the application gives one already
      (`Application.jl:116-117`), so that call does not change. `make_file_tab` and
      `make_file_tab_content` lose their mark. The docstrings of `get_file_content`
      (`FileProject.jl:110-115`) and `Workspace` (`Workspace.jl:108`) name `open_file!` in their
      place. The docstring of `open_file!` says that the tab follows a rewrite while it has no
      edits. `documentation/guide/orientation.md` gets one example of a page in a card, after the
      example of `open_file!` (`orientation.md:242-247`) that step 6 of the reflection plan wrote. Update "The tool set" of
      `fileformat.md` and the open of a file in `filesystem.md`. Tests: `test_application()`,
      `test_assistant_documentation()`, `test_assistant_verbs()` and
      `test_referenced_document_editor()`.
- [ ] **7. The check in the window.** No code. In a window of `projectured` and of `omnet_ide`, a
      script rewrites a page with three pictures 20 times, 2 s apart. The assistant opens the page
      with `open_file!` and puts it in a card. `take_picture` after the first and the last rewrite
      must show the new pictures in both views and no band. `describe_undo_history()` must have no
      new step. The caret must stay, and a scroll in the tab must leave the card where it is. Then
      the person types one letter, and the next rewrite must show the band. Record the results
      here.

## 8. Risks

- **Decode off the loop.** The background work of the pixels decodes a PNG on a task after the
  frame. The decode of the backend must be safe on such a task. The watcher never reads a file. G3
  measured 960 decodes on 16 tasks with results equal to a decode on the main task, and step 7
  shows it in a window.
- **The scroll pane moves into the view (D2).** A test or a caller that finds the scroll pane
  inside a `FilePage` fails. The tab finder of `open_file!` compares `tab.content` with the page
  (`FileSystemDocument.jl:262-288`). Step 1a runs `test_filechange()`, `test_file_tab()`,
  `test_explorer()`, `test_file_watch_window()` and `test_referenced_document_editor()`.
- **The cost of a rewrite.** A page reads again only when it is drawn, and only the pictures on the
  screen (D4, D5), so a timeline page of 60 pictures with 4 on the screen costs 4 decodes. A dashboard on a page with a height reads
  only the cards on the screen already (measured by the layout plan: 6 of 60). A dashboard on a page
  with no height, and a plain layout over a vector, read all of their elements until the layout plan
  (`a-layout-paints-only-what-the-screen-shows.md`) lands.
- **An edit that passes no reader.** A direct write to `cards` changes no hold. The assistant writes
  through operations, so its edits pass the reader.
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

- **A page that is not read yet** (the save plan, D6, decided by the owner on 2026-11-05). The open
  of a saved holder makes the page of each held file and reads nothing. The background cell of its
  text (D4) reads it when the page is drawn. Until then the page shows that it reads and refuses a
  save. Today a page with no hash saves with no check (`FilePage.jl:191-192`), so step 2 must close
  that. Step 2 must also give a way to make a page that reads nothing, with the history of the
  settings, which step 5 of the save plan uses. Step 2 tests it: an unread page reads at its first
  draw, and a save before that read writes nothing.

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
   the INI link of omnet-julia (`LegacyIniFileEntryToWidget.jl:150-156`) in the same landing, so
   that it opens through `OpenFileOperation` and gets a page and a history. The question was: the INI link of omnet-julia opens a file with no page and no history. Must
   a plan of omnet-julia open it through `OpenFileOperation`, so that it gets a page and a
   history? Recommended by the assistant: yes, in a plan of omnet-julia after G4 step 6.
