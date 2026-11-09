# A picture gets its size from the head of its file

> **Kind:** plan · **For:** developer · **Status:** a plan, written 2026-11-09 at `main` `7dd836aaf`
> on the branch `picture-size`. It is not approved, and no step is built.
> · **Needs:** the plan of the layout on main, which it is since `2a3f4b7a8`
> · **Sibling plans:** the parent [a-layout-paints-only-what-the-screen-shows.md](../done/a-layout-paints-only-what-the-screen-shows.md)
> (its D12, §4.7, §4.10 and the risk "A picture that comes on the screen moves what is after it"),
> G3 [the-assistant-shows-a-picture-file.md](../done/the-assistant-shows-a-picture-file.md) (`Image`,
> `ImageFile`, its D10), G4 [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md)
> (its steps 5 and 5a change the three image spans that step 3 of this plan changes)
> · **Stands on:** [style.md](../../documentation/package/platform/style/style.md),
> [natural.md](../../documentation/package/platform/natural/natural.md),
> [editor.md](../../documentation/package/kernel/editor.md),
> [sdl.md](../../documentation/package/backend/sdl/sdl.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md)

The owner decided on 2026-11-09 (D12 of the layout plan, option B) that a picture gets its size
apart from its pixels, in a plan of its own. This is that plan. A print asks for the size, and a
task reads it from the head of the file with no decode. Only a paint asks for the pixels. The size
is one more background cell of the picture, as the pixels are, so the plan adds no event, no
payload, no channel and no kernel hook.

The owner rules that bind the design: a reader and a print read no disk, and a task reads the
outside state and an operation writes what it found into the document; keep what the producer
knew; who needs a value asks for it, and making a document reads nothing; no new dependency in the
platform; design the correct model, not a minimal patch; the steps are fixed up front.

The example of D12, three charts of 1000 by 600 pixels in a column in a tab of 1000 by 500:

| # | What happens | The state | What the person sees |
| --- | --- | --- | --- |
| 1 | The tab opens. | The print asks for the size of a, b and c. One task reads the head of each file and decodes nothing. The paint reads the pixels of a only. | a, as a box of 320 by 240 for one frame |
| 2 | The next frame. | The sizes are in. The column is 1800 high. The decode of a answers. | a, and a scroll bar of a column of 1800 |
| 3 | The person scrolls to the end. | The view shows 1300 to 1800. c is decoded. Nothing moves. | c, as a box of 1000 by 600 for one frame, then the chart |

## 1. The goal

When this plan is done, these must be true:

1. A print of a picture asks for its size and never for its pixels. A task reads the size from the
   head of the file, with no decode, for a PNG, GIF, BMP or JPEG file.
2. The size is a background cell of the picture. The plan adds no event, no payload, no channel and
   no kernel hook.
3. A column of 60 pictures in a scroll pane has its true height in the frame after its first print,
   and the pixel cell of each picture off the screen has no read.
4. A picture that comes on the screen moves nothing: its decode gives the size that its head gave.
5. A file that does not exist shows its failure with no paint.
6. A change of the file reads its head again.
7. Any other format gets its size from the decode, as now.

## 2. What exists (checked at `main` `7dd836aaf`)

