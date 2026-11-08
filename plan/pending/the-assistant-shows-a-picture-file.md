# The assistant shows a picture file

> **Kind:** plan · **Status:** a plan, written 2026-11-05, revised on 2026-11-08 at `main`
> `aaa2ecf94` to G4 D10, G4 D14 and the file document. Nothing is built.
> · **Sibling plans:** G4 [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md),
> G5 [the-assistant-fills-a-live-table.md](the-assistant-fills-a-live-table.md), and the plan of the
> save [a-file-saved-alone-names-the-files-that-it-holds.md](a-file-saved-alone-names-the-files-that-it-holds.md)
> · **Needs:** G4 steps 1 to 3 and steps 1 to 5 of the plan of the save, all on main. No step needs
> the plan of G4 open question 10 (§3.8) · **Stands on:** [style.md](../../documentation/package/platform/style/style.md),
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

The assistant checked each row at `main` `aaa2ecf94` on 2026-11-08, and the rows of omnet-julia
at its `main` `ced3d0cdb`. The inventory of `SEALING.md` covers `source/kernel/` only, and no step
of this plan changes a file there.

| Thing | Where | State |
| --- | --- | --- |
| The picture document | `ImageFile(filename)`, `source/platform/style/Image.jl:20-34`; `set_cell_computation!`, `:50` | `ImageFile <: ImageDocument <: Document`. Two fields: the path, and `raw`, the pixels or `nothing`. The constructor of one argument decodes nothing. Its docstring has no line "For the assistant.". The holders set a computation on `getfield(image, :raw)` (the next rows), and no caller uses `set_cell_computation!(::ImageFile, f)`. |
| The file document | `FileDocument`, `source/platform/serialization/FileProject.jl:40-66`; `FileDiskState`, `:176-181`; `get_view_state_fields`, `:194-195`; `is_editable_file_type`, `FileSplice.jl:35-45`; `read_file_content`, `:47-68`; `_read_set_file`, `:72-74` | Each file type has the fields `filename`, `content` and `disk::FileDiskState`, and the docstring of `FileDocument` has the mark (`:64`). `disk` is view state: a save writes none of it, and a walk does not enter it. A type that a person does not edit is read with `read_file_content`. omnet-julia has one: `LegacyResultFile` (`source/legacy/result/presentation/LegacyResultFile.jl:177-202`), with a field `tables` that follows the cell of the content. The trait `is_file_document` (`FileProject.jl:68-84`) is the other way to be a file, and no type of `source/` uses it. |
| Six decodes on the loop | `MarkdownToSyntax.jl:481-496`, `BookToSyntax.jl:566-588`, `RstToSyntax.jl:1236-1251`, `RosterToGraphics.jl:146-159`, `ConversationToWidget.jl:366-382`, `example/platform/TextDocumentExample.jl:49-60` | Markdown, Book, RST, the roster and the example set a computation on `raw` that calls `decode_image` (`source/kernel/backend/BackendInterface.jl:214-220`). The conversation calls `decode_image` in the print itself (`:369`), also for a part of the draft (`ConversationEditor.jl:638`). Markdown, Book and RST also call `isfile` in the print (`MarkdownToSyntax.jl:485`, `BookToSyntax.jl:577`, `RstToSyntax.jl:1237`), and each makes its picture at each print of its node (`MarkdownToSyntax.jl:514`, `BookToSyntax.jl:602`, `RstToSyntax.jl:1260`, `:1307`). |
| The decodes and the pictures of omnet-julia | `source/legacy/result/presentation/LegacyChartComparisonToWidget.jl:44-53`, `source/ide/LegacyStoreEntryToWidget.jl:47-66`, `source/presentation/module/ModuleAppearanceToGraphics.jl:191-208`; `SimulationEmbedToWidget.jl:1045`, `LegacyChartBaseline.jl:52`, `LegacyChartTestTask.jl:563` | The first two set a decode computation on `getfield(image, :raw)` of an `ImageFile`, and the second reads `picture.raw` for its box (`:62-63`). The third decodes the icon of a module in a computation and makes no `ImageFile`. The last three make an `ImageFile(path)`: a label holds one, and a facet and a task record answer one. |
| The decode of the backend | `decode_sdl_image`, `SdlBackend.jl:5932-5958`; `decode_image`, `:5975`; `decode_image_file!`, `:5961-5972` | `IMG_Load` and `SDL_ConvertSurfaceFormat` need no video. No code calls `IMG_Init`, so the loaders start at the first decode. A check on 2026-11-05 ran 960 decodes of a PNG, a JPEG and a BMP on 16 tasks of the default pool, on 8 threads, started together and with no video. Each answer was equal to a decode on the main task. `decode_image_file!` writes pixels into `raw`, and nothing calls it. |
| The draw of the pixels | `_image_payload`, `_content_size`, `_push_content!`, `WidgetToGraphics.jl:1248-1302`; `_extract_image_data`, `TextToGraphics.jl:1733-1737`; `_graphics_span_element`, `:1757-1764`; `GraphicsImage`, `GraphicsDocument.jl:787-800` | A label and a text span read `raw` in the print and put the value into a `GraphicsImage`. A label checks `content isa ImageDocument` (`WidgetToGraphics.jl:1266`, `:1291`). It draws the pixels at their natural size, or smaller in their shape to fit the maximum of its slot (`_fit_image_size`, `:1276-1284`). With no pixels it draws a box. |
| The paint of the backend | `_render_canvas!`, `SdlBackend.jl:2034-2101`; `_render_image!`, `:1988-2005`; `_record_painted_element!`, `:2450-2462`; `_compute_first_drawn_index`, `:2105-2107`; `compute_first_visible_index`, `GraphicsDocument.jl:1092-1099` | The render and the dirty walk read the `data` of an image when they visit it. They skip the elements outside the clip only in a canvas with `layout_vertical` or `layout_horizontal` and no overlap: the lines of a text (`TextToGraphics.jl:696`) and the list layouts (`LayoutList.jl:144`, `GridList.jl:146`). The canvases of `HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout` and `StackLayout` have `layout_none` (`LayoutToGraphics.jl:1014`, `:1337`, `:1842`, `:2062`, `:2227`), so the render and the walk visit each of their elements, also outside the clip. The paint runs in the print stage, with the editor of the evaluation, before `start_background_cell_work!` (`EditorLoop.jl:113-122`, `ReadEvaluatePrint.jl:164`). |
| A picture in a tab or a card | the renderer table, `NaturalProjection.jl:132-240`; `FileToContent`, `FileToContent.jl:60-73` | No row names `ImageDocument`. A file document draws its content through the recursion. An `ImageFile` falls to the reflection row and draws as its fields. |
| A picture in a cell | `make_roster_value_cell`, `RosterToGraphics.jl:122-144`; `WidgetTheme.jl:223-224` | A cell of a roster or of a task table shows an `ImageFile` at most 120 px high. |
| Zoom and pan of any content | `WidgetTransformPane`, `WidgetDocument.jl:1640-1688`; its wheel, `WidgetToGraphics.jl:7587-7608`; its keys, `:7653-7667` | Ctrl+wheel zooms about the pointer, the wheel pans, and Ctrl+0 resets the zoom when it is not reset. The keys come after the content, so a key that the content reads first does not reach the zoom. Its docstring has no mark, and `WidgetDocument` has none (`WidgetDocument.jl:5`). It has no `get_edited_field`, so a tab does not hold its content: a tab holds each layer that `get_edited_field` or `get_wrapped_document` names (`PaneSurgery.jl:574-588`, `PaneDocument.jl:381-402`). `WidgetScrollPane` has the mark and the field (`WidgetDocument.jl:1590`, `:4047`). The window binds Ctrl+0 too (`AppearanceDocument.jl:41`), and nothing binds Ctrl+1. |
| A read off the loop | `BackgroundSource`, `BackgroundCells.jl:8-35`; `make_background_cell`, `:181-232`; `wait_for_cell!`, `:404-440` | A read records a demand and never waits. A second read in the same frame records no second demand. After the print of a frame, the editor runs the work of each source on a task of the default pool (`:310-334`, `BackgroundWork.jl:89-101`). `apply` stores an answer in the document by an operation. With no editor, `wait_for_cell!` computes the value on the task that calls it. |
| A holder that counts its reads | `_make_unread_folder`, `FileSystemDocument.jl:370-391` | The input of the listing of a folder is the path and a read count (`:379-382`), and a change of the folder adds one to the count (`:622`). |
| The watch and the read of a file | `acquire_document!(editor, ::FileDocument)`, `FileChangeStore.jl:255-262`; `receive_file_change!`, `DocumentFile.jl:765-786`; `_read_file_text_answer`, `:800-811`; `_make_file_text_cell`, `:821-830`; `demand_file_text`, `:854-860`; `ApplyFileTextOperation`, `:891-925`; `ReloadFileOperation`, `:564-593` | A held file document watches its file (`watch_document_file!`, `FileChangeStore.jl:113-133`), is the receiver of its watch, and is in the open files of the editor (`add_open_file!`, `OpenFileList.jl:182-187`). A file that changed while it was not held counts a change at its acquire (`is_file_stale`, `DocumentFile.jl:869-873`). The watcher compares the time and the size of a file and notes its path (`_mark_changed_files!`, `FileChangeStore.jl:373-389`). The drain calls `receive_file_change!` (`:416`), and a file adds one to `read_count` of its disk state. Only the view of a file asks for the read (`FileViewToWidget.jl:72`): then a task waits until the file is whole and reads it. For a type that a person does not edit the read takes the hash of the time and the size, never of the text, and the content from `read_file_content_again` (`:645-648`). `ApplyFileTextOperation` changes nothing for an equal hash, and else loads a file that a person does not edit. The load gives the new content to the wrapper with `replace_wrapped_document!` (`:579`), and a history gives it to the document that it holds first (`UndoDocument.jl:118-122`). F5 with no content hashes the whole text of the file (`:580-583`), also for a type that a person does not edit. |
| A file document in a document | `_cut_copy`, `FileCut.jl:289-305`; `_make_held_file_leaf`, `:322-328`; `find_held_file`, `:129`; `splice_held_files!`, `FileSplice.jl:299`; `_splice_open_files`, `DocumentFile.jl:598-602`; `open_file_document!`, `OpenFileList.jl:119-148`, `FileSystemDocument.jl:265-272`; `make_unread_file`, `DocumentFile.jl:205-215` | A file saved alone writes `file("…")` for a file document that it holds. A load in an editor gives each `file("…")` the file document that the editor holds open for the path, or a new one that reads nothing, which `open_file_document!` adds to the open files at once. A file that reads nothing holds the seed of its extension until a view of it is drawn. |
| The read of a file by its extension | `read_document_file`, `DocumentFile.jl:96-104`; `_read_registered_file`, `:107-111`; the table at `:1-25`; `make_file_tab`, `:165-182`; `_record_read_file_hash!`, `:185-193` | For a registered type, `read_document_file` answers the content of the file, not the file document. A path that does not exist gives the seed of its extension, and `DocumentNothing()` for an extension with no seed (`:99`, `:37`). `make_file_tab` puts the content into the file document of the extension, and keeps the time and the size of the file. It keeps the hash of the text only for a type that a person edits. The open wraps the content in a history (`_make_opened_file`, `FileSystemDocument.jl:245-256`), and a history takes only a `Document` (`UndoDocument.jl:91`). The registered extensions are `""`, `.txt`, `.pred` (`FileProject.jl:690-692`) and those of the domains and of the language server. A `.png` has none. |
| A picture file in the Files pane | `OpenFileOperation`, `OpenFileOperation.jl:23`; its evaluation, `FileSystemDocument.jl:223-243`; `get_file_document_type`, `FileProject.jl:255-261` | Return on `chart.png` throws "no file document registered for extension .png". No tab opens. A file of the Files tree reads its file the same way (`FileSystemDocument.jl:66-91`). |
| The view of a file and a dashboard | `FileView`, `FileView.jl:24-55`; `make_document_view(::FileDocument)`, `:46-47`; `make_file_view`, `:44`; `acquire_document!(editor, ::Dashboard)`, `Dashboard.jl:135-146`; `DashboardCard`, `:26-33` | Each place that shows a file shows its own `FileView(file, scroll)`: a scroll pane that grows on its height, and fits the width of the place. A view holds its file, and answers `find_held_file` with it. A tab shows a view (`_make_opened_tab_content`, `FileSystemDocument.jl:277`). A card keeps the view of its content in `content_view`, and the dashboard holds the view of each card. `FileViewToWidget` draws the band, or the row "<name> · reading" of a file that reads nothing yet, above the scroll pane. A card takes any document. |
| The mark | `ASSISTANT_MARK`, `source/kernel/tool/AssistantMark.jl:15`; `collect_marked_api`, `:48-65`; `make_editor_api`, `Application.jl:345-362` | `make_editor_api` collects the marked names of the loaded modules, and no list is kept by hand. A mark on a type also offers each exported subtype. `ImageFile`, `ImageDocument`, `WidgetTransformPane` and `decode_image` have no mark. `GraphicsImage` (`GraphicsDocument.jl:785`), `WidgetScrollPane` (`WidgetDocument.jl:1590`), `FileDocument` (`FileProject.jl:64`), `open_file!` (`FileSystemDocument.jl:314`), `find_open_file_document` (`OpenFileList.jl:106`) and `open_file_document!` (`OpenFileList.jl:141`) have it. |
| The window text and the orientation guide | `EDITOR_SYSTEM`, `Application.jl:364-421`; `APPLICATION_SYSTEM`, `:418-450`; `documentation/guide/orientation.md:156-254`; `test_assistant_documentation`, `AssistantVerbsTest.jl:365-483` | The window text names only the verbs that its rules need. It names `open_file!` and `read_document_file` to read a file (`Application.jl:406-407`), and it shows no canvas. The orientation guide shows a canvas (`orientation.md:177-187`), a chart and a graph (`:189-197`) in a tab, and `open_file!` in "Work with files" (`:240-254`). The test fails for a name of the guide that no model can write (`AssistantVerbsTest.jl:475-480`). |

