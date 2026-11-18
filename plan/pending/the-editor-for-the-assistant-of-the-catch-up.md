# The editor for the assistant of the catch-up

**Status:** a list of asks, not a plan with steps. Written 2026-11-18 by the assistant of the
campaign window of omnet-julia, which follows the INET baseline catch-up in the IDE
(`bin/omnet_ide --assistant=acp ~/workspace/ghci-baseline-catch-up`), at the request of the
owner: "collect the issues which should be fixed in the next version of the editor to make your
life easier". The findings come from the live check of
[the-ide-follows-the-baseline-catch-up.md](../../../omnet-julia/plan/pending/the-ide-follows-the-baseline-catch-up.md)
(omnet-julia, step 11), which holds the details of each case. The assistant adds a row when it
meets a new one.

## 1. Faults

| # | Fault | Where it showed | What it cost | Fix idea | State |
| --- | --- | --- | --- | --- | --- |
| F1 | A page in a file tab falls to one fixed column of 280 px. `open_file!` shows a file in a `FileView`, whose scroll pane gives its content the view as a minimum and an edge in two cells (`layout-rules.md` §3), and `DashboardToWidget` read only an exact width. | The walk page `catch-up.pred` on 2026-11-18. | The owner saw narrow cards; the assistant opened a second tab on the file document to get the width. | The page takes the edge of a bounded range as its width (`_get_page_width`). | Fixed on the branch `baseline-catch-up`, commit `1b650f6d1`, `test_explorer` 514 of 514; not landed. |
| F2 | A pane on a file document draws no band. When the file on disk changes and the history has an edit, the apply makes the band "changed on disk" with "Load it" and "Keep mine", but only `FileViewToWidget` draws it, so the page stays old without a sign. | The step page of step 58 in the tab "Step 58 (wide)". | The owner asked twice why a page was old; the assistant found the band in the disk state by code and loaded the file. | Every place that shows a file draws the band, or a pane on a file document gets the file view. | Open. |
| F3 | A click on a generated page makes a history entry, so the file counts as edited and F2 follows. The gesture is not known; the writes of the page (`followed_sample`, the maximized card, the reads of the comparisons) are view state. | The step page of step 58; the Explorer said "Open files · 1 unsaved". | See F2. | Find the gesture; a view-state write must not enter the history. | Open. |
| F4 | A shown tab does not always read a rewritten file. The watch reported the change (`read_count` above `loaded_count`), nothing asked for the text for over a minute, and the read came when the owner went to the file tab. In the two cases that did not read, the focus was in the Assistant pane; in the two controlled writes that read at once, `show_pane!` had moved the focus into the tab. | The walk page, the writes of 12:11 and 12:28. | The owner had to load the page by hand; the assistant loads every open page by code after each rewrite. | A test with a drawn pane that has no focus and no input after the write; the demand of the text must not depend on the focus. | Open. |
| F5 | A document that is not a file gets no scroll pane in a tab: `make_document_view(document) = document`, and only a file gets a `FileView`. A workflow of ten stages with its entries, which `start_workflow!` opens in a third of the height, did not scroll. | The workflow tab on 2026-11-18. | The owner could not scroll; the assistant put `WidgetScrollPane(workflow; grows = (width = false, height = true))` in the tab. | A view of a workflow that scrolls, or a scroll pane around every document that a tab shows without a view of its own. | Open. |
| F6 | A link on a Markdown page opens a new navigator tab each time, so one file gets several tabs ("summary.md" twice). | The links of the Progress card. | Tabs multiply. | A link to a file that is open shows its tab, as `open_file!` does. | Open. |
| F7 | The reference of a tab goes stale when tabs come or go: `show_pane!` then fails with "That reference names nothing and not a pane". | The tab "catch-up (wide)" after a close of another tab. | A failed call and a second `find_pane`. | A tab reference that follows the tab, or every pane verb accepts a title or the document. | Open. |
| F8 | A card of a dashboard shows with the generic view on the page of an explorer, not with the view of its content (the owner, 2026-11-18). | The walk page `catch-up.pred` as an entry of the explorer "Catch-up", on the page of the navigator. | The page of the walk is not readable in the explorer; the owner opens the tab of the file instead. | The navigator of an explorer draws a dashboard and its cards with the same views as a tab does. | Open. |

## 2. Names that the assistant could not write

The system text of the window lists the names that the code can write. These were missing or
different, and each cost a failed call and a search:

| # | Name | What happened | Fix idea |
| --- | --- | --- | --- |
| N1 | `Explorer` | Not among the names; `ExplorerSection` and `Dashboard` are. The assistant took it from `ProjecturedPlatform.ExplorerModule`. | List `Explorer` with the explorer verbs. |
| N2 | `Dates`, `ProjecturedKernel`, `ProjecturedPlatform` | Not imported in the scratch module; a `Dates.unix2datetime` or a type name with its module fails. | Import `Dates` in the scratch module; say in the system text how to reach a module. |
| N3 | `get_file_disk_state`, `is_folder_watched`, `find_file_change_store` | Not in the names; `is_folder_watched(store, folder)` differs from its real signature `is_folder_watched(path; store, receiver)`. | The state of a file against the disk as a verb for the assistant: the counts of the watch, the band, the stamp. |
| N4 | `describe_undo_history(buffer)` | No method for an `UndoBuffer`; only the editor-wide form exists. | A form that takes a document or a file. |
| N5 | `get_session_open_file_list()` | Answers a plain `OpenFileList`, which cannot be iterated: "Pass a part, a document with its place". | Answer a part, or document the field `files`. |
| N6 | `has_unsaved_edits(file)` | Answers `nothing` for a file; `true` or `false` only for its history (`file.content`). | A method for the file. |

## 3. Wishes

| # | Wish | Why |
| --- | --- | --- |
| W1 | A picture of one tab, shown or not: `take_picture` with a tab in place of the window or the selection. | To check a page the assistant does not want to put in front of the owner. |
| W2 | An event from the editor to the assistant: a file changed, a task ended, a job of `bounded-run` ended. | The assistant acts only in its turns; between them a rewritten page stays old (F4) and the workflow waits. A wake on such an event keeps the window current without a scheduled poll. |
| W3 | A file format for a plain text file (`.log`, `.txt`), as a text document with a filter. | The walk log and the outputs of the tools could be entries of the explorer; today no format of the session reads `.log`. |
| W4 | The band of F2 in the pane of the assistant too: a line that says which open file changed on disk and holds an edit. | The assistant would see it without a read of the disk state by code. |
| W5 | A matrix cell with a least height and a scroll, so a row of 16 scalars is not 10 px. | On a test page the cells of the history fold and show no value. |
| W6 | `open_file!` for a `.pred` page gives the page the width of the tab, with no second tab on the file document. | Until F1 lands, the owner has two tabs of one page. |
| W7 | A returned `String` of `execute_julia_code` reaches the agent as one line; `println` or `Base.Text` is needed for a long text. | Known; a note in the system text would save a wrong first call. |