| Thing | Where | State |
| --- | --- | --- |
| The picture | `Image`, `source/platform/style/Image.jl:35-71`; its maker, `:75-88` | Six fields: `filename`, `read_count`, `pixels`, `natural_size`, `failure`, `source`. "Making an `Image` reads nothing and runs no work" (`:38-39`). `pixels` is a background cell with the inputs `(path[], read_count[])` (`:83-84`). `natural_size` and `failure` are plain cells, `nothing` until the first answer. `_make_image(filename, source)` takes the source of the pixels; a test passes one whose work it counts. |
| The view state | `get_view_state_fields(::Type{<:Image})`, `Image.jl:73` | Every field but `filename`. A save writes the path only (`pred_arguments`, `:142`), and a copy is `Image(filename)` (`copy_document`, `:138-139`). |
| The decode | `_make_image_source`, `Image.jl:92-94`; `_read_image_answer`, `:96-102`; `decode_image`, `source/kernel/backend/BackendInterface.jl:214-220`; `decode_sdl_image`, `source/backend/sdl/SdlBackend.jl:6025-6051`, its seam `:6054` | Each picture has a `BackgroundSource` of its own, so the pictures of a frame decode in parallel (G3 D10). The work answers `(bytes, width, height)` or the exception as a value. The decode is SDL_image `IMG_Load`, which chooses the format by the content of the file. |
| The answer | `ApplyImageAnswerOperation`, `Image.jl:107-133` | It drops the answer of a read that a newer read follows (`:123`). It writes the size of the pixels into `natural_size`, or the exception into `failure`, and writes no cell whose value stays the same. It has one kind of answer. |
| The file of a picture | `ImageFile`, `Image.jl:151-188`; `replace_wrapped_document!(::Image, …)`, `:193-197` | A change of the file adds one to `read_count` of the picture that the file keeps. The extensions `.png`, `.jpg`, `.jpeg`, `.bmp` and `.gif` are this type (`StyleModule.jl:132-136`). |
| The background cell | `BackgroundSource`, `source/kernel/editor/BackgroundCells.jl:8-35`; `make_background_cell`, `:181-232`; `_record_background_demand!`, `:256-274`; `_take_background_demands!`, `:277-291`; `start_background_cell_work!`, `:319-334`; `_write_background_answers!`, `:385-404`; `wait_for_cell!`, `:423` | A read in a computation of a frame records a demand and never waits. With no editor it records nothing. After the print the editor groups the demands of the frame by their source object, and starts one task, one record of the work store and one answer operation for each source. The `apply` of a cell stores its answer in the document by an operation. |
| The order of a frame | `source/kernel/editor/EditorLoop.jl:115-122` | The print, with the paint, runs first; `start_background_cell_work!` runs after it. |
| A print that asks through a background cell | `demand_file_text`, `source/platform/fileformat/DocumentFile.jl:855-868`; its call in a print, `FileToContent.jl:76` | The print reads the background cell of the text of a file only while a change is unread. The `apply` stores the answer, and the print reads plain state. The same form serves this plan. |
| The readers of `natural_size` | `_image_payload(::Image)`, `source/platform/widget/WidgetToGraphics.jl:1279-1286`; the box under the pixels, `:1322-1324`; `_make_shown_image_widget`, `source/platform/natural/ImageToWidget.jl:34-38`, and its docstring, `:11-14`; `_md_image_value`, `source/domain/markdown/MarkdownToSyntax.jl:484-492` (`:487`); `_picture_leaf_value`, `source/domain/book/BookToSyntax.jl:567-590` (`:580`); `_rst_picture`, `source/domain/rst/RstToSyntax.jl:1236-1248` (`:1239`) | A label measures 320 by 240 with no size (`_UNMEASURED_IMAGE_SIZE`). The label puts a box under its pixels while `natural_size` is `nothing` or `failure` is set. `ImageToWidget` draws the path below the box while `natural_size` is `nothing`. The three spans measure 720 by 460 with no size, capped at 640 wide. Each of the six reads the cell itself. |
| The reader of omnet-julia | `_make_saved_picture`, omnet-julia `source/ide/LegacyStoreEntryToWidget.jl:48-58` (`:54`), at omnet-julia `main` `925c73605` | A `LayoutConstraint` whose bounds read `picture.natural_size`, around a `WidgetLabel(picture)`. inet-julia `main` `9074572` reads no picture. |
| The spans make a picture at each print | `MarkdownToSyntax.jl:485-486`, `BookToSyntax.jl:578-579`, `RstToSyntax.jl:1237-1238` | Each calls `isfile` and makes an `Image` in the print. G4 steps 5 and 5a change this. |
| The test helpers | `_make_sized_picture_file`, `test/platform/document/ImageTest.jl:96-102`; `_itw_make_picture`, `test/platform/projection/ImageToWidgetTest.jl:16-21`; `_make_image_test_source`, `ImageTest.jl:23-30` | The first two set `natural_size` by hand, with a decode source that answers `nothing`, at paths that do not exist (`"chart.png"`, `"<task>.png"`). `test_roster_table()` and `test_task_views()` use the first one. |
| The tests | `test_image()`, `ImageTest.jl`; `test_image_to_widget()`, `ImageToWidgetTest.jl`; `test_image_file_read()`, `test/backend/sdl/projection/ImageFileReadTest.jl`; `test_layout_render()`, `LayoutRenderTest.jl`; `test_markdown_image_leaf()`, `test/domain/markdown/MarkdownImageLeafTest.jl`; `test_book_to_syntax()`, `test/domain/book/projection/BookToSyntaxTest.jl` | There is no `test/platform/style/`: the test of `Image.jl` is in `test/platform/document/`. RST has no test of a picture. `ImageTest.jl:431` asserts 320 by 240 for a file that holds the text `"one"`. |
| The fixtures | `asset/image/` | PNG files only: `file.png` is 16 by 16, `projectured.png` 1876 by 489. No JPEG, GIF or BMP file is in `test/`, `example/` or `asset/`. |
| The decoder, measured | SDL_image 2.6.2 (`SDL2_image_jll` 2.6.2+1 in `environment/all`) | A script on 2026-11-09 wrote each file and decoded it with `IMG_Load`. A GIF with a screen of 20 by 10 and one frame of 5 by 4 at (2, 3) decodes as 5 by 4: the size of the first frame, not of the screen. A BMP of 7 by 5 stored top-down, with a height of −5, decodes as 7 by 5. A JPEG of 7 by 5 with an EXIF orientation of 6 decodes as 7 by 5: the decoder does not turn it. A JPEG of 7 by 5 with three APP1 segments of 65 535 bytes after its SOI, 197 273 bytes in all, decodes as 7 by 5. The markers of a JPEG that `IMG_SaveJPG` writes are E0, FE, DB, DB, C0, C4 four times, DA. |
| The cost of a head read, measured | a script, 2026-11-09, 8 threads, warm cache | 60 reads of the first 24 bytes of 60 files take 72 µs on one task and 39 µs on 60 tasks. |
| The seals | `SEALING.md` | It lists files under `source/kernel/` only. No step of this plan changes one. |
| The test environment | `.gitignore:28` | A worktree has no manifest for the test packages, so each test runs in `environment/all` of the worktree, through `workspace/bin/bounded-run`. |