## 2. What the code lacks

1. **A picture is not a file.** No file type reads a `.png`, so the open of a picture throws, and no
   file document of a picture can watch its file.
2. **A picture has no view.** An `ImageFile` in a tab or a card draws as its fields.
3. **The print reads the pixels.** Six holders decode on the loop. The label and the text span read
   `raw` in the print, so a pixel cell that a print reads asks for every picture that the print
   lays out.
4. **A file that a place draws with no view of its own reads no change.** Only the view of a file
   asks for the read.
5. **The assistant can not write the names.** `ImageFile` and `WidgetTransformPane` have no mark,
   and a tab does not hold what a transform pane holds.

## 3. Design

### 3.1 A picture file is a file that a person does not edit

`ImageFile` is a file document: `ImageFile <: FileDocument`, with the fields `filename`, `content`
and `disk` of every file type (D1). `is_editable_file_type` answers `false` for it, as for the
result files of omnet-julia. So Ctrl+S answers nothing (`DocumentFile.jl:664`), and the decoration
says "read only" (`:457`). The content is the picture that the file holds: a new document `Image <:
ImageDocument` (D9). So `ImageDocument` keeps the pictures that draw, and the file keeps the path
and its state against the disk.

The style slice registers the file type for `.png`, `.jpg`, `.jpeg`, `.bmp` and `.gif`. The slice
depends on the serialization slice already (`test/platform/PlatformSuite.jl:35`), so no slice edge
is new. Then the open of today works for a picture with no change. `read_document_file` answers
the picture, `make_file_tab` answers the `ImageFile` that holds it, and Return in the Files pane
opens a tab of the view of the file. A file of the Files tree shows its picture in the same way.
G3 adds no special tab.

