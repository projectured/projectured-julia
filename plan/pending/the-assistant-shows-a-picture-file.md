# The assistant shows a picture file

> **Kind:** plan · **Status:** a plan, written 2026-11-05 at `main` `de6b4e95d`, revised the same
> day at `main` `0d8dd49a0` to follow the decisions of the owner (model B), and revised again at
> `main` `6b93bfcf3` to follow D9, D11, D12 and G4 D8. Nothing is built.
> · **Sibling plans:** G4 [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md),
> G5 [the-assistant-fills-a-live-table.md](the-assistant-fills-a-live-table.md), and the plan of the
> save [a-file-saved-alone-names-the-files-that-it-holds.md](a-file-saved-alone-names-the-files-that-it-holds.md),
> whose steps 1 to 4 land before this plan (§3.8) · **Needs:** steps 1 and 2 of the plan of the
> save, and G4 steps 1a and 2 (§5) · **Stands on:** [style.md](../../documentation/package/platform/style/style.md),
> [filechange.md](../../documentation/package/platform/filechange/filechange.md),
> [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md),
> [natural.md](../../documentation/package/platform/natural/natural.md),
> [the-assistant-finds-its-names-by-reflection.md](../done/the-assistant-finds-its-names-by-reflection.md)

This plan closes the gap G3 of the inet-cpp plan `plan/pending/ieee80211-chart-baseline-evolution.md`,
§9.3. The owner decided on 2026-11-05 to close G1, G3, G4, G5 and G9 first. §3.8 says where the
plans of G4, G5 and the save meet this plan.

The use case: matplotlib writes 17 chart pictures as PNG files at each of about 60 commits. The
assistant puts a picture into a card of a dashboard, into a tab of its own and into a cell of a
table. The person reads it at a size that fits, at its natural size, or zoomed. Another program
writes the same file again, and the picture then shows the new file.

## 1. What exists

The assistant checked each row at `main` `6b93bfcf3` on 2026-11-05, and the rows of omnet-julia
at its `main` `a1dfa5af3`. The inventory of `SEALING.md` covers `source/kernel/` only, and no step
of this plan changes a file there.