## 3. What the code does not do yet

1. A picture gets its size only from the decode of its pixels, and only a paint asks for the decode.
   So a picture that the screen has not shown measures 320 by 240 in a label and 720 by 460 in a
   span, and a layout of a vector moves what is after it when it comes on the screen.
2. No code reads the size of a picture file without a decode.
3. A file that does not exist shows its failure only after a paint asks for its pixels.
4. `ApplyImageAnswerOperation` has no rule for two answers of one read.

## 4. The design

### 4.1 The head of a picture file

`read_image_size(path)` reads the size that the head of a picture file states, with no decode. It
lives in a new fragment `source/platform/style/ImageHead.jl` of `StyleModule`, and `StyleModule`
exports it. It opens the file, reads its first bytes, and chooses the reader by the signature in
those bytes, not by the extension (D8):

| Format | Signature | Where the size is | Bytes it reads |
| --- | --- | --- | --- |
| PNG | `89 50 4E 47 0D 0A 1A 0A` | the `IHDR` chunk: the width and the height, 32-bit big-endian, at bytes 16 to 23 | 24 |
| BMP | `BM` | the size of the DIB header at byte 14. A header of 12 bytes has a 16-bit width and height at bytes 18 and 20. A header of 40 to 124 bytes has a signed 32-bit width and height at bytes 18 and 22. A negative height is a picture stored top-down, and the reader takes its absolute value. | 26 |
| GIF | `GIF87a` or `GIF89a` | the first image descriptor (`2C`): the 16-bit little-endian width and height at its bytes 5 to 8. The reader skips the screen descriptor, the global colour table, and each extension (`21`) by its sub-blocks. SDL_image decodes the first frame, not the screen (§2), so the size of the screen is not the size of the pixels. | 13, the colour table, 2 for each sub-block, and 10 |
| JPEG | `FF D8` | the first SOF marker, `C0` to `CF` but not `C4`, `C8` and `CC`: the 16-bit big-endian height and width after its length and its precision. The reader skips fill bytes `FF` and the markers with no length (`01`, `D0` to `D7`), and seeks past the body of every other segment by its length. | 4 for each segment, and 9 |

It answers `(width, height)` as a `Tuple{Int,Int}`, or `nothing`. It answers `nothing` for a file
with none of the four signatures, for a head that ends before the size, for a size of 0, for a JPEG
with an SOS (`DA`) or an EOI (`D9`) before its SOF, for a GIF with its trailer (`3B`) before a
frame, and for a JPEG or a GIF whose walk passes byte 1 048 576 (1 MiB) before it finds the size
(D11). A file that it can not open throws the `SystemError` of `open`. It keeps nothing, reads no
document and calls no backend. It is plain Julia over bytes with `open`, `read`, `seek`, `skip`,
`ntoh` and `ltoh` of Base, so the platform gets no new dependency.

The bound of the walk: one APPn segment of a JPEG holds at most 65 535 bytes. A file of a camera
holds an EXIF segment with its thumbnail, an XMP segment and an ICC profile before its SOF, a few
hundred KiB at most. The walk seeks over each body, so it reads 4 bytes of each segment. Past the
bound the picture gets its size from its decode, as a picture of any other format does.

### 4.2 The size is a background cell of the picture

`Image` gets two fields:

- **`head_size`**: a background cell (`make_background_cell`) with the inputs `(path[], read_count[])`,
  the inputs of the pixel cell. Its work calls `read_image_size` for each path and answers the
  size, `nothing`, or the exception as a value, so one bad file fails no other. Its `apply` returns
  an `ApplyImageAnswerOperation` of the size (§4.3).
- **`decoded_count`**: a plain cell, the `read_count` whose decode answered, and −1 until the first
  decode answers.

Both are view state (`get_view_state_fields`): a save writes the path only, undo records none of
their changes, and a copy is a new picture that reads nothing.

The head cells of all pictures share one source, `_IMAGE_SIZE_SOURCE`, a constant of `StyleModule`
with the description "the sizes of pictures" (D6). The editor groups the demands of a frame by their
source (`_take_background_demands!`), so the sizes that one frame asks for are read on one task,
come back in one operation, and make one record in the work store. The source holds its work and its
description and no other value: the demands are in the `BackgroundDemands` of each editor, so two
editors read their sizes apart (PAR-PER-EDITOR-STATE). The pixels keep a source for each picture
(G3 D10).