`read_file_content(::Type{<:ImageFile}, path)` reads nothing of the file: no byte, and not its time
or its size (D12). It answers `Image(path)`, a picture that is not read yet. `ImageFile(path)`
reads nothing too. `make_file_tab` keeps the time and the size of the file, as for every file type,
and reads no byte of a picture. A history of the open wraps the picture, as it wraps any content,
and gets no step.

The editor keeps one file document for each path. `find_open_file_document(path)` answers it, and
`open_file_document!(path)` answers it or a new one that reads nothing (`make_unread_file`). So a
tab, a card and a zoom tab of one picture share one file document, one watch and one read. A new
picture file that reads nothing holds `DocumentNothing()`, the seed of an extension with no seed,
until its first draw reads it (§3.3). A held picture file is in the open files of the editor, as
every held file is, so the page "Open files" lists it with the state "read only". `ImageFile(path)`
makes a new document that no other place shares, so the docstring of `ImageFile` sends a holder to
`open_file_document!` (D6).

A file saved alone writes `file("…")` for a picture file that it holds, with the path relative to
the folder of the saved file, and does not write the picture (the plan of the save, its D0). Its
load gives each `file("…")` the editor's one file document of the path, or a new one that reads
nothing (`splice_held_files!`, `open_file_document!`; its D1, D6 and D7). In a `.pred` file, an
`Image` that a document holds with no file writes only its path.

### 3.2 The picture reads its pixels on a task, and only a paint asks for them

The pixels are a background cell (D2). Its input is the path and the count of changes of the
picture, `read_count` (D12). A folder reads its listing with the same kind of input
(`FileSystemDocument.jl:379-382`). The work decodes the file and answers the pixels, which carry
their natural size. It reads no time and no size of the file. It answers the exception of a file
that does not exist or does not decode as a value, so one bad file fails no other picture of the
batch, and a read of the cell never throws. Its `apply` writes the natural size of the pixels into
the plain cell `natural_size` of the picture, or the exception into the plain cell `failure`, as the
`apply` of a folder writes its entries. It writes no cell whose value stays the same (§3.3). The
write is view state, so undo records none.

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
a source, so `ImageFile(path)`, `Image(path)` and `open_file_document!(path; editor)` take no
keyword `source`. The pictures that one frame demands thus decode in parallel, each on a task of the
default pool. This holds for the pictures of a Markdown page and of a dashboard alike, and it does
not depend on which holder made a picture first.

A script with no editor gets the pixels with `wait_for_cell!(cell; editor = nothing)`, as for any
background cell. A holder must make a picture where it builds a document. A computation that makes
a picture makes a new pixel cell at each run, so it must not read that pixel cell.

### 3.3 The picture follows its file through its file document

A picture follows its file while a place holds the file document of the picture (D3). The file
document watches its file while it is held, and it is the receiver of the watch (G4 D10). On main a
tab and a card hold it: a tab holds each layer of what it shows, and a dashboard holds the view of
each card. Step 4 makes a transform pane a layer of a tab (`get_edited_field(::WidgetTransformPane)
= :content`, as for a scroll pane), so a zoom tab holds the file too. The image of a Markdown page
holds its picture after G4 step 5 (§3.8). A label, a cell of a roster, the conversation and a
transform pane outside a tab do not hold the file. They show the file as it is at their first paint.

A change goes to the picture in five steps. The watch, the drain and the read have no code for
pictures (D13):

1. The watch reports a change. The file adds one to `read_count` of its disk state
   (`receive_file_change!`). A file that is held again after a change counts it at its acquire.
2. The print of the file asks for the read when a change is not read yet (D14). After the frame a
   task reads the file as for every type that a person does not edit: it waits until the file is
   whole, takes the hash of the time and the size, and answers `read_file_content(ImageFile,
   path)`, a new `Image` that reads nothing. No byte of the file is read.
3. `ApplyFileTextOperation` compares that hash with the hash of the file. An equal hash changes
   nothing, so a report with no change changes no cell of the document (G4 property 4). Else the
   file loads, because a person does not edit it (`ReloadFileOperation`).
4. The load gives the new picture to the history, and the history gives it to the picture that it
   holds first. `replace_wrapped_document!(::Image, document)` keeps the old picture when the new
   one is a picture of the same path: it adds one to the `read_count` of the old picture and
   answers the old picture. Nothing reads the pixel cell of the new picture, and the load drops it.
   So the file keeps one picture with its pixels, and the history takes no new document.
5. The pixel cell of the old picture gets a new input. It answers its last pixels until the new ones
   come, and only a picture that the backend paints asks for them again. The `apply` of the answer
   compares the natural size with `natural_size`, and the failure with `failure`. With the same
   values, it writes no cell.

F5 on a picture file loads in the same way: `ReloadFileOperation` reads the file again with
`read_file_content`, which reads nothing, and the old picture adds one to its count. For a type that
a person does not edit, F5 takes the hash of the time and the size, as the read on a task does,
and not the hash of the whole text. So F5 reads no byte of a picture, and no byte of a large result
file of omnet-julia.

G3 adds no watch, no event, no payload and no channel (D3).

### 3.4 The view and the size

The view is a new projection `ImageToWidget` of the natural slice. Its row in the renderer table
names `ImageDocument`, beside `GraphicsDocument` (`NaturalProjection.jl:207`). An `ImageFile` draws
through the row of a file document (`FileToContent`), which prints its content, the picture. A view
of a file (`FileView`) draws its file in its scroll pane. The picture view draws the pixels as a
label draws them. Before the first answer it draws a box with the path. After a failed read it
draws the path and the reason from `failure`. A tab of a picture takes the base name of its file
from `get_document_title(::FileDocument)` (`DocumentFile.jl:252`).

The size comes from the holder, and the view of each place keeps the choice of Ctrl+1 (D4, D8,
D11):

