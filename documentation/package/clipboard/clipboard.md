# Clipboard

> **Kind:** design · **Status:** current · **Stands on:** [projection.md](../projection/projection.md), [document.md](../kernel/document.md), [domain.md](../domain/domain.md)

`ProjecturedClipboard` adds copy, cut, note and paste to any document, a view of what the clipboard holds, and a bridge to the clipboard of the operating system. It works for every domain without a line of code in the domain. This document says how the wrapper stays out of the view, which rules decide where a paste can go, and why a copy is a deep copy.

## How it works

The clipboard is a wrapper document around the whole content of a window:

- `ClipboardSlice` has `content` and `slice`, the one stored document.
- `ClipboardCollection` has `content` and `elements`, a list of stored documents.

`ClipboardSliceToAnyProjection` prints both the content and the slice. Its output is a computed cell that chooses one of them by the `display_slice` cell. So Ctrl+/ toggles the view with a plain cell write, and the chain prints again only the stages after the clipboard. The output has no node for the clipboard itself: a reference forward loses the `content` or `slice` step, and a reference backward gets it again.

The reader has seven gestures, in a gesture table of the projection:

| Key | Gesture | What it stores or does |
| --- | --- | --- |
| Ctrl+C | copy | a deep copy of the selected document, with no selection |
| Ctrl+Shift+C | copy the reference | Julia code that gives the selected document, as text |
| Ctrl+X | cut | the selected document itself; the source becomes `DocumentNothing()` |
| Ctrl+N | note | the selected document itself, not a copy: a live bookmark |
| Ctrl+V | paste | the stored document replaces the selection |
| Ctrl+Shift+V | paste a copy | a copy of the stored document replaces the selection |
| Ctrl+/ | toggle | shows the stored document instead of the content |

A key that is not in the table goes to the content, and the reader roots the operation that comes back under `content`. `ClipboardCollectionToAnyProjection` has the same shape for a list: Ctrl+= adds the selected document to the list, Ctrl+- removes the selected element, and Ctrl+* shows the list.

The clipboard reads its own `selection` field only, never its content's. Every write of the live selection starts at the root, so by the time a key reaches the clipboard, its own suffix already names what was selected (`PAR-SELECTION-WRITTEN-AT-ROOT`; see [selection.md](../kernel/selection.md#writing-from-outside-a-gesture)).

### Where a paste can go

A paste replaces a whole document. Three checks decide whether the selection can take it:

1. The selection names a whole document, not a caret or a character range. A caret goes to the text reader of the content.
2. Every document from `content` down to the target accepts a pasted document: `accepts_pasted_document` of `ProjecturedDomain`.
3. The cell of the slot accepts the value, and the document there accepts a replacement: `accepts_pasted_replacement`. A field in an `ImmutableCell` does not.

A selection that ends in a character range of a text or number field is different. Copy, cut and paste then act on the characters of that field with `ReplaceStringRangeOperation` and `ReplaceNumberRangeOperation`. This is how Ctrl+C and Ctrl+V work in a text field of a form.

`find_clipboard_document(document)` returns the document that a selection copies. The default is the document itself. `ProjecturedPane` adds a method, so the selection of a tab copies the content of the tab and not the frame around it.

### The reference

Ctrl+Shift+C answers `CopyReferenceOperation`, which holds the clipboard and no path, so it travels up the chain unchanged. When it runs, it reads the complete selection from the root document of the editor, and drops steps from the end until the path names a document: a caret inside a text names the document that holds the text. It writes this code into the slice as a `PrimitiveString` and onto the system clipboard:

    evaluate_reference(editor.document, @reference(editor.document, <path>))

`make_reference_code(reference)` makes the code. The path is the `show` of the reference without its type checkpoints, and `@reference` with the document types it again. In an evaluator, where `editor` is bound, the code gives the selected document itself. A paste at a caret types the code, in this editor or in another program. The operation writes no document, so its inverse is `DoNothingOperation()`.

### The copy

`ClipboardCopyPolicy` is the `CopyPolicy` of a copy; [document.md](../kernel/document.md) describes the copy of a document under a policy. It goes into every document that accepts a paste. A document that does not accept a paste, such as a tool, is copied as its declared duplicate (`make_document_duplicate`). One policy object copies one tree and remembers each copied node, so a node that the tree reaches twice is copied once.

### The operating system

`make_clipboard_projection(…; to_text, from_text)` connects the clipboard to the operating system. A copy then adds a `WriteOsClipboardOperation` with the text form of the document, and a paste with an empty slice reads the system clipboard. `read_os_clipboard` and `write_os_clipboard!` call the first tool that is installed: `xclip` or `xsel`, `wl-paste` or `wl-copy`, `pbpaste` or `pbcopy`. With no tool they return `nothing` and `false`. The inverse of the write is `DoNothingOperation()`, because the system clipboard is not part of the document. `set_os_clipboard_backend!` puts a fake in place for a test.

With `text = true` over a `TextBlock` content, the clipboard copies and pastes character ranges only, and never a node.

## How it fits

`ProjecturedClipboard` depends on `ProjecturedDomain` for the paste hooks, `ProjecturedText` for the text mode, `ProjecturedCollection` and `ProjecturedProjection`. `ProjecturedPane` depends on it. Its `__init__` registers the two wrappers as `.pred` types; `pred_arguments` saves only `content`, so a loaded window starts with an empty clipboard.

`make_clipboard_projection` builds a chain of two stages: the clipboard, then your projection in a `NestingProjection`. The clipboard can not be the last stage of a chain, because its output is a cell.

## Design decisions

- **The wrapper is not in the view.** The view of a wrapped document is the view of the document, so a test or a later stage sees no difference. See `plan/done/clipboard-to-t.md`.
- **The toggle is a cell write.** It needs no new print of the stages before it. `ProjecturedVersioning` uses the same pattern; see [versioning.md](../versioning/versioning.md).
- **Copy and note are two gestures.** A copy can go anywhere without an alias; a note keeps the live object, for example a tool.
- **The paste rules come from the documents.** A domain blocks a paste with a method of `ProjecturedDomain`; the clipboard has no list of types. See `plan/pending/select-a-widget-and-paste-it-into-a-tab.md`, whose clipboard steps are done.
- **The bridge calls a command.** `InteractiveUtils.clipboard` also calls a command, and a new dependency on `InteractiveUtils` would change the manifests of the whole workspace. See `plan/done/clipboard-os-bridge-and-run-example-wrapper.md`.

## Usage

```julia
document   = make_clipboard_document(make_json_document_example())
projection = make_clipboard_projection(make_json_projection_example())
run_example(document, projection; name = "clipboard")
run_example("json"; clipboard = true)     # the same wrapper, from the gallery
```

- Example: `clipboard_example`. The general sweeps skip it, because its display cell keeps state between tests.
- Tests: `test_clipboard()` and `test_text_clipboard()`.

## Limits

- The text mode copies a range inside one span only. A range across lines returns `nothing`.
- In the gallery, `clipboard = true` can not go with `tooltip = true` or `inspector = true`.
- A reference is a path, so a reference through an index goes stale when the tree changes shape, for example when the tabs are moved.
- A paste of text reads the complete selection. A tool that the toolbar of the application opens leaves that selection unwritten from the root, so Ctrl+V into it does nothing until a click places the caret.