`_make_image(filename, source, size_source = _IMAGE_SIZE_SOURCE)` takes the source of the sizes as
a third argument, so a test passes one whose work it counts. `Image(filename)` passes none, and no
public maker takes a source.

A script with no editor reads the size with `wait_for_cell!(getfield(picture, :head_size); editor =
nothing)` and then `picture.natural_size`.

### 4.3 Which answer wins

`ApplyImageAnswerOperation(image, read_count, answer, is_pixel_answer)` gets one field,
`is_pixel_answer::Bool`: `true` for the answer of the pixel cell, `false` for the answer of the
head cell. Its evaluation follows these rules, in this order:

1. The answer of a read that a newer read follows is dropped, by `read_count`, as now.
2. A pixel answer writes `decoded_count`, then the size of the pixels into `natural_size`, or the
   exception into `failure`, as now.
3. A size answer for a read whose decode answered is dropped: the decode wins (D4).
4. A size answer of `nothing` writes nothing.
5. A size answer `(width, height)` clears `failure` and writes `natural_size`. A size answer that
   is an exception writes `failure`.

Each rule writes a cell only when its value changes. So for one read the decode wins, whichever
answer comes first, and a newer read wins over an older one.

The decode wins because the paint draws the pixels of the decode into the box of the print, and a
box of another shape stretches them. The two can differ when a file changes between the two reads
and no watch reports it, for a picture that no file document holds. They can also differ for a
variant of a format that the reader reads otherwise than SDL_image, or for a later SDL_image that
composes the frames of a GIF on its screen or turns a JPEG by its EXIF orientation. Then the
picture moves once, at its decode, as every picture does today.

### 4.4 One function asks for the size

`get_image_natural_size(image::Image)` is the one function that a print calls for the size of a
picture. `StyleModule` exports it.

```julia
function get_image_natural_size(image::Image)
    image.decoded_count == image.read_count || image.head_size   # asks for the head of the file
    image.natural_size
end
```

It reads the head cell only while the decode of this read has not answered, so a picture whose
decode answered asks for no head (keep what the producer knew). In a computation of a frame, the
read of the head cell records a demand when the cell has no answer for its inputs. Outside an editor
it records nothing, as a read of the pixel cell does (`_record_background_demand!`).

| Reader | Today | After this plan |
| --- | --- | --- |
| `_image_payload(::Image)`, `WidgetToGraphics.jl:1283-1286` | `natural_size`, else 320 by 240 | `get_image_natural_size`, else 320 by 240 |
| the box under the pixels, `WidgetToGraphics.jl:1322-1324` | while `natural_size` is `nothing` or `failure` is set | while `decoded_count` is below 0 or `failure` is set: the box stands for pixels that have not come (§4.5) |
| `_make_shown_image_widget`, `ImageToWidget.jl:34-38` | the path below the box while `natural_size` is `nothing` | the path below the box while `get_image_natural_size` is `nothing` (D12) |
| `_md_image_value`, `MarkdownToSyntax.jl:487`; `_picture_leaf_value`, `BookToSyntax.jl:580`; `_rst_picture`, `RstToSyntax.jl:1239` | `natural_size`, else 720 by 460 | `get_image_natural_size`, else 720 by 460 |
| `_make_saved_picture`, omnet-julia `LegacyStoreEntryToWidget.jl:54` | `natural_size` | no change: the label inside the box asks for the size, so the box reads the size of the head (D13) |

Every label of a picture measures through `_image_payload`: a card or a tab of a picture file
(`ImageToWidget`), a cell of a roster (`make_roster_value_cell`) and the picture of a conversation.

### 4.5 Before the size, and before the pixels

Until the size answers, a print measures as today: a label is 320 by 240, a span is 720 by 460
capped at 640 wide, and `ImageToWidget` draws the path below the box (D9). The head work runs after
the frame (`EditorLoop.jl:115-122`) and takes microseconds (§4.7), so the next frame has the sizes.
The answer removes the path line and gives the label its size in that one frame.

The box under the pixels stays until the first decode answers. A picture whose head answered and
whose pixels have not come is a box of its true size, as row 3 of the example says. After a change
of the file, the old pixels draw until the new ones come, and no box shows, as now.

### 4.6 A change of the file

The head cell has the inputs of the pixel cell. A change adds one to `read_count` of the picture
(the drain, F5, `replace_wrapped_document!`). `get_image_natural_size` reads `read_count`, so the
print of the picture runs again. `decoded_count` is then older than `read_count`, so the print reads
the head cell. That cell has no answer for the new input: it answers its last size and records a
demand. A file of a new size gives the new size in the next frame, also for a picture off the
screen. An answer of the same size writes no cell.