- **Fit.** The picture draws at its natural size, or smaller in its shape to fit the maximum of its
  slot. It never draws larger. A card, a cell and a tab give such a slot. In a view of a file the
  slot has the width of the place and no maximum height (`FileView.jl:46-47`). So the picture fits
  the width, and the place scrolls a taller picture.
- **Natural size.** Ctrl+1 draws the picture at its natural size: one pixel of the image to one
  pixel of the screen. The scroll pane of the view scrolls a picture that is larger than the view,
  on either axis (`WidgetDocument.jl:1537-1539`). Ctrl+0 goes back to the fit, which stays the
  default. Each place keeps the choice in a field of its `FileView` (D11). `FileViewToWidget`
  gives its view to the print of its file as a context property. The picture view takes the choice
  from that property only when that view shows this picture. For Ctrl+1 its reader returns a
  `ReplaceViewStateOperation` that writes the choice, so no history records it. The reader returns
  an operation for Ctrl+1 only at the fit, and for Ctrl+0 only at the natural size. Otherwise it
  returns `nothing`, so Ctrl+0 still reaches a transform pane and the zoom of the window. A picture
  with no view of a file around it, such as a picture in a label, a cell or a zoom tab, stays at
  the fit, and its reader returns `nothing` for both keys.
- **Zoom.** In a `WidgetTransformPane` around a picture file, Ctrl+wheel zooms about the pointer,
  the wheel pans, and Ctrl+0 resets the zoom. The pixels keep their natural resolution.

### 3.5 A caption and pictures side by side

The holder gives the caption: the title of a card or a tab, the alt line of a Markdown image, a
column of a table. A `WidgetLabel` under the picture in a `VerticalLayout` gives a longer one. For
pictures side by side, a `HorizontalLayout` with `Fill` shares gives each picture a slot, and each
picture fits its slot. A comparison view is the gap G7.

### 3.6 The holders of a picture

Each holder stops its decode. A label and a text span draw an `ImageDocument`, and the picture that
`get_edited_document` answers for an `ImageFile`, through its history. A label that holds a picture
file thus draws its picture. Only a holder of the editor's one file document of the picture follows
the file (§3.3).

| Holder | What it holds | Follows its file |
| --- | --- | --- |
| A tab | `open_file!` and `OpenFileOperation` show the view of the editor's one file document of the path (`FileSystemDocument.jl:223-243`, `:277`). | Yes. |
| A card of a dashboard | The file document that `open_file_document!` or `find_open_file_document` answers, or that the load of a saved dashboard gives (the plan of the save, its step 5). The dashboard holds the view of each card. | Yes. |
| A zoom tab | `WidgetTransformPane(file)` in a tab. The tab holds the file through `get_edited_field` (step 4), and the print of the file asks for its read (D14). | Yes. |
| The image span of Markdown | Step 2: it makes `Image(path)` in place of `ImageFile(path)` and its decode, and sizes the `TextGraphics` from `natural_size`. Its `isfile` stays. G4 step 5: the span holds the editor's one file document of its picture, as a tab holds a file, and reads no disk (G4 D14, §3.8). | After G3: no. After G4 step 5: yes. |
| The picture leaf of Book, the picture of RST | The same as Markdown. G4 step 5a gives them the model of G4 step 5 (open question 10). | After G3: no. After G4 step 5a: yes. |
| The cell of a roster | What the record holds: an `ImageFile`, also the editor's file document of a picture, which a record holds after the load of a saved table (the plan of the save, its open question 10). Step 2 makes the cell draw a picture when `get_edited_document` answers an `ImageDocument` for the value. `_decode_roster_picture` goes. Before the pixels come, the cell shows a box 160 by 120 px. | After G3: no. With G5: yes, when the table holds its records and the cell asks for the read of its file (§3.8). |
| The picture of a conversation | `WidgetLabel(image)` draws the picture of the part, at most `height` high in its shape. Before the pixels come, it is a box `4 * height ÷ 3` by `height`, as for a failed decode now. The conversation holds no document. | No. |
| The text document example | `Image(path)`, with no decode. The example still reads nothing when it is built. | No. |
| The chart comparison of omnet-julia | `Image(path)` in place of its decode. A computation makes it, as now, so it decodes again only when the chart that it shows changes. | No. |
| The saved picture of omnet-julia | Its box takes the natural size of the picture, not `raw`. | No. |
| The icon of a module in omnet-julia | No change. It decodes on the loop and makes no picture document. | No. |
| The other pictures of omnet-julia | No change. A label draws the picture of an `ImageFile`. | No. |

`decode_image_file!` goes, because it writes pixels into the place of the pixel cell. The draft of
an assistant keeps a part that is a picture as it is: the test at `AssistantPicture.jl:75` takes a
picture file too, because an `ImageFile` is no longer an `ImageDocument`.

### 3.7 How the assistant reaches the picture

A name reaches the assistant by the line `For the assistant.` at the end of the docstring of its type
or of its generic function. `make_editor_api` reads the marks when it runs. On main, neither
`ImageFile` nor `WidgetTransformPane` has the mark, and `open_file_document!` has it.

A mark on a type also offers each exported subtype, so `ImageFile` is offered as a subtype of
`FileDocument`. Its own docstring still ends with the mark, because its example shows how to show a
picture, and `search_api` reads it (D6). The docstring of `WidgetTransformPane` ends with the mark.
`ImageDocument` and `Image` get none: a mark on `ImageDocument` also offers `ImageMemory` and
`Image`, and the model writes only `ImageFile`. Both docstrings take the form that
`test_assistant_documentation` checks. The window text names only the verbs of its rules, so it does
not change (§1). The orientation guide gets this example in "Work with files", after the example of
`open_file!` (`orientation.md:246-251`):

```julia
throughput_1 = open_file_document!("media/throughput-new.png")
delay_1 = open_file_document!("media/delay-new.png")
charts_1 = Dashboard("Charts", [DashboardCard("Throughput", throughput_1),
                                DashboardCard("Delay", delay_1)])
open_pane!(charts_1; title = "Charts")
zoom_tab_1 = open_pane!(WidgetTransformPane(throughput_1); title = "Throughput")
show_pane!(zoom_tab_1)
```

The two cards and the zoom tab show the editor's one file document of each path, and
`open_file!("media/throughput-new.png")` shows the same file document in a file tab. So each of them
shows the new picture after a program writes the file again, and the editor reads the file once for
all of them. A `Document` that a call returns shows as a live card, so a picture file as the last
value shows its picture in the conversation. The conversation holds no document, so that picture
does not follow its file.

### 3.8 Where this plan meets G4, G5, the plan of the save and the plan of Q10

The plan of G4 asks six properties of the picture (its §6). This plan gives each of them:

1. The file type of a `.png` is registered, so `make_file_tab`, the open of a file and
   `open_file_document!` make the picture file: yes (§3.1). Nothing reads a byte of the file when
   the picture is made (D12).
2. The pixels are a background cell, and the decode runs in the background work, never in a print,
   a computation or the watcher: yes (§3.2). The watch and the read of the file read no byte of a
   picture file (§3.3).
3. `is_editable_file_type` answers `false`: yes (§3.1).
4. A reported change changes the input of the pixel cell, and a report with no change changes no
   cell of the document: yes. The report adds one to the count of the file, the load adds one to
   the count of the picture, and an equal hash of the time and the size loads nothing (§3.3).
