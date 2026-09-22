# Inspector

> **Kind:** design · **Status:** current · **Stands on:** [reference.md](../kernel/reference.md), [screen.md](../screen/screen.md), [natural.md](../natural/natural.md)

`ProjecturedInspector` shows a reference in a form that a person can read: the compact path and a sentence that says what it names. It has two documents, `ReferenceInspector` for one reference and `SelectionInspector` for a selection, and a probe that opens a reference inspector for what a click under the pointer would select. This document says how the three parts work, how they share one rendering, and what the probe does wrong.

## How it works

### The reference inspector

`ReferenceInspector(; reference, target)` pairs a `Reference` with the document that it is read against. `ReferenceInspectorToText` prints it as one `TextBlock` with two sections:

1. **Compact**: the reference printed as Julia on one colored line, by `ReferenceToText`.
2. **Human-readable**: the steps in reverse order as English, by `ReferenceToHumanReadableText`.

Before it prints, the projection adds a `TypeReferenceStep` for each step with `annotate_reference_types(target, reference)`. So the compact form shows the `::Type` of each step, and the sentence names the parent type of each step. [reference.md](../kernel/reference.md) describes both renderings. The text is a computed cell that reads `reference` and `target`, so it follows a change of either.

Both maps of the projection return `nothing`. A click in the panel names a place in the text and not a place in the inspected document, so it makes no operation.

### The selection inspector

`SelectionInspector(source)` shows a selection. The type of `source` picks which one:

| Written as | Shows |
| --- | --- |
| `SelectionInspector()` | the selection of the editor |
| `SelectionInspector(reference)` | that reference, fixed |
| `SelectionInspector(() -> get_selection(other))` | what the function returns, computed again when it changes |
| `SelectionInspector(other)` | the selection of the document `other` |

A function becomes the thunk of a `ComputedCell` in the `source` field. So a read of `source` runs the function again when a cell that it read changed, and the view follows another document with no cell in the printer.

`SelectionInspectorToText` holds a `ReferenceInspectorToText` and gives it all the rendering. Its computed text reads `source`, makes a `ReferenceInspector` with `find_inspected_selection(source, root)` and `get_inspected_document(source, root)`, and prints that. `root` is the document of the editor, which the editor puts into the printer context under `:root`. A `nothing` source falls back to `root`, and a reference is read against `root`. So the words of a step are written in one place.

### The hover probe

`HoverProbeProjection(; inner, pointer, id, offset, size, title)` wraps the content projection of a window. It prints as `inner` and maps references as `inner`. On a `MouseMove`, its reader:

1. makes a plain left `MousePress` at the pointer and reads it through `inner`, without applying the answer;
2. takes the path of the `ReplaceSelectionOperation` that comes back, if any;
3. returns an `OpenWindowOperation` with `style = :tooltip` and a `ReferenceInspector(reference = path, target = document)` as content, at `pointer()` plus `offset`;
4. returns a `CloseWindowOperation` when the press selects nothing and the window is open.

An open with the same `id` updates the window in place, so the window follows the pointer. `WindowManagingProjection` applies the two operations; see [screen.md](../screen/screen.md). `pointer` is a function that returns the pointer in screen coordinates, so the package has no dependency on a backend. Every other event goes to `inner`, so a real click, a key, a scroll and a drag edit as before.

The press has no Alt key, so the probe shows the reference that a click makes: a caret in a text, or the selection of a node. A press on a button returns the action of the button, so the probe shows nothing there. The tooltip probe uses an Alt+press instead, because it looks for a document; see [tooltip.md](../tooltip/tooltip.md).

## How it fits

The code is in `source/inspector/`, one file for each document and each projection, and `HoverProbe.jl` for the probe. `ProjecturedInspector` depends on the kernel and on `ProjecturedDomain`, `ProjecturedNatural`, `ProjecturedProjection`, `ProjecturedScreen`, `ProjecturedSerialization`, `ProjecturedStyle` and `ProjecturedText`. It names no domain: it reads a `Reference` and a `Document` of any kind.

Its `__init__` registers the rows of the renderer kind `:inspector` with `register_natural_graphics!`. Each of the two documents draws through its text projection, `WordWrapping` and `TextToGraphics`. It also registers both documents as `.pred` types. `pred_arguments` of both writes nothing: what a reference inspector holds is a moment of the pointer, and a function source can not be written as notation. So a loaded inspector starts empty, and a loaded selection inspector follows the editor.

Both documents have a title, "Reference" and "Selection", and an insertion name, `reference` and `selection`, so a person can open one by its name in an empty tab. The toolbar of `ProjecturedShell` has a Selection tool that opens a `SelectionInspector`; see [shell.md](../shell/shell.md). The gallery wraps a window in a `HoverProbeProjection` with `run_example(…; inspector = true)`.

## Design decisions

- **The panel shows what a click would select, not the selection.** A person sees the reference before the click, and the probe does not change the document or its selection. See `plan/done/hover-click-reference-inspector.md`.
- **Two forms, one rendering.** `ReferenceInspectorToText` prints both forms, and `SelectionInspectorToText` only chooses the reference. So a change of the words of a step is made in one place.
- **A source can be a function.** The view then follows any selection with no cell of its own. The cost is that the function is not saved; a view that must follow a document after a load takes the document form.
- **The probe is a window.** The panel can extend past the window that it describes, as a tooltip does. See [tooltip.md](../tooltip/tooltip.md).

## Usage

```julia
inspector = ReferenceInspector(reference = @reference(document, entries[1].value),
                               target = document)
SelectionInspector()                                  # the selection of the editor
SelectionInspector(() -> get_selection(other))        # follows another document
probe = HoverProbeProjection(; inner = content_projection,
                             pointer = () -> get_pointer_position(backend))
run_example("json"; inspector = true)
```

`document`, `other`, `content_projection` and `backend` stand for your own values.

- Tests: `test_reference_inspector_text()`, `test_hover_probe()` and `test_hover_probe_pipeline()` in `test/projectured/projection/HoverProbeTest.jl`, and `test_selection_inspector()` in `test/projectured/projection/ToolViewTest.jl`. The package has no suite of its own.

## Limits

- The probe takes every `MouseMove` and does not pass it on. So a hover highlight or a drag of a divider below the probe gets no move. The tooltip probe has the same fault, and `plan/pending/hover-drag-and-tooltip-share-the-pointer.md` describes it and a fix.
- The probe and the tooltip probe do not compose: `run_example` raises an error for `inspector = true` with `tooltip = true`, and for either one with `clipboard = true`.
- The probe reads the whole chain again on each move, with no delay.