### 4.7 The cost

- A head read takes 24 bytes of a PNG, 26 of a BMP, and the descriptors and the colour table of a
  GIF. A JPEG takes 4 bytes for each segment before its SOF and 9 bytes of the SOF. 60 reads of 24
  bytes take 72 µs on one task (§2).
- Each picture has one background cell and one plain cell more.
- The print of a picture reads `read_count` and `decoded_count`, so it runs again at each change of
  its file and at its first decode. That is the print of one label.
- A frame that asks for sizes adds one record to the work store, whatever the count of pictures.

### 4.8 What is not in this plan

- A format other than the four (D1). WebP, TGA, TIFF and SVG get their size from the decode.
- A picture that `write_image` or the PDF writer draws with no editor. A read with no editor records
  no demand, as in G3.
- The sizing of the image spans of Markdown, Book and RST. It is one rule in three copies: 720 by
  460, capped at 640 wide. Step 3 changes only how they read the size.
- The two sizes of a picture with no answer, 320 by 240 in a label and 720 by 460 in a span.
- The web backend, which reads every picture at its first paint (D11 of the layout plan).
- A wait for a whole file. A file document reads a change only when the file is whole
  (`_wait_for_settled_file`), and only then adds one to `read_count` of its picture, so the head
  read of a change finds a whole file.

## 5. Decisions

A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation. The owner can name one to see it first.

- **D0. A plan of its own.** Decided by the owner on 2026-11-09 (D12 of the layout plan, option B).
  A print asks for the size, and a task reads it from the head of the file with no decode. Only a
  paint asks for the pixels. The size is one more background cell of the picture, as the pixels are,
  so the plan adds no event, no payload and no channel. Rejected: option A, a picture gets its size
  with its pixels, and what is after it moves.
- **D1. A head reader for PNG, GIF, BMP and JPEG.** Decided by the owner on 2026-11-09 (question 1
  of this plan, option A): the formats that open as a picture file, `.png`, `.jpg`, `.jpeg`, `.bmp`
  and `.gif`. Any other format gets its size from the decode, as now. Rejected: option B, PNG only.
- **D2. The readers live in the style slice beside `Image`, as `read_image_size(path)` in
  `ImageHead.jl`** (§4.1). Proposed by the assistant. `Image` is their one caller, and the style
  slice holds a parser of a file format in plain Julia already (`TrueType.jl`). A head read draws
  nothing, so it needs no backend, and an editor with `HeadlessBackend` gets the sizes too. The name
  follows naming-rules.md: `read_` with no `!` is a pure read of outside state, as
  `read_os_clipboard` and `read_file_content`; the file is named for what it reads. Rejected: a
  second seam beside `decode_image` in the backend interface. That is a new interface, a change of
  `source/kernel/backend/BackendInterface.jl`, and a size that only an editor with a decoder gets.
  Rejected: a package that reads image formats. It is a new dependency of the platform. Rejected:
  `find_image_size`, because the function searches no collection, and `get_image_size`, because the
  value is in a file and not at a known place of a document.
- **D3. The size is a background cell `head_size`, and its answer goes through
  `ApplyImageAnswerOperation` into `natural_size`** (§4.2). Proposed by the assistant. It is the
  form of G3: a task reads the disk, the `apply` writes plain cells, and a print reads plain cells
  and asks through the background cell, as `demand_file_text` does. Rejected: the print reads the
  value of the head cell and keeps `natural_size` for the decode. A print then merges two values,
  a missing file needs a second way into `failure`, and a reader of `natural_size` such as
  omnet-julia gets no size from the head.
- **D4. The decode wins over the head for the same read, and a newer read wins over an older one;
  the picture keeps `decoded_count`** (§4.3). Proposed by the assistant. The paint draws the pixels
  of the decode, so the box must have their size. Rejected: the last answer wins. A file rewritten
  between the two reads, with no report, then stretches the pixels until the next read. Rejected:
  the head wins, for the same reason. Rejected: no count, with a reset of `natural_size` at a
  change. A picture that a program writes again would then fall back to 320 by 240 at each change,
  and the layout would move twice.
- **D5. One function asks for the size: `get_image_natural_size(image)`** (§4.4). Proposed by the
  assistant. The five readers of the size call it, and the sixth, the box under the pixels, reads
  `decoded_count` because it stands for the pixels. The function reads the head cell only while the
  decode of the read has not answered. Rejected: each reader reads the head cell itself, which is
  five copies of one rule. Rejected: a `natural_size` field whose cell computes from the head and the
  decode. The decode then can not write the field, and a field of a document that computes from two
  other fields is a new kind of view state.