5. Each picture has a `BackgroundSource` of its own (§3.2, D10).
6. The rendered Markdown draws the cell of its pixels in a `TextGraphics`: yes. Step 1 makes the
   text span put the pixel cell into its `GraphicsImage`.

**G4 step 5 and the plan of Q10.** The image of a page holds the file document of its picture in
the same way as a tab holds the file document that it shows, and the page keeps no table of its
pictures (G4 D14). The image resolves its path against the folder of the page, gets the editor's
one file document with `open_file_document!`, draws the picture of that file, and reads no disk. It
draws the picture in a text span and not through the print of a file, so it asks for the read of
the file itself (`demand_file_text`): the first read of a file that reads nothing yet, and each
change (D14). An edit that adds an image must hold its picture, and an edit that removes it must
release it. That needs the general hold rule of the lifecycle of a document (G4 open question 10),
so the plan of Q10 comes before G4 step 5 (G4 D14). G3 does none of this. No step of G3 needs the
plan of Q10: a tab and a card hold by the code on main, and a zoom tab holds when it opens. G3 lands
before G4 step 5.

**G5.** The cell of a record draws the picture of a picture file (step 2). It follows its file when
the table holds its records (G5), and when the cell asks for the read of the file, for the same
reason as the image of a page. The roster slice can not name `demand_file_text`, because the
file-format slice depends on the roster slice (`PlatformSuite.jl:62-63`, `:82-84`). G5 decides how
the cell asks. The plan of G5 also needs a picture that a record holds and that a `.pred` file
saves: the plan of the save writes `file("…")` for it.

**The plan of the save.** Its steps 1 to 5 are on main. A file saved alone writes `file("…")` for
each file document that it holds, and writes none of them (its D0). Its load gives each held file
the editor's one file document, through `open_file_document!(path; editor)`, which answers the file
that the editor has open, or else makes a new file that reads nothing until a place draws it, and
adds it to the open files of the editor at once (its D6 and its open question 5). For a picture,
that load reads no pixel and no time or size, as its §4.10 asks. A load of the holder is a load
(its D7).

## 4. Decisions

The owner decided D1, D2, D7, D8, D9, D10 and D12. The assistant decided D11 from the owner's G4
D2. D3 follows from D1, D12, G4 D10 and G4 D14. The assistant proposed D4, D5, D6, D13 and D14. A
decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. A picture is a file that a person does not edit.** The owner decided this on 2026-11-05
  (model B). `ImageFile` is a file document, and `is_editable_file_type` answers `false` for it,
  as it does for the vector file of a simulation (`FileSplice.jl:35-68`). A card, a tab and a row
  of a table hold the file document. The owner decided the save on 2026-11-05 (option A): a file
  saved alone writes `file("…")` for each file document that it holds, with the path relative to
  its own folder, and does not write that file. Edits of the held file that are not saved stay
  until the person saves that file. The load of the saved file gives each named file the editor's
  one file document of its path, so a tab and a card share it. This is for every file kind, not for
  pictures only (the plan of the save, on main). Rejected: option B, a save of the holder as a
  project, which writes each file that it holds. Rejected: model A, a picture that holds its path
  and is not a file document. It adds a second way to follow a file on disk, and it puts a fact of
  storage into the document, against `FileCut.jl:4`. Rejected: a second type for the tab of a
  picture file, because two names for one picture confuse the assistant.
- **D2. A print asks for the pixels, and a task decodes them.** Confirmed by the owner on
  2026-11-05 with model B (G4 D5): the pixels of the picture file document are a background cell.
  A draw on the screen demands them, and the editor reads the demanded pictures on a task after the
  frame. A picture that is not on the screen is not read. Rejected: a read in the acquire. A
  picture in the conversation or in a cell can have no holder, and it would never show. Rejected:
  one source for each editor, because the assistant makes a picture before a holder has it.
- **D3. A picture follows its file through its file document.** It follows from D1, D12, G4 D10 and
  G4 D14 (decided by the owner). The editor's one file document of the path watches the file while
  a place holds it, the watch only reports a change, and the file takes the change as every file
  that a person does not edit takes it (§3.3, D13). So a picture file is watched once and read once
  for all the places that show it. Rejected: a watch of the folder of each picture, with a fragment
  `ImageFileWatch.jl`. It is a second way to follow a file, and it counts against the limit of 1000
  folders of a store. Rejected: a new kind of watch. Rejected: a watcher that reads a picture file
  again and gives it to the picture, because the watch reads nothing (D12).
- **D4. The size comes from the holder.** The holder gives the slot and the zoom, and the view of
  each place keeps the choice of Ctrl+1 (D8, D11). Rejected: a field for a size or a zoom factor. A
  tab would have two zooms, and a picture in a card would take the wheel from the dashboard.
- **D5. No caption field.** Rejected: a `caption` field, which repeats the title of a card.
- **D6. The type keeps its name `ImageFile`.** "Image" is the word of a Markdown image and of the
  media type `image/png`. The docstring also says "picture", so `search_api` finds either word. The
  example of the docstring gets the file with `open_file_document!`, because `ImageFile(path)` makes
  a second document of a path that the editor can have open (§3.1).
- **D7. This plan starts after steps 1 to 4 of `reflection-api` land, and lands before step 5 of
  G4.** The owner decided the order on 2026-11-05. Steps 1 to 4 of `reflection-api` are on main,
  so a name reaches the assistant only by the mark `For the assistant.` (§3.7). Rejected: this plan
  lands first, before the mark rule is on main.
- **D8. Ctrl+1 shows a picture at its natural size.** The owner decided this on 2026-11-05 (open
  question 3, option A): one pixel of the image to one pixel of the screen. The binding belongs to
  the picture view, because only a picture knows its natural size. The fitted view stays the
  default, and Ctrl+0 goes back to it. Rejected: no key, so that the person zooms with Ctrl+wheel.
- **D9. The content of a picture file is its picture, `Image <: ImageDocument`.** The owner decided
  the name on 2026-11-05: the content of a file type is named for what it is, as a `JsonFile` holds
  a `JsonObject`. `Image` holds the path, `read_count`, the pixel cell, `natural_size` and `failure`
  (§3.2). A load of its file keeps the picture (D13), so the pixel cell keeps its last pixels until
  the new ones come. Rejected: a new picture at each load. Its pixel cell has no answer, so each
  rewrite shows the box for a frame or more. A script that writes 17 charts at once makes 17 boxes.
  Rejected: a picture that keeps the time and the size of its last read and compares them itself,
  because the read of the file compares them for every file that a person does not edit. Rejected:
  the time and the size as the content, and the pixels in a third field of the file, as the tables
  of `LegacyResultFile`. Then `read_document_file` of a picture answers no picture, and a new
  document must hold two numbers, because a history takes only a `Document`. Rejected:
  `ImageFile <: ImageDocument` with the trait `is_file_document`. The acquire, the watch, the read
  and the row of a file take `FileDocument` (`FileChangeStore.jl:113`, `:255`; `DocumentFile.jl:821`;
  `FileToContent.jl:60`).
