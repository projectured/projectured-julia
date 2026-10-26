# A paste never holds the window

Status: PENDING, 2026-10-19. Not started. No decision is open.

## The ask

The owner, 2026-10-19, after the survey of the means of communication: "let's
plan this and also the smaller items". One small item: a paste starts the
clipboard tool of the system while the editor reads the key, so a tool that hangs
holds the window.

## The problem

A paste reads the clipboard of the system in a reader. The bindings of the
clipboard projection call `read_os_clipboard()` in three places
(`ClipboardSliceToAny.jl:184, 234, 304`), and the read runs `xclip`, `xsel`,
`wl-paste` or `pbpaste` with `read(cmd, String)` and no time limit
(`Clipboard.jl:7`). The reader runs on the owner task, so the frame waits for the
tool. The owner decided on 2026-10-15 that a reader reads nothing outside the
document, and that a read of outside state belongs to the evaluation of one
operation. A copy, a cut and a note already write the clipboard in an evaluation
(`WriteOsClipboardOperation`), but that write has no time limit either.

## The model

A toolkit of a window system reads the clipboard asynchronously: X11 asks the
owner of the selection and gets the answer as an event, Wayland reads a pipe, and
a browser answers a promise. The window never waits for the owner of the
clipboard. For the editor:

1. **The reader reads no clipboard.** A paste gesture answers one operation that
   names the place, the mode and the stored slice. The choice between the stored
   slice and the text of the system moves into its evaluation.
2. **The evaluation reads off the owner task.** It starts the read with
   `start_document_read!`. A read that ends inside the short wait of 50 ms pastes
   in the same evaluation, which is the usual case. A later answer pastes at the
   place that the gesture named, when that place still exists; else it pastes
   nothing and logs one line.
3. **A tool has a time limit.** A read or a write that does not end in 2 s is
   stopped, and the paste or the copy logs one line.
4. **The writes and the reads keep their order.** A write runs off the owner task
   too, after the write before it, and a read waits for the last write. So a copy
   and a paste at once paste what was copied.

The stored slice of the clipboard projection is a value in the document, so a
paste of it needs no read and pastes at once, as today.

## Steps

1. [ ] **The read, the write and the time limit.** The paste operation and its
   evaluation; the time limit and the order of the tool calls in `Clipboard.jl`;
   the bindings answer the operation. Tests: `test/platform/projection/ClipboardTest.jl`,
   `test/projectured/projection/TextClipboardTest.jl`, the clipboard cases of
   `test/projectured/editor/ApplicationTest.jl`, and new tests: a backend that
   answers after 0.2 s pastes in a later frame while the frames go on; a backend
   that does not answer gives no paste and one log line after 2 s; a copy and a
   paste in one frame paste the copied text.
2. [ ] **The guides.** `documentation/package/platform/clipboard/clipboard.md`, and
   the row of the clipboard in `documentation/design/communication-anatomy.md`. The
   plan moves to `plan/done/`.

## Not in this plan

- The clipboard of a web backend. It has no system tool.

## As built

Nothing yet.