- **D6. One source for the head reads of all pictures, a constant of `StyleModule`** (§4.2).
  Proposed by the assistant. A head read is a few bytes, and 60 of them take 72 µs on one task and
  39 µs on 60 tasks (§2). So one task loses nothing that matters, and the sizes of a frame come back
  in one operation and one record of the work store. The constant holds a function and a text and no
  other value; the demands and the batches belong to each editor, so it is no state of the process.
  G3 D10 rejected one source for the decodes, which take milliseconds each; it holds for the pixels.
  Rejected: a source for each picture, as for the pixels. A column of 60 pictures then starts 60
  tasks and adds 60 records to a work store that keeps 100, for a gain of 33 µs. Rejected: a source
  for each holder, which G3 D10 rejected because a picture does not depend on its first holder.
- **D7. A file that can not be opened writes its failure at once; a format with no head reader, and
  a head that does not parse, write nothing** (§4.1, §4.3). Proposed by the assistant. A missing
  picture off the screen then shows its failure, and its label takes the size of the text of the
  failure in the next frame and not at its first paint. A file that the head reader does not know
  can still decode, such as a WebP or a JPEG with its SOF past the bound, so only the decode can say
  that it fails. An empty file that a program is about to write is such a file, so it shows no
  failure too early. Rejected: a failure for each file that the reader does not know. Rejected: no
  failure from the head, which leaves a missing picture at 320 by 240 with its path until a paint.
- **D8. The signature in the first bytes chooses the reader, not the extension** (§4.1). Proposed by
  the assistant. `IMG_Load` reads the content, and `Image(path)` takes any path, such as the url of
  a Markdown image. A JPEG named `.png` then gets the size that its decode gives. Rejected: the
  extension, which gives no size, or a wrong one, for a file whose name is wrong.
- **D9. Before the size answers, a picture measures as today: 320 by 240 in a label, 720 by 460 in a
  span** (§4.5). Proposed by the assistant. The answer comes in the frame after the first print.
  Rejected: a size of 0, which draws nothing in the first frame and moves the layout as much.
  Rejected: a read in the print, because a print reads no disk.
- **D10. A change of the file reads the head again** (§4.6). Proposed by the assistant. The head cell
  has the inputs of the pixel cell, `(path, read_count)`, so a change is a new input, as for the
  pixels and the listing of a folder.
- **D11. The walk of a JPEG or a GIF stops at 1 MiB and answers `nothing`** (§4.1). Proposed by the
  assistant. The metadata before the SOF of a camera file is a few hundred KiB, and the walk seeks,
  so the bound costs 4 bytes for each segment. Past it the decode gives the size, as now. Rejected:
  no bound, which walks a large file with no SOF to its end on the task of the sizes of every
  picture of the frame. Rejected: 64 KiB, the largest single segment, which misses a file with an
  EXIF segment and an ICC profile.
- **D12. The path line of a picture with no answer goes when its size comes; the box under its
  pixels stays until its pixels come** (§4.4, §4.5). Proposed by the assistant. The path line is a
  row of `ImageToWidget` below the box, so it changes the height of the picture. If it went at the
  decode, the layout would move at the decode, which this plan prevents. The box keeps the place of
  the pixels visible until they come. Rejected: both go with the size, which leaves an empty place
  of the true size until the decode. Rejected: both go with the pixels, which moves the layout at
  the decode.
- **D13. omnet-julia needs no change** (§4.4). Proposed by the assistant. Its one reader reads
  `natural_size` around a label of the same picture, and the label asks for the size. No field that
  omnet-julia names changes its meaning, and `Image(path)` keeps its signature. So the plan has no
  sibling plan in omnet-julia, and step 4 checks that omnet-julia precompiles.

## 6. Steps

Each step is one commit with its test. No step changes a file under `source/kernel/` (§2). Each
test runs with `workspace/bin/bounded-run` in `environment/all` of the worktree. The work runs in a
worktree on a branch of its own, and nothing lands on main without the approval of the owner.