- **D10. Each picture has a source of its own.** Decided by the owner on 2026-11-05 (open
  question 12, option A). `Image(path)` makes the `BackgroundSource` of the picture, and no maker
  passes one. The pictures that one frame demands decode in parallel, each on a task; 960 decodes
  on 16 tasks gave equal pixels (§1). The rule has no order: a picture that a tab, a Markdown page
  or the assistant made first reads in the same way. Rejected: a keyword `source` on
  `open_file_document!`, `ImageFile` and `Image`, which a holder such as a Markdown page passes. A
  file that a tab made earlier keeps its own source, so the batch depends on which holder came
  first. Rejected: one source for the editor. One task then decodes every picture of a frame one
  after another, which is slower for a dashboard of 17 charts. Rejected: a picture with no source
  until a holder gives one. The open and the assistant make a picture before a holder has it.
- **D11. Each place keeps its choice of Ctrl+1 in its view.** Decided by the assistant on
  2026-11-05 from the owner's G4 D2: the state of a view belongs to each place that shows a file.
  The view of a place (`FileView`, which `make_document_view(::FileDocument)` makes, G4 D12) keeps
  the choice in a field, as its scroll pane keeps the scroll place. A write of it adds no undo
  step, and a save does not write it. Ctrl+1 in a tab leaves a card of the same file at the fit.
  The binding stays in the picture view (D8), which takes the choice from the view of its place
  through a context property (§3.4). Rejected: the choice as view state of the picture, shared by
  every place that shows one file. Rejected: a field of the holder.
- **D12. The watch only reports a change.** Decided by the owner on 2026-11-05 with G4 D4: every
  outside read is a background cell, and the watch reads no text and computes no hash for any file
  kind. Each change that the watch reports adds one to a count of changes. The input of the pixel
  cell is the path and the count of the picture, which each load of its file adds one to (D13). So
  only a picture on the screen is read again after a change, and the time and the size are not the
  input of the cell. Property 4 of G4 (an unchanged report changes nothing) holds in the read of the
  file, which compares the hash of the time and the size, and in the `apply` of the pixels, which
  compares what it read with what the picture has.
- **D13. A picture file takes a change as every file that a person does not edit, and the load
  keeps its picture.** Proposed by the assistant on 2026-11-08, from G4 D10 and G4 step 2: the file
  document is the receiver of its watch, adds one to its count, and reads when it is drawn. A
  picture file has no method of its own for a change. The read on a task answers a new picture
  that reads nothing, the load gives it to the history, and `replace_wrapped_document!(::Image,
  document)` keeps the old picture and adds one to its count when the new one has the same path.
  The kernel declares that function for a document that must survive a replacement
  (`DocumentInterface.jl:490-506`), and the style slice adds the method. F5 takes the hash of the
  time and the size for a type that a person does not edit, as the read on a task does (§3.3).
  Rejected: a method `receive_file_change!(editor, ::ImageFile)` that adds one to the count of the
  picture and skips the read of the file. It is a second path for one kind of file. The style slice
  can not add a method to a function of the file-format slice (`PlatformSuite.jl:35`), so the
  function must move to the serialization slice. And a picture file that reads nothing yet needs
  the read of the file at its first draw in either model. Rejected: the file gives each change to its
  content first, through a method of `receive_file_change!` for `Image`. It has the same slice
  problem. Rejected: the picture reads a count that its file keeps, because the picture must then
  know its file.
- **D14. The print of a file asks for the read of its file.** Proposed by the assistant on
  2026-11-08, from the owner's G4 D14 ("The explorer and the pages are not special in any way") and
  the rule that a file reads when it is drawn (G4 D4). `FileToContent` asks for the text of its
  file (`demand_file_text`) where it reads the content of the file. So a place that draws a file
  with no view of its own, such as a zoom tab (§3.7), reads the file at its first draw and after a
  change. The view of a file asks too (`FileViewToWidget.jl:72`), and a second ask in one frame
  records no second demand. A file that no place draws still reads nothing. Rejected: a zoom tab
  around a view of the file, `WidgetTransformPane(make_document_view(file))`. `make_document_view`
  is not offered to the assistant, and each new place must know of the view. Rejected: the read of
  a picture file at its acquire, a second read beside the read at the draw (G4 D4).

## 5. Steps

Each step runs in a worktree and ends with one commit in each repository that it changes.
`workspace/bin/bounded-run` runs each test: a test under `test/platform/` in
`package/ProjecturedPlatformTest`, any other in `environment/all`. No step changes a file under
`source/kernel/`, so no step changes a sealed file.

The dependencies: step 1 needs no other plan. Step 2 needs step 1. Steps 3 and 4 need step 2.
Step 5 needs steps 1 to 4. The plans that the steps need are on main: G4 steps 1 to 3 and steps 1
to 5 of the plan of the save. No step needs the plan of G4 open question 10.

- [x] **1. A picture reads its pixels on a task, and only a paint reads them.** `Image` in
      `Image.jl`: its fields, which hold the path, `read_count`, the pixel cell, `natural_size` and
      `failure`, its source, its work, its `apply` and `pred_arguments`. A label and a text span
      draw an `Image` from `natural_size` and `failure` in the print, and put its pixel cell into
      the `GraphicsImage` (`WidgetToGraphics.jl`, `TextToGraphics.jl`). An `ImageFile` and an
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
      Done on branch `picture-file`. Decisions and facts of the step:
      - `Image` has six fields, in this order: `filename`, `read_count`, `pixels` (the
        background cell), `natural_size`, `failure`, `source`. It has no defaults, so the macro
        writes no keyword constructor that the outer `Image(filename)` could collide with. All
        fields but `filename` are view state (`get_view_state_fields`), so a walk does not enter
        `pixels` and a save writes the path only (`pred_arguments`, `make_pred_document`).
      - The test source: `_make_image(filename, source)` is the internal constructor, and
        `Image(filename)` calls it with `_make_image_source()`. No public maker takes a `source`.
        A test calls `StyleModule._make_image`.
      - `ApplyImageAnswerOperation(image, read_count, answer)` is the `apply`. Like
        `ApplyFolderListingOperation`, it drops the answer of an older `read_count` and writes
        plain fields directly, so undo records none. It is not exported.
      - `Cell(cell)` nests a cell in a cell. `GraphicsImage` therefore keeps a `Cell` given as
        `data` (`_make_image_data_cell`), so `img.data` reads through the pixel cell. SDL, PDF and
        web read `img.data` as a plain value and need no change: an exception as the answer
        draws nothing there.
      - A label puts a box under the pixels while `natural_size` is `nothing` or `failure` is
        set. A text span takes its size from its holder and reads neither cell.
      - The style slice uses `using ..BackendModule`, `..EditorModule` and `..OperationModule`
        bare, because the layering guard refuses a symbol list on a `using`.
      - Counts: `test_image()` 28/28; `test_widget_button_behavior()` 134 passes in 25 sets, no
        fail; `test_inline_image_caret()` 258/258; `test_text_to_graphics()` no fail;
        `test_image_file_read()` (SDL, offscreen) 7/7. The tests ran in `environment/all`,
        because the worktree has no manifest for `package/ProjecturedPlatformTest`. The platform
        layering guard gives 5 pass and 2 fail, and the slice edges 1 pass and 1 fail, both for
        files outside the style slice (`appearance`, `assistant`), as on main.
