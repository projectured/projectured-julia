# WorkbenchEditor file keybindings (Ctrl+S save / Ctrl+O reload)

## Goal

Bind **Ctrl+S** (save) and **Ctrl+O** (reload) on a `WorkbenchEditor` tab so the
tab's `content` is written to / re-read from its `filename`, with the on-disk
format chosen by the file extension. A tab opened on a non-existent file starts
as an extension-guessed **insertion** seed, so it can be typed into and then
saved. This makes the save/load/import/export operations
([plan/done/document-load-save-import-export.md](../done/document-load-save-import-export.md))
reachable from the keyboard for the first time.

`WorkbenchEditor` ([Workbench.jl](../../package/domain/src/document/Workbench.jl))
is the natural home: it is the "open document tab" type and already carries both
`content::Any` and `filename::String`. `make_workbench_document(doc; title,
filename)` ([Wrapper.jl](../../package/example/src/document/Wrapper.jl)) wraps
editor content in one, and `build_file_editor(...; workbench=true)`
([FileEditor.jl](../../package/example/src/FileEditor.jl)) uses that path.

## Key mechanism (how the gesture fires)

The generic 3-arg reader ([Projection.jl:87](../../package/kernel/src/common/Projection.jl#L87))
already delegates a raw `KeyDown`/`KeyPress` to `document_read(iomap.input,
gesture)` for any projection **without** a bespoke reader — that is how every
`@gestures` table fires. `WorkbenchEditorToWidgetScrollPane` *overrides*
`projection_read` (to retarget content ops), so its `WorkbenchEditor` input never
gets that delegation. But raw events **do** reach it: the workbench shell reader
routes `KeyDown`/`KeyPress` through each panel
([WorkbenchToWidget.jl:697](../../package/domain/src/projection/primitive/WorkbenchToWidget.jl#L697)),
and `ContentIoMap.input` is the `WorkbenchEditor` itself.

**Fix:** in `WorkbenchEditorToWidgetScrollPane.projection_read`, when the payload
is a raw `KeyDown`/`KeyPress`, first try `document_read(iomap.input, event)`;
return its operation if non-`nothing`, else fall through to the existing
`_retarget_panel_op` (content path). This is a one-branch addition that lights up
`@gestures WorkbenchEditor`.

## Operations (carry the tab, like ToggleCollapseOperation)

`@gestures WorkbenchEditor` emits **self-contained** operations that carry the
`WorkbenchEditor` directly, so they bubble up through every wrapping reader
(page → workbench → window → screen) unchanged (`prepend_steps_to_op` leaves
target-carrying ops alone) and are applied by `evaluate_operation`:

```julia
struct SaveWorkbenchEditorOperation <: Operation; editor::WorkbenchEditor; end
evaluate_operation(ed, op) = write_document_file(op.editor.content[], op.editor.filename[])

struct ReloadWorkbenchEditorOperation <: Operation; editor::WorkbenchEditor; end
function evaluate_operation(ed, op)                 # reactive content swap
    op.editor.content = read_document_file(op.editor.filename[])
    op.editor.selection = nothing
end
```

`@gestures`:
```julia
@gestures WorkbenchEditor begin
    KeyDown(:s; ctrl) => "Save file"   => SaveWorkbenchEditorOperation(doc)
    KeyDown(:o; ctrl) => "Reload file" => ReloadWorkbenchEditorOperation(doc)
end
```

## Format-by-extension file IO (bridges binary + natural + insertions)

A small helper set — new `serializer/DocumentFile.jl` — is the single source of
truth for "read/write a document file", dispatching on extension across the two
formats built already plus the insertion seeds:

| ext | write | read (exists) | read (missing) |
|-----|-------|---------------|----------------|
| `.pdoc` | `save_document` (binary) | `load_document` | `DocumentNothing()` |
| `.json` | `export_document` | `import_document` | `JsonInsertion()` |
| `.xml` | `export_document` | `import_document` | `XmlInsertion()` |
| `.sql` | `export_document` | `import_document` | `SqlInsertion()` |
| `.jl` | `export_document` | `import_document` | `JuliaInsertion()` |

- `write_document_file(doc, path)` — binary for `.pdoc`, natural export otherwise.
- `read_document_file(path)` — if the file exists, binary/natural by ext; if
  missing, `new_document_for(path)` (the insertion seed, so a new file opens
  editable). Reload of a still-missing file re-seeds.
- `new_document_for(path)` — extension → insertion (the empty-seed registry the
  earlier "new file guesses content" requirement asked for).

## FileEditor registry integration

`EDITOR_DOMAINS` ([FileEditor.jl](../../package/example/src/FileEditor.jl))
currently has only `:json` with `save_file = nothing`. Fill in `save_file` and
add `:xml`/`:sql`/`:jl`, using `read_document_file`/`write_document_file` (or the
domain parsers) and the insertion `make_empty_document`s. The v1 note in that
file ("a serializer can be dropped in later without changing anything here") is
exactly this drop-in.

## Placement / load order

```
serializer/DocumentFile.jl   NEW  write/read/new_document_for (needs both serializers + insertions)
editor/WorkbenchFile.jl      NEW  Save/Reload ops + evaluate + @gestures WorkbenchEditor
projection/.../WorkbenchToWidget.jl  EDIT one raw-event → document_read branch
example/src/FileEditor.jl     EDIT registry save_file + domains
```

`DocumentFile.jl` and `WorkbenchFile.jl` include **after** the serializers and
`WorkbenchToWidget`. The reader-hook edit needs only `document_read` (already in
scope in WorkbenchToWidget).

## Testing (headless, narrow)

- **Gesture fires + writes:** build `make_workbench_document(jsonparse("{...}"),
  filename="x.json")`, print through the workbench→widget→screen pipeline, feed
  `Change(EventEnvelope(win, KeyDown(:s; ctrl)))` to the composed reader, assert
  it yields a `SaveWorkbenchEditorOperation`, `evaluate_operation`, and the file
  appears with the exported text.
- **Reload:** change the file on disk, fire `Ctrl+O`, assert `tab.content`
  swapped to the re-read document.
- **New file → insertion:** `read_document_file("nope.sql")` is a `SqlInsertion`;
  `.json`→`JsonInsertion`, etc.
- **Format-by-extension unit:** `write_document_file` picks binary for `.pdoc`,
  natural for `.json`.

## Out of scope (noted)

- "Save As" / a file picker for an *empty* `filename` (needs the deferred picker
  projection).
- Non-workbench (`run_file_editor` without `workbench=true`) keybindings — the
  content isn't wrapped in a `WorkbenchEditor` there, so it has no filename-
  bearing tab; a window-level binding is a separate follow-up.
- Dirty/modified tracking and unsaved-changes prompts.