- [ ] **1. The head of a picture file gives its size (D1, D2, D8, D11).** A new fragment
      `source/platform/style/ImageHead.jl` holds `read_image_size(path)` and the four readers of
      §4.1. `StyleModule.jl` includes it before `Image.jl` (`:121`) and exports `read_image_size`
      (`:82`). Its docstring states the four formats, the answer and the bound. Test: the new
      `test_image_head()` in `test/platform/document/ImageHeadTest.jl`, which
      `ProjecturedPlatformTest` includes beside `ImageTest.jl` (`src/ProjecturedPlatformTest.jl:124`)
      and `test/platform/PlatformSuite.jl` calls and exports (`:193`, `:445`). The test writes each
      file byte by byte:
      - a PNG head of 640 by 480 gives `(640, 480)`;
      - a BMP with a header of 40 bytes of 7 by 5, the same stored top-down with a height of −5, and
        one with a header of 12 bytes of 7 by 5 each give `(7, 5)`;
      - a GIF with a screen of 20 by 10, a global table of 4 colours, a graphic control extension, a
        comment of 300 bytes in two sub-blocks and a first frame of 5 by 4 gives `(5, 4)`; a GIF with
        only its trailer gives `nothing`;
      - a JPEG with SOI, APP0, three APP1 segments of 65 535 bytes, fill bytes before a marker, DQT
        and an SOF0 of 1000 by 600 gives `(1000, 600)`; the same with SOF2 gives the same; a JPEG
        with its SOS before an SOF, one with an SOF of height 0, and one with 17 APP1 segments of
        65 535 bytes before its SOF give `nothing`;
      - a text file named `a.png`, a file of 3 bytes and a RIFF WebP head give `nothing`;
      - a path that does not exist throws a `SystemError`.

      Then a new testset of `test_image_file_read()` compares each reader with the decode: a PNG and
      a BMP that `write_image` writes, a JPEG of 7 by 5 that `IMG_SaveJPG` writes with three APP1
      segments of 65 535 bytes and an EXIF orientation of 6 put after its SOI, a BMP stored top-down
      and a GIF with a screen of 20 by 10 and a frame of 5 by 4, both written by the test. The LZW
      data of a GIF of one colour is a clear code before every two pixels, which keeps each code at
      3 bits. For each file, `read_image_size(path) == Int.(decode_image(path)[2:3])`.
- [ ] **2. A print asks for the size of a picture, and a task reads it from the head of its file (D3
      to D7, D9, D10, D12).** `Image.jl`: the fields `head_size` and `decoded_count`, the constant
      `_IMAGE_SIZE_SOURCE`, the third argument of `_make_image`, the field `is_pixel_answer` and the
      rules of §4.3 in `ApplyImageAnswerOperation`, `get_image_natural_size`, `get_view_state_fields`,
      and the docstring of `Image`. `StyleModule.jl` exports `get_image_natural_size`.
      `WidgetToGraphics.jl:1283-1286` and `:1322-1324`, and `ImageToWidget.jl:34-38` with its
      docstring (`:11-14`), follow §4.4. `_make_sized_picture_file` (`ImageTest.jl:96-102`) and
      `_itw_make_picture` (`ImageToWidgetTest.jl:16-21`) pass a size source that answers `nothing`,
      so the size that they set stays. The section "A picture of a file" of style.md
      (`style.md:353-361`) and row 6 of natural.md (`natural.md:82`) say what §4.2 to §4.6 say. Test:
      new testsets of `test_image()`:
      - a label printed in a frame of an editor asks for the size and not the pixels: after
        `start_background_cell_work!` and the drain, the size source has one call
        `[("a.png", 0)]` and the decode source none, `natural_size == (4, 3)`, the label is 4 by 3,
        and a box lies under its image;
      - the decode wins: with a size of 4 by 3 and pixels of 6 by 5, the head first and the decode
        first both end at `(6, 5)`, and a size answer after the decode runs no reader of
        `natural_size`;
      - a file that does not exist, printed through `ImageToWidget` in a frame, gets a `SystemError`
        in `failure` and draws its path and the reason, with no call of its decode source;
      - a file that holds the text `"not a picture"` gets no size and no failure from its head, and
        then the size of its decode;
      - one more `read_count` asks for the head again: the calls are `[("a.png", 0)]` and
        `[("a.png", 1)]`, a new size is written, and the answer of read 0 that comes after it is
        dropped;
      - a picture whose decode answered for its read asks for no head in a frame;
      - the view state fields are the eight of the new `Image`.

      Then `test_image_to_widget()`, `test_roster_table()`, `test_task_views()`,
      `test_external_agent_turn()`, `test_image_file_read()`, `test_dashboard_render()` and
      `test_layout_render()`.
- [ ] **3. An image span of Markdown, Book and RST asks for the size (D5).** The helpers of
      `MarkdownToSyntax.jl:487`, `BookToSyntax.jl:580` and `RstToSyntax.jl:1239` call
      `get_image_natural_size`, and the comment of the Markdown span (`MarkdownToSyntax.jl:481-483`)
      says that 720 by 460 holds until the size is read, not until the pixels are. Test: one new
      testset for each domain, in `test_markdown_image_leaf()`, in `test_book_to_syntax()`, and in a
      new `test_rst_to_syntax()` in `test/domain/rst/projection/RstToSyntaxTest.jl`, which
      `ProjecturedRSTTest` includes beside `RstThemeTest.jl` (`src/ProjecturedRSTTest.jl:47`) and
      `RstSuite.jl` calls and exports (`:23-31`, `:35-36`). Each prints the span of
      `asset/image/file.png`, 16 by 16, in a frame of an editor: it measures 640 by 409 before the
      answer, and 16 by 16 after the head answers, while its pixel cell has no read. The span makes
      its `Image` in the print, outside the cells that read the size, so the answer recomputes only
      those cells and makes no new picture: each set runs two more frames with no change and
      asserts that the size work ran once, with one value, and that the span keeps the same
      `Image`.