- [ ] **2. A picture file is a file that a person does not edit, and a load keeps its picture.**
      In `Image.jl`: `ImageFile <: FileDocument` with the fields `filename`, `content` and `disk`,
      `ImageFile(path)` and the constructor of a path and a content, `is_editable_file_type`,
      `read_file_content`, `get_file_domain`, and `replace_wrapped_document!(::Image, document)`
      (D13). `set_cell_computation!(::ImageFile)` goes. `StyleModule.jl` registers the five
      extensions. In `DocumentFile.jl`: F5 (`ReloadFileOperation` with no hash) takes the hash of
      the time and the size for a type that a person does not edit (D13). A label and a text span
      draw the picture that `get_edited_document` answers for an `ImageFile`. The cell of a roster
      draws a picture for a value for which `get_edited_document` answers an `ImageDocument`
      (`RosterToGraphics.jl:138-144`). `decode_image_file!` goes from `SdlBackend.jl`. The holders
      of §3.6 drop their decode: `MarkdownToSyntax.jl`, `BookToSyntax.jl`, `RstToSyntax.jl`,
      `RosterToGraphics.jl`, `ConversationToWidget.jl` and `example/platform/TextDocumentExample.jl`.
      `AssistantPicture.jl:75` keeps a picture file. In omnet-julia,
      `LegacyChartComparisonToWidget.jl` and `LegacyStoreEntryToWidget.jl` follow in a commit that
      lands with this one. Update `style.md`, the table at the head of `DocumentFile.jl`,
      `fileformat.md` and `filechange.md`. Test: `test_image()`, new sets.
      `read_document_file("a.png")` answers an `Image`, and the test source runs no work.
      `make_file_tab("a.png")` answers an `ImageFile` that holds that picture. In an editor with a
      `FileChangeStore`, `OpenFileOperation` of a `.png` opens a tab of the view of the file, and
      the file is the receiver of its watch (`===`). A new file at the path, a drain and a frame:
      the file holds the same picture (`===`) with one more `read_count`, and the test source runs
      no work until a frame reads the pixel cell. A drain with no change of the file changes no
      cell of the picture. F5 adds one to `read_count` of the picture, and the hash of the file is
      the hash of its time and size. `open_file_document!("b.png")` answers a file that holds
      `DocumentNothing()`, and after the first draw of its view it holds a picture of `b.png`. Then
      `test_filechange()`, with a new set: F5 on `_ReadOnlyProbeFile` gives the file the hash of
      its time and size. Then `test_roster_table()`, with a new set: a record that holds the
      editor's file document of a picture shows a picture cell, as a record with a bare
      `ImageFile` does. Then `test_task_views()`, `test_external_agent_turn()`,
      `test_markdown_image_leaf()` and `test_explorer()`. `test_book()` and `test_rst()` follow,
      because no narrower test prints their pictures. In omnet-julia:
      `test_chart_comparison_document()`, `test_legacy_store_entry_pages()`,
      `test_simulation_embed_in_page()` and `Pkg.precompile()`.
- [ ] **3. The picture is a view.** `ImageToWidget` in `source/platform/natural/ImageToWidget.jl`,
      its row in `NaturalProjection.jl`, and Ctrl+1 and Ctrl+0. The choice of D11 is a field of
      `FileView` (`FileView.jl`), and `FileViewToWidget` gives its view to the print of its file as
      a context property (§3.4). Update the row list of `natural.md` and the view of a file in
      `fileformat.md`. Test: the new `test_image_to_widget()` in
      `test/platform/projection/ImageToWidgetTest.jl`, with a test source that answers pixels of 400
      by 300. Before the answer, a slot 200 wide draws a box 200 by 150 with the path. After it, a
      slot 200 wide draws 200 by 150. A slot 800 wide draws 400 by 300, and so does a scroll pane
      that grows on both axes. Three pictures in a `HorizontalLayout` 600 wide with `Fill` draw 200
      wide each. A `DashboardCard` draws the picture at the width of the card. A failed read draws
      the path and the reason. Ctrl+1 in a tab 200 wide draws the picture 400 by 300, no history
      records it, and a card of the same file stays at 200 by 150. Ctrl+0 draws it 200 by 150
      again. At the fit, the reader returns `nothing` for Ctrl+0. A picture in a label returns
      `nothing` for Ctrl+1. Then `test_file_tab()`, `test_explorer()`, `test_filechange()` and
      `test_user_interface_file()`, because `FileView` gets a field that a save must not write.
- [ ] **4. The assistant reaches the picture, and a zoom tab follows its file.**
      `get_edited_field(::WidgetTransformPane) = :content` in `WidgetDocument.jl`. `FileToContent`
      asks for the text of its file where it reads the content (D14, `FileToContent.jl:60-73`). The
      mark at the end of the docstrings of `ImageFile` and `WidgetTransformPane`, and the example of
      §3.7 in `documentation/guide/orientation.md`. Update the transform pane in `widget.md` and the
      read of a file in `fileformat.md` and `filechange.md`. Test: `test_image()`, a new set: a tab
      of `WidgetTransformPane(file)` holds the file of `p`, and the file watches `p`. A file of `p`
      that reads nothing yet and that only the zoom tab holds reads at its first draw. A new PNG at
      `p` and a drain reach the picture with no view of the file. `open_file!(p)` answers the zoom
      tab. The close of the tab releases the file, and the watch stops when no other holder holds
      it. Then `test_widget_transform_pane()`, `test_filechange()`, `test_file_tab()`,
      `test_dashboard_render()`, `test_assistant_documentation()`, and `test_assistant_verbs()` with
      a new set beside "tell: a drawing, a chart and a graph draw in a tab"
      (`AssistantVerbsTest.jl:279-303`). In it the code tool gets a picture file with
      `open_file_document!`, and puts it in a card and in a `WidgetTransformPane`. Then
      `test_referenced_document_editor()`, because a new docstring can move the rank of
      `search_api`. Compare each count with a run on `main`. In omnet-julia,
      `test_simulation_embed_in_page()`, because a tab now holds the content of a transform pane.
- [ ] **5. The live check in `omnet_ide`.** Through its MCP connection, the assistant gets three
      charts with `open_file_document!`, fills a dashboard with them, opens one in a file tab with
      `open_file!` and in a `WidgetTransformPane`, and returns one picture file from a call. A
      script writes a new PNG at the path of the zoomed chart. `take_picture` must show the new
      picture in its file tab, in its card and in its zoom tab. The store of the background work
      (`get_background_work_store`) must record one read of that file and one decode of that
      picture for the change, because the three places show one file document. Ctrl+1 in the file
      tab must show the natural size while the card stays at the fit. Ctrl+0 must fit it again, and
      Ctrl+wheel must zoom the transform tab. Then `Pkg.precompile()` runs in omnet-julia, and this
      plan moves to `plan/done/`.

## 6. Risks

- **A plain layout reads each of its pictures.** The backend skips an image outside the clip only in
  a list canvas and in the lines of a text (§1). A picture in a plain layout is read at the first
  paint, also off the screen. The test of step 1 asserts the laziness in a list canvas only. The
  owner accepts these reads until the plan of the layouts lands (open question 9).
- **The web backend reads each picture.** At the first paint it sends the whole drawing of a window
  to the browser, with the pixels of each picture (`WebBackend.jl:1089`, `:303-305`). So in the web
  backend each picture of a window is decoded, also off the screen. The owner accepts this for now
  (the plan of the layouts, its D11).
- **A print with no editor draws the box.** A script or a test must call `wait_for_cell!` on the
  pixel cell before it writes an image. The tests of steps 1 and 2 show which prints have no editor.