| Thing | Where | State |
| --- | --- | --- |
| The picture document | `ImageFile(filename)`, `source/platform/style/Image.jl:20-34`; `set_cell_computation!`, `:50` | `ImageFile <: ImageDocument <: Document`. Two fields: the path, and `raw`, the pixels or `nothing`. The constructor of one argument decodes nothing. Its docstring has no line "For the assistant.". No caller in projectured-julia uses `set_cell_computation!(::ImageFile, f)`. |
| The file document | `FileDocument`, `source/platform/serialization/FileProject.jl:40-63`; `is_editable_file_type`, `FileSplice.jl:35-45`; `read_file_content`, `:47-68`; `_read_set_file`, `:72-74` | A file document has a `filename` and a `content`, and its docstring has the mark. A type that a person does not edit is read with `read_file_content`. omnet-julia has one: `LegacyResultFile` (`source/legacy/result/presentation/LegacyResultFile.jl:177-201`), with a third field that follows the cell of the content. The trait `is_file_document` is the other way to be a file (`FileProject.jl:65-81`), and no type uses it. |
| Six decodes on the loop | `MarkdownToSyntax.jl:472-484`, `BookToSyntax.jl:566-588`, `RstToSyntax.jl:1228-1243`, `RosterToGraphics.jl:146-159`, `ConversationToWidget.jl:366-382`, `example/platform/TextDocumentExample.jl:49-60` | Markdown, Book, RST, the roster and the example set a computation on `raw` that calls `decode_image` (`BackendInterface.jl:215-220`). The conversation calls `decode_image` in the print itself (`:369`), also for a part of the draft (`ConversationEditor.jl:638`). Markdown, Book and RST also call `isfile` in the print (`:473`, `:577`, `:1229`), and each makes its picture at each print of its node (`MarkdownToSyntax.jl:502`, `BookToSyntax.jl:602`, `RstToSyntax.jl:1252`, `:1299`). |
| The decodes and the pictures of omnet-julia | `LegacyChartComparisonToWidget.jl:45-54`, `LegacyStoreEntryToWidget.jl:50-66`, `ModuleAppearanceToGraphics.jl:192-208`; `SimulationEmbedToWidget.jl:1047`, `LegacyChartBaseline.jl:52`, `LegacyChartTestTask.jl:563` | The first two set a decode computation on `getfield(image, :raw)` of an `ImageFile`, and the second reads `picture.raw` for its box. The third decodes the icon of a module in a computation and makes no `ImageFile`. The last three make an `ImageFile(path)`: a label holds one, and a facet and a task record answer one. |
| The decode of the backend | `decode_sdl_image`, `SdlBackend.jl:5932-5958`; `decode_image`, `:5975`; `decode_image_file!`, `:5961-5972` | `IMG_Load` and `SDL_ConvertSurfaceFormat` need no video. No code calls `IMG_Init`, so the loaders start at the first decode. A check on 2026-11-05 ran 960 decodes of a PNG, a JPEG and a BMP on 16 tasks of the default pool, on 8 threads, started together and with no video. Each answer was equal to a decode on the main task. `decode_image_file!` writes pixels into `raw`, and nothing calls it. |
| The draw of the pixels | `_image_payload`, `_content_size`, `_push_content!`, `WidgetToGraphics.jl:1233-1286`; `_extract_image_data`, `_graphics_span_element`, `TextToGraphics.jl:1721-1764`; `GraphicsImage`, `GraphicsDocument.jl:787-800` | A label and a text span read `raw` in the print and put the value into a `GraphicsImage`. A label checks `content isa ImageDocument`. It draws the pixels at their natural size, or smaller in their shape to fit the maximum of its slot (`_fit_image_size`, `WidgetToGraphics.jl:1257-1268`). With no pixels it draws a box. |
| The paint of the backend | `_render_canvas!`, `SdlBackend.jl:2034-2101`; `_render_image!`, `:1988-2005`; `_record_painted_element!`, `:2450-2462`; `_compute_first_drawn_index`, `:2103-2107`; `compute_first_visible_index`, `GraphicsDocument.jl:1092-1099` | The render and the dirty walk read the `data` of an image when they visit it. They skip the elements outside the clip only in a canvas with `layout_vertical` or `layout_horizontal` and no overlap: the lines of a text (`TextToGraphics.jl:696`) and the list layouts (`LayoutList.jl:144`, `GridList.jl:146`). The canvases of `HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout` and `StackLayout` have `layout_none` (`LayoutToGraphics.jl:1014`, `:1337`, `:1842`, `:2062`, `:2227`), so the render and the walk visit each of their elements, also outside the clip. The paint runs in the print stage, with the editor of the evaluation, before `start_background_cell_work!` (`EditorLoop.jl:70`, `:111-122`, `ReadEvaluatePrint.jl:185`). |
| A picture in a tab or a card | the renderer table, `NaturalProjection.jl:165-231`; `FileToContent`, `FileToContent.jl:120-128` | No row names `ImageDocument`. A file document draws its content through the recursion. An `ImageFile` falls to the reflection row and draws as its fields. |
| A picture in a cell | `make_roster_value_cell`, `RosterToGraphics.jl:122-144`; `WidgetTheme.jl:211-212` | A cell of a roster or of a task table shows an `ImageFile` at most 120 px high. |
| Zoom and pan of any content | `WidgetTransformPane`, `WidgetDocument.jl:1640-1690`; its wheel, `WidgetToGraphics.jl:7540-7563`; its keys, `:7608-7620` | Ctrl+wheel zooms about the pointer, the wheel pans, and Ctrl+0 resets the zoom when it is not reset. The keys come after the content, so a key that the content reads first does not reach the zoom. Its docstring has no mark, and `WidgetDocument` has none (`WidgetDocument.jl:5`). It has no `get_edited_field`, so a tab does not hold its content (`PaneSurgery.jl:548-562`, `PaneDocument.jl:388-404`). `WidgetScrollPane` has the mark and the field (`WidgetDocument.jl:1590`, `:4034`). The window binds Ctrl+0 too (`AppearanceDocument.jl:41`), and nothing binds Ctrl+1. |
| A read off the loop | `BackgroundSource`, `BackgroundCells.jl:8-35`; `make_background_cell`, `:181-232`; `wait_for_cell!`, `:404-440` | A read records a demand and never waits. After the print of a frame, the editor runs the work of each source on a task of the default pool (`:319-334`, `BackgroundWork.jl:89-101`). `apply` stores an answer in the document by an operation. With no editor, `wait_for_cell!` computes the value on the task that calls it. |
| A holder that gives its source | `_make_unread_folder`, `FileSystemDocument.jl:304-321`; `receive_folder_change!`, `:556-560` | A folder takes the source of the folder that holds it, so one task reads every folder of a tree that one frame asks for. The input of its listing is the path and a read count (`:311-316`), and a change of the folder adds one to the count. |
| The watch of a file | `WatchedFile`, `FileChangeStore.jl:44-49`; `watch_document_file!`, `:138-152`; `acquire_document!(::FileDocument)`, `:280-284`; `_prepare_file_change`, `:476-487` | A holder that acquires a file document watches its file. For a type that a person does not edit, the watcher compares the hash of the time and the size of the file. It reads a changed file again on its own task with `read_file_content_again` (`DocumentFile.jl:458-480`). A drain gives the new content to the receiver: a page loads it, and a file with no page reloads it (`FilePage.jl:324-345`). The reload stores `replace_wrapped_document!(old, new)` in `content` (`DocumentFile.jl:449-456`). G4 step 2 makes the watch only report a change (G4 D4), and G4 D8 watches no bare file. |
| A file document in a document | `_cut_copy`, `FileCut.jl:267-284`; `_cut_leaf`, `:293-299` | A file document inside another document is a cut. A save of one file, such as a `.pred` file, throws for it. The plan of the save changes that (§3.8). |
| The read of a file by its extension | `read_document_file`, `DocumentFile.jl:96-103`; `_read_registered_file`, `:107-111`; the table at `:1-25`; `make_file_tab`, `:165-174` | For a registered type, `read_document_file` answers the content of the file, not the file document. A path that does not exist gives the seed of its extension, and `DocumentNothing()` for an extension with no seed (`:99`, `:37`). `make_file_tab` puts the content into the file document of the extension. The open path first wraps the content in a history (`FileSystemDocument.jl:219-227`), and a history takes only a `Document` (`UndoDocument.jl:91`). A `.png` has no file type. |
| A picture file in the Files pane | `OpenFileOperation`, `OpenFileOperation.jl:23`; its evaluation, `FileSystemDocument.jl:201-227`; `get_file_document_type`, `FileProject.jl:187-193` | Return on `chart.png` throws "no file document registered for extension .png". No tab opens. A file that the explorer selects reads its page the same way (`FileSystemDocument.jl:55-87`). |
| A dashboard | `DashboardCard`, `Dashboard.jl:22`; `Dashboard`, `:61` | A card takes any document. A dashboard has no `acquire_document!`, so a card holds no content. G4 step 1 adds it. |
| The mark | `ASSISTANT_MARK`, `source/kernel/tool/AssistantMark.jl:4-23`; `collect_marked_api`, `:25-65`; `make_editor_api`, `Application.jl:345-362` | The reflection plan is done ([its plan](../done/the-assistant-finds-its-names-by-reflection.md)). `make_editor_api` collects the marked names of the loaded modules, and no list is kept by hand. A mark on a type also offers each exported subtype. `ImageFile`, `ImageDocument`, `WidgetTransformPane` and `decode_image` have no mark. `GraphicsImage` (`GraphicsDocument.jl:785`), `WidgetScrollPane`, `FileDocument` (`FileProject.jl:61`), `open_file!` (`FileSystemDocument.jl:248`) and `find_open_file_document` (`OpenFileList.jl:107`) have it. |
| The window text and the orientation guide | `EDITOR_SYSTEM`, `Application.jl:364-416`; `APPLICATION_SYSTEM`, `:418-449`; `documentation/guide/orientation.md:156-221`; `test_assistant_documentation`, `AssistantVerbsTest.jl:475-480` | The window text names only the verbs that its rules need. It names `open_file!` and `read_document_file` to read a file (`Application.jl:406-407`), and it shows no canvas. The orientation guide shows a canvas (`orientation.md:177-187`), a chart and a graph (`:189-197`) in a tab. The test fails for a name of the guide that no model can write. |

## 2. What the code lacks

1. **A picture is not a file.** No file type reads a `.png`, so the open of a picture throws, and a
   holder can not follow the file of a picture.
2. **A picture has no view.** An `ImageFile` in a tab or a card draws as its fields.
3. **The print reads the pixels.** Six holders decode on the loop. The label and the text span read
   `raw` in the print, so a pixel cell that a print reads asks for every picture that the print
   lays out.
4. **The assistant can not write the names.** `ImageFile` and `WidgetTransformPane` have no mark,
   and a tab does not hold what a transform pane holds.

## 3. Design

### 3.1 A picture file is a file that a person does not edit

`ImageFile` is a file document: `ImageFile <: FileDocument`, with the fields `filename` and
`content` (D1). `is_editable_file_type` answers `false` for it, as for the result files of
omnet-julia. The content is the picture that the file holds: a new document `Image <:
ImageDocument` (D9). So `ImageDocument` keeps the pictures that draw, and the file keeps the path.