- [ ] **4. A column of 60 pictures has its true height before a paint (§1, the example of D12).** A
      new testset of `test_image_file_read()`, in a window of 1100 by 500 pixels as in
      `test_layout_render()`. `write_image` writes one PNG of 200 by 120 and one of 200 by 200, and
      the test copies them to 60 paths: picture `k` is 200 by 120 for an odd `k` and 200 by 200 for
      an even one. Each picture is `_make_image(path, source)` with a decode source that calls
      `decode_image` and records its path, and the size source of `Image`. The test uses `Image` and
      not `ImageFile`, because the read of a picture file (G3 D14) is not what it counts. The 60
      pictures are a `VerticalLayout` in a `WidgetScrollPane` that grows down, printed with
      `NaturalToGraphics` in a frame of an editor with `SdlBackend` and no video. The test asserts:
      - after the first frame, the work store holds one work "the sizes of pictures" with 60 values,
        and the decode source has no call;
      - after its answer, the column is as high as a column of 60 pictures of the same paths whose
        pixels `wait_for_cell!` decoded first: 30 × 120 + 30 × 200 = 9600 pixels of pictures, with
        the same insets in both;
      - a paint of the output reads the pixel cells of pictures 1 to 4 and no other, whose tops are
        at 0, 120, 320 and 440 pixels plus the insets of the labels;
      - picture 30 written again at 200 by 300, with one more `read_count`, gives one work with one
        value, a column 100 pixels higher, and no decode of picture 30;
      - a scroll to the end reads the pixel cells of pictures 58 to 60 and no other, and after their
        decodes the column keeps its height.

      Then `Pkg.precompile()` in omnet-julia against the branch (D13). Mark each step done, record
      what the work found, and move this plan to `plan/done/`.

## 7. Tests

The narrowest test of each step, in the order in which to run them:

| Step | First | Then |
| --- | --- | --- |
| 1 | `test_image_head()` | `test_image_file_read()` |
| 2 | `test_image()` | `test_image_to_widget()`, `test_roster_table()`, `test_task_views()`, `test_external_agent_turn()`, `test_image_file_read()`, `test_dashboard_render()`, `test_layout_render()` |
| 3 | `test_markdown_image_leaf()` | `test_book_to_syntax()`, `test_rst_to_syntax()` |
| 4 | `test_image_file_read()` | `Pkg.precompile()` in omnet-julia |

Each test asserts which pictures are read, by their numbers or their paths, and not only how many.
No step runs an aggregate suite.

## 8. Risks

- **A test that prints a picture of a path that does not exist in a frame of an editor now gets a
  failure before a paint (D7).** The two helpers of step 2 pass a size source that answers
  `nothing`. Another test of that kind shows a label of the failure where it had a box: step 2 runs
  `test_roster_table()`, `test_task_views()`, `test_image_to_widget()` and
  `test_external_agent_turn()` for this. `ImageTest.jl:431` reads a file that holds `"one"`, which
  the head does not know, so it keeps 320 by 240.
- **The path line of `ImageToWidget` goes with the size (D12).** A test that finds the path below a
  picture until its decode fails: `test_image_to_widget()` shows it.
- **One slow file holds the sizes of every picture of its frame (D6).** A file on a slow mount delays
  the task of the sizes, and the pictures of that frame keep 320 by 240 until it ends. The pixels
  have a source for each picture, so their decodes do not wait. The listing of a folder has the same
  form today.
- **The head and the decode differ (D4).** The picture moves once, at its decode. The comparison of
  step 1 fails when a new SDL_image decodes a GIF on its screen or turns a JPEG by its EXIF
  orientation, so the suite shows such a change.
- **A print of a picture runs again more often (§4.7).** It runs at each change of its file and at
  its first decode, because it reads `read_count` and `decoded_count`. That is the print of one label.
- **The spans of Markdown, Book and RST make a picture at each print.** Each new picture asks for its
  head once, a few bytes. A print that the answer of the size makes run again would make a new
  picture with no size, which asks again, without end. The span makes its picture outside the
  cells that read the size, so the answer runs only those cells; the sets of step 3 assert that
  the size work runs once. G4 steps 5 and 5a give each span the picture of its file and change the
  same three helpers; the plan that lands second keeps the call of `get_image_natural_size`.
- **An example with a picture shows its true size from its second frame.** A walk of an example in an
  editor, such as `test_example` of the widget example with `projectured.png`, sees the size of the
  head before the decode. The final size is the same.
- **omnet-julia.** Its reader reads a field that keeps its meaning, and `Image(path)` keeps its
  signature. A new export of `StyleModule` can meet a name of omnet-julia: step 4 runs
  `Pkg.precompile()` there.

## 9. Open questions for the owner

None. Each point that the plan had to settle is a proposed decision in §5, and the owner approves
them with the plan. D6 touches the rule that the editor keeps no global state: it adds a constant
that holds a function and a text, and no state. The owner can name it to see it first.