- **SDL decodes on many tasks at once.** The check of §1 found equal pixels on 8 threads with no
  video. The loaders start at the first decode, on whichever task comes first.
  `test_image_file_read()` and step 5 show the decode beside a window.
- **A change shows after two rounds of background work.** The read of the file waits until the file
  is whole (at least 50 ms, `DocumentFile.jl:374-389`), and the decode comes after the next paint.
  A file that a program writes for longer than 2 s can still give the decode a file that is not
  whole. The work then answers the failure, and the view draws the reason until the next report.
- **A picture file that reads nothing yet shows in three stages:** the row "<name> · reading", then
  the box with the path, then the pixels.
- **A place that does not hold the picture file does not follow it.** A label, a cell, the
  conversation and a transform pane outside a tab show the file as it is at their first paint. The
  hold rule of the plan of G4 open question 10 decides these places.
- **Two documents of one path.** `ImageFile(path)` makes a new file document. A card that holds it
  while a tab shows the editor's file document of that path gives two watches and two reads, and
  the open files list the path twice. The docstring sends a holder to `open_file_document!` (D6).
  The plan of G4 open question 10 decides whether the editor refuses a second document of a path.
- **D14 changes the print of every file.** Each file that a place prints asks for its read, also a
  file in a print that is off the screen in a plain layout. Such a file reads its text after a
  change, which only its view did before. A dashboard prints only the cards on the screen (G4 D9).
  `test_filechange()` and `test_dashboard_render()` in step 4 show it.
- **A tab holds the content of a transform pane.** omnet-julia shows a network in one
  (`source/presentation/page/EmbedPanes.jl:445`, `source/presentation/module/SimulationTopologyToWidget.jl:257`),
  so `get_edited_document` of that tab can change. The finder of the tab of a file walks the edited
  fields (`_is_document_in_tab`, `FileSystemDocument.jl:284-292`), so `open_file!` of a picture
  that only a zoom tab shows answers that zoom tab. Step 4 runs the tests and asserts it.
- **A picture path that does not exist opens as `DocumentNothing()`**, the seed of an extension
  with no seed (§1). The file of that path reads the file when a program writes it, and loads a
  picture once. From then on, D13 holds.
- **A computation that makes a picture makes a new pixel cell at each run.** The chart comparison of
  omnet-julia and the facets of a roster do so. They decode again only when that computation runs
  again. A computation that read the pixel cell of a picture that it makes would ask at each answer;
  the docstring says so. Until G4 step 5, a Markdown, Book or RST page makes a new picture at each
  print of an image node, so a print of that node shows the box for a frame or more.
- **omnet-julia breaks between the two commits of step 2**, because its two holders read `raw` of an
  `ImageFile`. Both commits must land on main together. `Pkg.precompile()` in omnet-julia shows it.
- **The open of a picture file reads no byte**, but `read_document_file` calls `isfile`
  (`DocumentFile.jl:99`) and `make_file_tab` reads the time and the size on the loop.
- **omnet-julia keeps one decode on the loop:** the icon of a module.
- **Book and RST keep `isfile` in the print** until G4 step 5a (open question 10).
- **The rank of `search_api` can move.** Step 4 runs the tests of the rank.

Not in this plan: a special tab of a picture file (D1), the image span of Markdown that holds its
picture (G4 step 5, after the plan of G4 open question 10), the image spans of Book and RST (G4 step
5a), the hold of a picture by a label, a cell or the conversation (the plan of G4 open question 10),
a plain layout that paints only what the screen shows (open question 9), and the icon decode of
omnet-julia. A comparison view is G7, and a link to the tab of a picture is G6.

## 7. Open questions for the owner

This revision adds no new question. D13 and D14 are proposed decisions (§4). The answered
questions follow.

1. **The tab of a picture file.** Resolved by D1 on 2026-11-05: a picture is a registered file type,
   so the open of today opens a file tab for it, and G3 adds the type. The question was: a press on
   a `.png` in the Files pane throws. Must G3 or G4 open a picture file in a tab?
2. **The third need of G4.** Answered by the owner on 2026-11-05: the model of G4 (D1, model B).
   The question was: G4 expects the file watcher to read a picture again. Which model must both
   plans use?
3. **A key for the natural size.** Answered by the owner on 2026-11-05: yes, Ctrl+1 (D8). The
   question was: in a tab smaller than the picture, the person zooms to the natural size. Must a tab
   of a picture have a key for it?
4. **A picture with no editor.** Resolved by G4 D5 on 2026-11-05: the pixels of a picture are a
   background cell, so a script calls `wait_for_cell!` with `editor = nothing`, as for any
   background cell, and that computes the pixels. The question was: must a read with no editor
   decode at once instead?
5. **The order** (D7). Answered by the owner on 2026-11-05: steps 1 to 4 of `reflection-api` land
   first (D7). The question was: can this plan land on `main` before `reflection-api`?
6. **The content of a picture file** (D9). Answered by the owner on 2026-11-05: the name is `Image`
   (D9). The question was: what is the name of the picture that a picture file holds, and how does
   it keep itself at a load?
7. **The choice of Ctrl+1** (D11). Decided by the assistant on 2026-11-05 from the owner's G4 D2
   (the state of a view belongs to each place): each place keeps its own choice, in its view. The
   question was: Ctrl+1 in a tab also changes a card that shows the same file. Is that acceptable,
   or must each place keep its own choice?
8. **A plan in omnet-julia.** Decided by the assistant on 2026-11-05, as for G8 and G9: step 2
   changes the two files of omnet-julia in the same landing, and no sibling plan is written. The
   reflection plan also spans both repositories. The question was: step 2 changes two files of
   omnet-julia. Must a small plan in omnet-julia name this one, or can step 2 carry the two files?
9. **Pictures that a plain layout holds.** Answered by the owner on 2026-11-05: option A, a plan of
   its own after G3 makes each layout tell which of its elements meet the visible area, so the
   backend paints only those. G3 accepts the extra reads until it lands. The question was: the
   backend reads every image of a horizontal, vertical, grid, flow or stack layout, also outside the
   clip (§1). Must those layouts skip what lies outside the clip, as a list does?
10. **Book and RST.** Decided by the assistant on 2026-11-05: G4 step 5a gives Book and RST the
    model of G4 step 5, from the owner's rule that a printer reads no disk. The question was: their
    image spans keep `isfile` in the print after G3. Must a plan give them the model of G4 step 5?
11. **The file of a picture with no tab, for the assistant.** Answered by the owner on 2026-11-05:
    the function of the plan of the save that answers the editor's one file document of a path,
    `open_file_document!(path; editor)`, carries the mark (`OpenFileList.jl:141`). So the assistant
    gets the file with no tab and puts it in a card with `insert_elements!` or in a tab with
    `open_pane!`. The question was: a card and a zoom tab follow a picture only when they hold the
    editor's one document of its file, and `open_file!` also opens a tab, so a dashboard of 17
    charts that follow their files opens 17 tabs. Must the assistant get that document with no tab?
12. **The source of a new picture file.** Answered by the owner on 2026-11-05: option A, each
    picture has a source of its own (D10). The question was: must `open_file_document!` take a
    keyword `source` that a new picture file takes, or does G4 accept a source for each picture?