The style slice registers the file type for `.png`, `.jpg`, `.jpeg`, `.bmp` and `.gif`. The slice
depends on the serialization slice already, so no slice edge is new. Then the open path of today
works for a picture with no change. `read_document_file` answers the picture, `make_file_tab`
answers the `ImageFile` that holds it, and Return in the Files pane opens a normal file tab. A file
that the explorer selects shows its picture in the same way. G3 adds no special tab.

`read_file_content(::Type{<:ImageFile}, path)` reads nothing of the file: no byte, and not its time
or its size (D12). It answers `Image(path)`, a picture that is not read yet. `ImageFile(path)`
reads nothing too. A history of the open path wraps the picture, as it wraps any content,
and gets no step. No person edits a picture, and a change of the file never replaces the picture
(§3.3).

A file saved alone writes `file("…")` for a picture file that it holds, with the path relative to
the folder of the saved file. It does not write the picture (the plan of the save, its D0). The
plan of the save implements that (§3.8). Its open of the saved file gives each held file the
editor's one page of that file, or a new page that reads nothing, through `open_file_page!(editor,
path)` (its D1, D6 and D7). A reload of the holder is a load (its D7). In a `.pred` file, an `Image` that a document holds with no file writes
only its path.

### 3.2 The picture reads its pixels on a task, and only a paint asks for them

The pixels are a background cell (D2). Its input is the path and the count of changes of the
picture, `read_count` (D12). A folder reads its listing with the same kind of input
(`FileSystemDocument.jl:311-316`). The work decodes the file and answers the pixels, which carry
their natural size. It reads no time and no size of the file. It answers the exception of a file
that does not exist or does not decode as a value, so one bad file fails no other picture of the
batch, and a read of the cell never throws. Its `apply` writes the natural size of the pixels into
the plain cell `natural_size` of the picture, or the exception into the plain cell `failure`, as the
`apply` of a folder writes its entries (`FileSystemDocument.jl:315-316`). It writes no cell whose
value stays the same (§3.3). The write is view state, so undo records none.

The print reads only `natural_size` and `failure`, which are `nothing` until the first answer. It
never reads the pixel cell. A label and a text span put the pixel cell into the `data` of their
`GraphicsImage`, so the backend reads it when it paints the image. The paint runs inside the frame,
with the editor of the evaluation, and before the frame starts the background work. Thus a paint
records the demand, and the work runs after the frame. A picture with no natural size measures as
pixels of 320 by 240, fitted to its slot.

The owner said: "The drawing is lazy in the backend when the graphics domain is read." §1 shows
where that holds: the backend skips an image outside the clip only in a list canvas and in the lines
of a text. The owner answered open question 9: a plan of its own makes each plain layout give the
backend only the elements that meet the visible area: `a-layout-paints-only-what-the-screen-shows.md`.
Its measurement shows that a dashboard on a page with a height reads only the pictures on the screen
already (6 of 60), because its grid is a list. A dashboard on a page with no height, and a plain
layout over a vector, read all 60. G3 accepts those extra reads until that plan lands.

Each picture has a `BackgroundSource` of its own, which `Image(path)` makes (D10). No maker gives
a source, so `ImageFile(path)`, `Image(path)` and `open_file_page!(path; editor)` take no keyword
`source`. The pictures that one frame demands thus decode in parallel, each on a task of the
default pool. This holds for the pictures of a Markdown page and of a dashboard alike, and it does
not depend on which holder made a picture first.

A script with no editor gets the pixels with `wait_for_cell!(cell; editor = nothing)`, as for any
background cell. A holder must make a picture where it builds a document. A computation that makes
a picture makes a new pixel cell at each run, so it must not read that pixel cell.

### 3.3 The picture follows its file through the page of the file

A holder that follows a picture file holds the editor's one page of that file (G4 D8): a tab, a
card, the page of a Markdown file for its images (G4 step 5), and a record of a table that holds
such a page (G5). The page watches the file while a holder holds it, and the page is the receiver
of the watch. No bare file is watched. A label, a cell, the conversation or a transform pane that
holds an `ImageFile` with no page shows the file as it is at its first paint. Such a picture reads
its file again only when its maker makes a new picture.

The watch only reports that the file changed (D12, G4 D4). It reads no byte, no time and no size,
and it computes no hash. A change goes to the picture in four steps:

1. The report reaches the page. Where G4 adds one to the count of changes of a page, for a report
   of the watch and for F5 (G4 step 2), a page whose content follows its file by itself adds one to
   the count of that content instead. `receive_file_change!` gets a method for `Image` that adds one
   to `read_count` and answers `true`. The default answers `false`, and the page then reads its
   file as G4 D4 says (D13).
2. The page reads nothing for a picture file, and the file keeps the same picture. So the picture
   needs no rule of `replace_wrapped_document!`, and the history of the file takes no new document
   (D9).
3. The pixel cell gets a new input. It answers its last pixels until the new ones come, and only a
   picture that the backend paints asks for them again.
4. The `apply` of the answer compares the natural size that the work read with `natural_size`, and
   the failure with `failure`. With the same values, it writes no cell. So a report with no change,
   such as the report at the start of a watch (G4 D4), changes no cell of the document (G4 property
   4). A picture on the screen decodes once more for such a report.

G3 adds no watch, no event, no payload and no channel. D3 rejects the watch of a folder for each
picture, with its fragment `ImageFileWatch.jl`, and a watcher that compares the time and the size of
a picture file. A tab holds each layer of what it shows, and `get_edited_field(::WidgetTransformPane)
= :content` makes a transform pane one, as a scroll pane is (`WidgetDocument.jl:4034`). So a zoom
tab of the page of a picture holds that page. G4 step 1 makes a dashboard hold its cards, and G5
makes a table hold its records.

### 3.4 The view and the size

The view is a new projection `ImageToWidget` of the natural slice. Its row in the renderer table
names `ImageDocument`, beside `GraphicsDocument` (`NaturalProjection.jl:207`). An `ImageFile` draws
through the row of a file document, which prints its content, the picture, and a page draws its
file. The view draws the pixels as a label draws them. Before the first answer it draws a box with
the path. After a failed read it draws the path and the reason from `failure`. A tab of a picture
takes the base name of its file from `get_document_title(::FileDocument)`.

The size comes from the holder, and the view document of each place keeps the choice of Ctrl+1
(D4, D8, D11):

- **Fit.** The picture draws at its natural size, or smaller in its shape to fit the maximum of its
  slot. It never draws larger. A card, a cell and a tab give such a slot. In a file tab the slot has
  the width of the tab and no maximum height (`DocumentFile.jl:201-202`), and the view of a page of
  G4 step 1a keeps that scroll pane. So the picture fits the width, and the tab scrolls a taller
  picture.
- **Natural size.** Ctrl+1 draws the picture at its natural size: one pixel of the image to one
  pixel of the screen. The holder scrolls a picture that is larger than its view
  (`WidgetDocument.jl:1538-1539`). Ctrl+0 goes back to the fit, which stays the default. Each place
  keeps the choice in its view document, as it keeps its scroll place (D11). The view of a page
  gives its view document to the print of its file as a context property, as it gives
  `:shown_files` (G4 D5). The picture view takes the choice from that property only when that view
  shows this picture. For Ctrl+1 its reader returns a `ReplaceViewStateOperation` that writes the
  choice, so no history records it. The reader returns an operation for Ctrl+1 only at the fit, and
  for Ctrl+0 only at the natural size. Otherwise it returns `nothing`, so Ctrl+0 still reaches a
  transform pane and the zoom of the window. A picture with no view of a page around it, such as a
  picture in a label, a cell or a transform pane, stays at the fit, and its reader returns `nothing`
  for both keys.
- **Zoom.** In a `WidgetTransformPane` around a picture or around the page of one, Ctrl+wheel zooms
  about the pointer, the wheel pans, and Ctrl+0 resets the zoom. The pixels keep their natural
  resolution.

### 3.5 A caption and pictures side by side

The holder gives the caption: the title of a card or a tab, the alt line of a Markdown image, a
column of a table. A `WidgetLabel` under the picture in a `VerticalLayout` gives a longer one. For
pictures side by side, a `HorizontalLayout` with `Fill` shares gives each picture a slot, and each
picture fits its slot. A comparison view is the gap G7.

### 3.6 The holders of a picture

Each holder stops its decode. A label and a text span draw an `ImageDocument`, and the picture that
`get_edited_document` answers for an `ImageFile` or for the page of one. A label that holds an
`ImageFile` or its page thus draws its picture. Only a holder of the editor's one page of the file
follows the file (§3.3, G4 D8).

| Holder | Under model B | Follows its file |
| --- | --- | --- |
| A tab | `open_file!` and `OpenFileOperation` show the view of the editor's one page of the file (G4 step 1a). | Yes. |
| A card of a dashboard | It holds the editor's one page of the file. `find_open_file_document` answers that page after `open_file!` (G4 D2), and the open of a saved dashboard gives it (the plan of the save, its D6). A card that holds a bare `ImageFile` draws its picture. | With a page: yes, because the dashboard holds its cards (G4 step 1). With a bare `ImageFile`: no. |
| A zoom tab | `WidgetTransformPane(page)` holds the page through `get_edited_field` (step 4). | With a page: yes. With a bare `ImageFile`: no. |
| The image span of Markdown | Step 2: it makes `Image(path)` in place of `ImageFile(path)` and its decode, and sizes the `TextGraphics` from `natural_size`. Its `isfile` stays. G4 step 5: the span takes from `:shown_files` the editor's one page of the picture file, which the page of the Markdown file holds, and it reads no disk (G4 D5). A picture that a Markdown page and a tab show is one page. | After G3: no. After G4 step 5: yes. |
| The picture leaf of Book, the picture of RST | The same as Markdown. G4 step 5a gives them the model of G4 step 5 (open question 10). | After G3: no. After G4 step 5a: yes. |
| The cell of a roster | It holds what the record holds: a bare `ImageFile`, or the page of a picture file, which a record holds after the open of a saved table (the plan of the save, its step 5 and its open question 10). Step 2 makes the cell draw a picture when `get_edited_document` answers an `ImageDocument` for the value, so a page draws its picture too. The roster slice can not name `find_page_file`, because the file-format slice depends on the roster slice (`test/platform/PlatformSuite.jl:62-63`, `:82-84`). `_decode_roster_picture` goes. Before the pixels come, the cell shows a box 160 by 120 px. | With a page: yes, when the table holds its records (G5). With a bare `ImageFile`: no. |
| The picture of a conversation | `WidgetLabel(image)` draws the `ImageFile` of the part, at most `height` high in its shape. Before the pixels come, it is a box `4 * height ÷ 3` by `height`, as for a failed decode now. | No. |
| The text document example | `Image(path)`, with no decode. The example still reads nothing when it is built. | No. |
| The chart comparison of omnet-julia | `Image(path)` in place of its decode. A computation makes it, as now, so it decodes again only when the chart that it shows changes. | No. |
| The saved picture of omnet-julia | Its box takes the natural size of the picture, not `raw`. | No. |
| The icon of a module in omnet-julia | No change. It decodes on the loop and makes no picture document. | No. |
| The other pictures of omnet-julia | No change. A label draws the picture of an `ImageFile`. | No. |

`decode_image_file!` goes, because it writes pixels into the place of the pixel cell. The draft of
an assistant keeps a part that is an `ImageFile` as it is (`AssistantPicture.jl:75`).

### 3.7 How the assistant reaches the picture

A name reaches the assistant by the line `For the assistant.` at the end of the docstring of its type
or of its generic function. `make_editor_api` reads the marks when it runs. On main, neither
`ImageFile` nor `WidgetTransformPane` has the mark.

A mark on a type also offers each exported subtype, so `ImageFile` is offered as a subtype of
`FileDocument`. Its own docstring still ends with the mark, because its example shows how to show a
picture, and `search_api` reads it (D6). The docstring of `WidgetTransformPane` ends with the mark.
`ImageDocument` and `Image` get none: a mark on `ImageDocument` also offers `ImageMemory` and
`Image`, and the model writes only `ImageFile`. Both docstrings take the form that
`test_assistant_documentation` checks. The window text names only the verbs of its rules, so it does
not change (§1). The orientation guide gets this example after its canvas example
(`orientation.md:177-187`):

```julia
throughput_tab_1 = open_file!("media/throughput-new.png")
throughput_1 = find_open_file_document("media/throughput-new.png")
charts_1 = Dashboard("Charts", [DashboardCard("Throughput", throughput_1)])
open_pane!(charts_1; title = "Charts")
zoom_tab_1 = open_pane!(WidgetTransformPane(throughput_1); title = "Throughput")
show_pane!(zoom_tab_1)
```

The tab, the card and the zoom tab show one page of the file (G4 D2 and D8). So each of them shows
the new picture after a program writes the file again, and the editor reads the file once for the
three. A `Document` that a call returns shows as a live card, so `ImageFile(path)` as the last value
shows the picture in the conversation. That picture does not follow its file. Open question 11 asks
for a way to get the page of a file with no tab.

### 3.8 Where this plan meets G4, G5 and the plan of the save

The plan of G4 asks six properties of the picture (its §6). This plan gives each of them:

1. The file type of a `.png` is registered, so `make_file_tab`, the open of a file and a page make
   the picture: yes (§3.1). Nothing reads the file when the picture is made: no byte, and not its
   time or its size (D12).
2. The pixels are a background cell, and the decode runs in the background work, never in a print,
   a computation or the watcher: yes (§3.2). The watch reads nothing of a picture file (§3.3).
3. `is_editable_file_type` answers `false`: yes (§3.1).
4. A reported change changes the input of the pixel cell, and a report with no change changes no
   cell of the document: yes. The report adds one to `read_count`, and the `apply` compares what
   its work read with what the picture has (§3.3).
5. Each picture has a `BackgroundSource` of its own (§3.2, D10).
6. The rendered Markdown draws the cell of its pixels in a `TextGraphics`: yes. Step 1 makes the
   text span put the pixel cell into its `GraphicsImage`.

The picture of a Markdown image is the editor's one page of that picture file (G4 D5 and D8). The
page of the Markdown file keeps that page in `shown_files`: the page that the editor has open for
the path, or else a new page of `ImageFile(path)`, which reads nothing when it is made.
`open_file_page!(path; editor)` of the plan of the save finds or makes such a page. The picture of a
new page has a source of its own (D10). So a picture that a Markdown page and a tab show is one page, with one watch and one
pixel cell. A page of a picture keeps no hash: a report goes to the picture, and the page reads
nothing (§3.3).

G3 needs G4 step 2 on main, because the watch must only report a change (D12). G3 needs G4 step 1a,
because each place keeps the choice of Ctrl+1 in its view document (D11). G4 step 1a needs G4 step
1, so a picture in a card follows its file when G3 lands. G3 lands before G4 step 5, which draws the
pictures of a Markdown page.

The plan of G5 needs a picture that a record holds and that a `.pred` file saves. The plan of the
save writes `file("…")` for it. A picture in a record follows its file when the record holds the
editor's one page of it and the table holds its records (G5).

The plan of the save, [a-file-saved-alone-names-the-files-that-it-holds.md](a-file-saved-alone-names-the-files-that-it-holds.md),
makes a file saved alone write `file("…")` for each opened file that it holds, and write none of
them (its D0). G3 does not implement the save. Its steps 1 to 4 land before G3, and G3 needs its
steps 1 and 2 to save a picture. Its steps 5 and 6 land after G4 step 2. `file("…")` loads as the
file document (its D1). The open of the saved file gives each held file the editor's one page of
it, through `open_file_page!(path; editor)`, which the owner named for its D7. That function answers
the page that the editor has open, or else makes a new page that reads nothing until a view draws
it, and adds it to the open files of the editor at once (its D6 and its open question 5). For a
picture, that open reads no pixel and no time or size, as its §4.10 asks. A reload of the holder is
a load (its D7). The view draws a held page and a held `ImageFile`: a page draws its file, and the
file draws its picture.

## 4. Decisions

The owner decided D1, D2, D7, D8, D9 and D12. The assistant decided D11 from the owner's G4 D2. D3
follows from D1, D12 and G4 D8. The owner decided D10 on 2026-11-05. The assistant proposed D4, D5, D6 and D13.
A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. A picture is a file that a person does not edit.** The owner decided this on 2026-11-05
  (model B). `ImageFile` is a file document, and `is_editable_file_type` answers `false` for it,
  as it does for the vector file of a simulation (`FileSplice.jl:35-68`). A card, a tab and a row
  of a table hold the opened file. A save writes `file("…")` for it, as a project save does now.
  A file saved alone throws for it now (`FileCut.jl:269-272`, `:293-299`). The owner decided the fix on
  2026-11-05 (option A): a file saved alone writes `file("…")` for each opened file that it holds,
  with the path relative to its own folder, and does not write that file. Edits of the held file
  that are not saved stay until the person saves that file. An open of the saved file opens each
  named file through the opened files of the editor, so a tab and a card share it. This fix is for
  every file kind, not for pictures only. Rejected: option B, a save of the holder as a project,
  which writes each file that it holds. Rejected: model A, a picture that holds its path and is not a file document. It adds a
  second way to follow a file on disk, and it puts a fact of storage into the document, against
  `FileCut.jl:4`. Rejected: a second type for the tab of a picture file, because two names for one
  picture confuse the assistant.
- **D2. A print asks for the pixels, and a task decodes them.** Confirmed by the owner on
  2026-11-05 with model B (G4 D5): the pixels of the picture file document are a background cell.
  A draw on the screen demands them, and the editor reads the demanded pictures on a task after the
  frame. A picture that is not on the screen is not read. Rejected: a read in the acquire. A
  picture in the conversation or in a cell can have no holder, and it would never show. Rejected:
  one source for each editor, because the assistant makes a picture before a holder has it.
- **D3. A picture follows its file through the page of the file.** It follows from D1, D12 and G4
  D8 (decided). The editor's one page of the picture file watches the file, the watch only reports
  a change, and the report adds one to the count of the picture (§3.3, D13). Rejected: a watch of
  the folder of each picture, the first D3, with its fragment `ImageFileWatch.jl`. It is a second
  way to follow a file, and it counts against the limit of 1000 folders of a store. Rejected: a new
  kind of watch. Rejected: the file watcher of today compares the time and the size of a picture
  file, reads them again on its task, and the reload gives them to the picture. D12 replaces it,
  because the watch reads nothing.
- **D4. The size comes from the holder.** The holder gives the slot and the zoom, and the view
  document of each place keeps the choice of Ctrl+1 (D8, D11). Rejected: a field for a size or a
  zoom factor. A tab would have two zooms, and a picture in a card would take the wheel from the
  dashboard.
- **D5. No caption field.** Rejected: a `caption` field, which repeats the title of a card.
- **D6. The type keeps its name `ImageFile`.** "Image" is the word of a Markdown image and of the
  media type `image/png`. The docstring also says "picture", so `search_api` finds either word.
- **D8. Ctrl+1 shows a picture at its natural size.** The owner decided this on 2026-11-05 (open
  question 3, option A): one pixel of the image to one pixel of the screen. The binding belongs to
  the picture view, because only a picture knows its natural size. The fitted view stays the
  default, and Ctrl+0 goes back to it. Rejected: no key, so that the person zooms with Ctrl+wheel.
- **D7. This plan starts after steps 1 to 4 of `reflection-api` land, and lands before step 5 of
  G4.** Steps 1 to 4 landed on main `2bbc18fb5` (omnet-julia `991a89b4f`) on 2026-11-05, not pushed. The owner decided the order on 2026-11-05: steps 1 to 4 of `reflection-api` land on main first,
  after a rebase, its tests and the approval of the owner. Then this plan starts from main, and a
  name reaches the assistant only by the mark `For the assistant.` (§3.7).
  Rejected: this plan lands first, before the mark rule is on main.
- **D9. The content of a picture file is its picture, `Image <: ImageDocument`.** The owner decided the
  name on 2026-11-05: the content of a file type is named for what it is, as a `JsonFile` holds a
  `JsonObject`. With D12 a change only adds one to the count of the picture, and its pixel cell reads
  again when the picture is drawn, so the picture is never replaced and needs no rule of
  `replace_wrapped_document!`. `Image` holds the path, `read_count`, the pixel cell, `natural_size`
  and `failure` (§3.2). Rejected: the first proposal of the assistant, a picture that keeps the time
  and the size of its last read and a version, with a `replace_wrapped_document!` that compares them
  at a reload and answers the old picture. D12 replaces it. Rejected: the time and the
  size as the content, and the pixels in a third field of the file, as the tables of
  `LegacyResultFile`. Then `read_document_file` of a picture answers no picture, and a new document
  must hold two numbers, because a history takes only a `Document`. Rejected: a new picture at each
  read. Its pixel cell has no answer, so each rewrite shows the box for a frame or more. A script
  that writes 17 charts at once makes 17 boxes. Rejected: `ImageFile <: ImageDocument` with the trait
  `is_file_document`. The acquire, the watch, the reload and the row of a file take `FileDocument`
  (`FileChangeStore.jl:138`, `:280`; `DocumentFile.jl:442`; `FileToContent.jl:122`).
- **D10. Each picture has a source of its own.** Decided by the owner on 2026-11-05 (open
  question 12, option A). `Image(path)` makes the `BackgroundSource` of the picture, and no maker
  passes one. The pictures that one frame demands decode in parallel, each on a task; 960 decodes
  on 16 tasks gave equal pixels (§3.2). The rule has no order: a picture that a tab, a Markdown page
  or the assistant made first reads in the same way. Rejected: a keyword `source` on
  `open_file_page!`, `ImageFile` and `Image`, which a holder such as a Markdown page passes. A page
  that a tab made earlier keeps its own source, so the batch depends on which holder came first.
  Rejected: one source for the editor. One task then decodes every picture of a frame one after
  another, which is slower for a dashboard of 17 charts. Rejected: a picture with no source until a
  holder gives one. The open path and the assistant make a picture before a holder has it.
- **D11. Each place keeps its choice of Ctrl+1 in its view document.** Decided by the assistant on
  2026-11-05 from the owner's G4 D2: the state of a view belongs to each place that shows a page.
  The view document of a place (`make_document_view`, G4 step 1a) keeps the choice, as it keeps
  the scroll place. A write of it adds no undo step, and a save does not write it. Ctrl+1 in a tab
  leaves a card of the same file at the fit. The binding stays in the picture view (D8), which
  takes the choice from the view document of its place through a context property (§3.4).
  Rejected: the choice as view state of the picture, shared by every place that shows one opened
  file. Rejected: a field of the holder.

- **D12. The watch only reports a change.** Decided by the owner on 2026-11-05 with G4 D4: every
  outside read is a background cell, and the watch reads no text and computes no hash for any file
  kind. Each change that the watch reports adds one to a count of changes. The input of the pixel
  cell is the path and that count, so only a picture on the screen is read again after a change.
  §3.3 (the rule of time and size for each new read) and step 1 must follow this: the time and the
  size are no longer the input of the cell. Property 4 of G4 (an unchanged report changes nothing)
  then holds in the `apply`, which compares what it read with what the picture has.
- **D13. The page gives a change of its file to the picture.** Proposed by the assistant. Where G4
  adds one to the count of changes of a page, a page whose content follows its file by itself adds
  one to the count of that content instead. `receive_file_change!` gets a method for `Image`, and
  its default for any other content answers `false`, so the page reads its file as G4 D4 says. The
  contract of a function that exists widens, and no function, event or channel is new (§3.3).
  Rejected: the page reads the picture file again and loads a new picture, because then the
  picture is replaced, against D9. Rejected: the picture reads a count that its page keeps, because
  a picture with no page then has no count.

## 5. Steps

Each step runs in a worktree and ends with one commit in each repository that it changes.
`workspace/bin/bounded-run` runs each test: a test under `test/platform/` in
`package/ProjecturedPlatformTest`, any other in `environment/all`. No step changes a file under
`source/kernel/`, so no step changes a sealed file.

The dependencies: step 1 needs no other plan. Step 2 needs steps 1 and 2 of the plan of the save
and G4 step 2 on main. Step 3 needs step 2 and G4 step 1a on main. Step 4 needs step 2. Step 5
needs steps 1 to 4.

- [ ] **1. A picture reads its pixels on a task, and only a paint reads them.** `Image` in
      `Image.jl`: its fields, which hold the path, `read_count`, the pixel cell, `natural_size` and `failure`,
      its source, its work, its `apply` and `pred_arguments`. A label and a text span draw an `Image`
      from `natural_size` and `failure` in the print, and put its pixel cell into the
      `GraphicsImage` (`WidgetToGraphics.jl`, `TextToGraphics.jl`). An `ImageFile` and an
      `ImageMemory` still draw from `raw` until step 2. A section "A picture of a file" in
      `style.md`. Test: the new `test_image()` in `test/platform/document/ImageTest.jl`, with a test
      source whose work counts its runs. The make of a picture and a print of a label and of a
      `TextGraphics` with it run no work. A read of the `data` of its `GraphicsImage` in a frame of
      an editor records a demand, and the work runs once after that frame. With no editor,
      `wait_for_cell!` answers the pixels of the test work. For a path that does not exist, the real
      work answers the exception as the value, and the `apply` writes it into `failure`.
      `natural_size` is `nothing` before the first answer. One more `read_count` gives the cell a
      new input, and the next read in a frame runs the work again. An answer of the same natural
      size writes no cell, and an answer of another size writes `natural_size`. Then
      `test_widget_button_behavior()` and `test_inline_image_caret()`. With SDL, the new
      `test_image_file_read()` in `test/backend/sdl/projection/ImageFileReadTest.jl`: a PNG that
      `write_image` wrote decodes on a task of the default pool and gives its size, and a file of
      another size at the same path gives the new size after one more `read_count`.
- [ ] **2. A picture file is a file that a person does not edit, and its page gives it each
      change.** `ImageFile <: FileDocument` with `ImageFile(path)`, `is_editable_file_type`,
      `read_file_content` and `get_file_domain` in `Image.jl`. `set_cell_computation!(::ImageFile)`
      goes. `StyleModule.jl` registers the five extensions. `receive_file_change!` gets its method
      for `Image` and its default for any other content, and the page gives a change to the content
      of its file first (`FilePage.jl`, D13). A label and a text span draw the picture of an
      `ImageFile` and of its page. The cell of a roster draws a picture for a value for which
      `get_edited_document` answers an `ImageDocument`, so the page of a picture file draws its
      picture there (`RosterToGraphics.jl:138-144`; the plan of the save, its open question 10).
      `decode_image_file!` goes from `SdlBackend.jl`. The holders of §3.6 drop their decode:
      `MarkdownToSyntax.jl`, `BookToSyntax.jl`, `RstToSyntax.jl`, `RosterToGraphics.jl`,
      `ConversationToWidget.jl` and `example/platform/TextDocumentExample.jl`. `AssistantPicture.jl`
      keeps a picture file (`:75`). In omnet-julia, `LegacyChartComparisonToWidget.jl` and
      `LegacyStoreEntryToWidget.jl` follow in a commit that lands with this one. Update `style.md`,
      the table at the head of `DocumentFile.jl`, `fileformat.md` and `filechange.md`. Test:
      `test_image()`, new sets. `read_document_file("a.png")` answers an `Image`, and the test source
      runs no work. `make_file_tab("a.png")` answers an `ImageFile`. In an editor with a
      `FileChangeStore`, `OpenFileOperation` of a `.png` opens a tab of the page of the file, and the
      page watches the file. A new file at the path and a drain add one to `read_count`, the file
      holds the same picture (`===`), and the page reads nothing. F5 on the page adds one to
      `read_count` too. Then `test_roster_table()`, with a new set: a record that holds the page of a
      picture file shows a picture cell, as a record with its `ImageFile` does. Then
      `test_task_views()`, `test_external_agent_turn()`, `test_markdown_image_leaf()`,
      `test_file_change_store()` and `test_explorer()`. `test_book()` and `test_rst()` follow,
      because no narrower test prints their pictures. In omnet-julia:
      `test_chart_comparison_document()`, `test_legacy_store_entry_pages()`,
      `test_simulation_embed_in_page()` and `Pkg.precompile()`.
- [ ] **3. The picture is a view.** `ImageToWidget` in `source/platform/natural/ImageToWidget.jl`,
      its row in `NaturalProjection.jl`, and Ctrl+1 and Ctrl+0. The choice of D11 is a field of the
      view document of a page of G4 step 1a, in `source/platform/fileformat/`. The view of the page
      gives that view document to the print of its file as a context property (§3.4). Update the
      row list of `natural.md` and the view of a page in `fileformat.md`. Test: the new
      `test_image_to_widget()` in `test/platform/projection/ImageToWidgetTest.jl`, with a test
      source that answers pixels of 400 by 300. Before the answer, a slot 200 wide draws a box 200
      by 150 with the path. After it, a slot 200 wide draws 200 by 150. A slot 800 wide draws 400 by
      300, and so does a scroll pane that grows on both axes. Three pictures in a `HorizontalLayout`
      600 wide with `Fill` draw 200 wide each. A `DashboardCard` draws the picture at the width of
      the card. A failed read draws the path and the reason. Ctrl+1 in a tab 200 wide draws the
      picture 400 by 300, no history records it, and a card of the same page stays at 200 by 150.
      Ctrl+0 draws it 200 by 150 again. At the fit, the reader returns `nothing` for Ctrl+0. A
      picture in a label returns `nothing` for Ctrl+1. Then `test_file_tab()` and
      `test_explorer()`.
- [ ] **4. The assistant reaches the picture, and a zoom tab follows its file.**
      `get_edited_field(::WidgetTransformPane) = :content` in `WidgetDocument.jl`, the mark at the
      end of the docstrings of `ImageFile` and `WidgetTransformPane`, and the example of §3.7 in
      `documentation/guide/orientation.md`. Update the transform pane in `widget.md`. Test:
      `test_image()`, a new set: a tab of `WidgetTransformPane(page)`, with the page of `p`, holds
      that page, and the page watches `p`. The close of the tab releases the page, and the watch
      stops when no other holder holds it. `test_assistant_documentation()`, and
      `test_assistant_verbs()` with a new set beside "tell: a drawing, a chart and a graph draw in a
      tab" (`AssistantVerbsTest.jl:279`). In it the code tool opens a picture with `open_file!`, and
      puts its page in a card and in a `WidgetTransformPane`. Then
      `test_referenced_document_editor()`, because a new docstring can move the rank of
      `search_api`. Compare each count with a run on `main`. In omnet-julia,
      `test_simulation_embed_in_page()`, because a tab now holds the content of a transform pane.
- [ ] **5. The live check in `omnet_ide`.** Through its MCP connection, the assistant opens three
      charts with `open_file!`, fills a dashboard with their pages, opens the page of one in a
      `WidgetTransformPane`, and returns one `ImageFile` from a call. A script writes a new PNG at
      the path of the zoomed chart. `take_picture` must show the new picture in its file tab, in its
      card and in its zoom tab. The store of the background work (`get_background_work_store`) must
      record one read of that file for the change, because the three places show one page. Ctrl+1
      in the file tab must show the natural size while the card stays at the fit. Ctrl+0 must fit it
      again, and Ctrl+wheel must zoom the transform tab. Then `Pkg.precompile()` runs in
      omnet-julia, and this plan moves to `plan/done/`.

## 6. Risks

- **A plain layout reads each of its pictures.** The backend skips an image outside the clip only in
  a list canvas and in the lines of a text (§1). A picture in a card of a dashboard, which a
  `GridLayout` places, is read at the first paint, also off the screen. A dashboard of 17 charts
  thus decodes all 17 at its open, off the loop and in parallel. The test of step 1 asserts the
  laziness in a list canvas only. The owner accepts these reads until the plan of the layouts lands
  (open question 9).
- **The web backend reads each picture.** At the first paint it sends the whole drawing of a window
  to the browser, with the pixels of each picture (`WebBackend.jl:1089`, `:303-305`). So in the web
  backend each picture of a window is decoded, also off the screen. The owner accepts this for now
  (the plan of the layouts, its D11).
- **A print with no editor draws the box.** A script or a test must call `wait_for_cell!` on the
  pixel cell before it writes an image. The tests of steps 1 and 2 show which prints have no editor.
- **SDL decodes on many tasks at once.** The check of §1 found equal pixels on 8 threads with no
  video. The loaders start at the first decode, on whichever task comes first.
  `test_image_file_read()` and step 5 show the decode beside a window.
- **The choice of Ctrl+1 waits for G4 step 1a** (D11). Step 3 starts only when the view document of
  a page is on main.
- **A bare picture does not follow its file** (G4 D8). A card, a label or a transform pane that
  holds an `ImageFile` with no page shows the file as it is at its first paint. The assistant gets
  the page of a file only after `open_file!`, which also opens a tab (open question 11).
- **Each new watch reads a picture on the screen again.** The watch reports a change at its start
  (G4 D4), so a picture on the screen decodes once more at each acquire of its page, such as a
  visit of the Back list. The `apply` writes no cell for an equal answer.
- **A decode can meet a file that a program still writes.** The work then answers the failure, and
  the view draws the reason until the next report. G4 step 2 decides whether the watch reports a
  change only when the file is whole, as `_wait_for_settled_file` waits now
  (`FileChangeStore.jl:477`).
- **A transform pane around a page draws the page with no view of it.** G4 step 1a moves the scroll
  pane and the band from the page into its view (G4 D2). The zoom tab of §3.7 then needs a row that
  draws a page with no view. Step 4 shows whether G4 step 1a keeps one.
- **A picture path that does not exist opens as `DocumentNothing()`**, the seed of an extension
  with no seed (§1). The page of that file reads the file when a program writes it, and loads a
  picture once. From then on, D13 holds.
- **A computation that makes a picture makes a new pixel cell at each run.** The chart comparison of
  omnet-julia and the facets of a roster do so. They decode again only when that computation runs
  again. A computation that read the pixel cell of a picture that it makes would ask at each answer;
  the docstring says so.
- **omnet-julia breaks between the two commits of step 2**, because its two holders read `raw` of an
  `ImageFile`. Both commits must land on main together. `Pkg.precompile()` in omnet-julia shows it.
- **A tab holds the content of a transform pane.** omnet-julia shows a network in one
  (`source/presentation/page/EmbedPanes.jl:445`), so `get_edited_document` of that tab can change.
  Step 4 runs its test.
- **F5 on the page of a picture reads the whole file as text today** to hash it
  (`LoadFilePageOperation`, `FilePage.jl:204-213`). After G4 step 2 and step 2 of this plan, F5
  adds one to `read_count` and reads nothing else.
- **The open of a picture file reads no byte, no time and no size.** `read_document_file` still
  calls `isfile` (`DocumentFile.jl:99`).
- **omnet-julia keeps one decode on the loop:** the icon of a module.
- **Book and RST keep `isfile` in the print** until G4 step 5a (open question 10).
- **The rank of `search_api` can move.** Step 4 runs the tests of the rank.

Not in this plan: a special tab of a picture file (D1), the final image span of Markdown (G4 step
5), the image spans of Book and RST (G4 step 5a), a plain layout that paints only what the screen
shows (open question 9), the icon decode of omnet-julia, and the save of a file alone (its own
plan). A comparison view is G7, and a link to the tab of a picture is G6.

## 7. Open questions for the owner

1. **The tab of a picture file.** Resolved by D1 on 2026-11-05: a picture is a registered file type,
   so the open path of today opens a file tab for it, and G3 adds the type. The question was: a
   press on a `.png` in the Files pane throws. Must G3 or G4 open a picture file in a tab?
2. **The third need of G4.** Answered by the owner on 2026-11-05: the model of G4 (D1, model B).
   The question was: G4 expects the file watcher to read a picture again. Which model must both
   plans use?
3. **A key for the natural size.** Answered by the owner on 2026-11-05: yes, Ctrl+1 (D8). The
   question was: in a tab smaller than the picture, the person zooms to the
   natural size. Must a tab of a picture have a key for it? The assistant recommends no key now.
4. **A picture with no editor.** Resolved by G4 D5 on 2026-11-05: the pixels of a picture are a
   background cell, so a script calls `wait_for_cell!` with `editor = nothing`, as for any
   background cell, and that computes the pixels. The question was: must a read with no editor
   decode at once instead?
5. **The order** (D7). Answered by the owner on 2026-11-05: no, steps 1 to 4 of `reflection-api`
   land first (D7). The question was: can this plan land on `main` before `reflection-api`? The
   assistant recommends yes.
6. **The content of a picture file** (D9). Answered by the owner on 2026-11-05: the name is `Image`
   (D9). The reload half no longer applies, because a change only adds one to the count of the picture
   (D12) and the picture is never replaced. The question was: is `ImageFileContent` the right name for the picture that
   a picture file holds, and can it keep itself at a reload through `replace_wrapped_document!`? The
   assistant recommends both.
7. **The choice of Ctrl+1** (D11). Decided by the assistant on 2026-11-05 from the owner's G4 D2
   (the state of a view belongs to each place): each place keeps its own choice, in its view
   document (`make_document_view`), as it keeps its scroll place. D11 records it. The
   question was: Ctrl+1 in a tab also changes a card that shows the same opened
   file. Is that acceptable, or must each place keep its own choice, in a view document of each
   place (`make_document_view`), as G4 D2 does for a page? The assistant recommends to accept it
   for G3, because a card gives its picture no room for the natural size.
8. **A plan in omnet-julia.** Decided by the assistant on 2026-11-05, as for G8 and G9: step 2
   changes the two files of omnet-julia in the same landing, and no sibling plan is written. The
   reflection plan also spans both repositories. The question was: step 2 changes two files of omnet-julia. The rules ask for one plan in
   each repository that a change touches. Must a small plan in omnet-julia name this one, or can
   step 2 carry the two files? The assistant recommends a small plan in omnet-julia.
9. **Pictures that a plain layout holds.** Answered by the owner on 2026-11-05: option A, a plan of
   its own after G3 makes each layout tell which of its elements meet the visible area, so the backend
   paints only those. G3 accepts the extra reads until it lands. The question was: the backend reads every image of a horizontal, vertical,
   grid, flow or stack layout, also outside the clip (§1). So a card of a dashboard off the screen
   reads its picture at the first paint. Must those layouts skip what lies outside the clip, as a
   list does? That changes the backend and the layouts, outside G3. The assistant recommends a plan
   of its own after G3, and accepts the cost in G3.
10. **Book and RST.** Decided by the assistant on 2026-11-05: G4 step 5a gives Book and RST the
    model of G4 step 5, from the owner's rule that a printer reads no disk. The question was: their image spans keep `isfile` in the print after G3. Must a plan give them
    the model of G4 step 5? The assistant recommends a plan after G4 step 5.
11. **The page of a file with no tab, for the assistant.** Answered by the owner on 2026-11-05: the
    function of the save plan becomes `open_file_page!(path; editor)` and carries the mark, so the
    assistant gets the page with no tab and puts it in a card with `insert_elements!` or in a tab
    with `open_pane!`. The question was: A card and a zoom tab follow a picture
    only when they hold the editor's one page of its file (G4 D8). The assistant gets that page only
    with `find_open_file_document` after `open_file!`, and `open_file!` also opens a tab. So a
    dashboard of 17 charts that follow their files opens 17 tabs. Must the assistant get the
    editor's one page of a path with no tab? The assistant recommends the mark `For the
    assistant.` on `open_file_page!(path; editor)` of the plan of the save, which finds that page
    or makes an unread one and adds it to the open files of the editor.
12. **The source of a new page of a picture.** Answered by the owner on 2026-11-05: option A, each
    picture has a source of its own (D10). The question was: a Markdown page has one `BackgroundSource` for its
    pictures (D10, G4 property 5). `open_file_page!(path; editor)` takes no source, so a new page
    that it makes for a picture has a source of its own, and the pictures of one Markdown page read
    on many tasks. Must `open_file_page!` take a keyword `source` that a new page of a picture
    takes, or does G4 accept a source for each picture? The assistant recommends the keyword: the
    default is a source of its own, and a page that is open already keeps its source.
