# Inspector

> **Kind:** design · **Status:** current · **Stands on:** [reference.md](../../kernel/reference.md), [natural.md](../natural/natural.md)

The inspector slice of `ProjecturedPlatform` shows a reference in a form that a person can read: the compact path and a sentence that says what it names. It has two documents, `ReferenceInspector` for one reference and `SelectionInspector` for a selection. This document says how the two parts work and how they share one rendering.

## How it works

### The reference inspector

`ReferenceInspector(; reference, target)` pairs a `Reference` with the document that it is read against. `ReferenceInspectorToText` prints it as one `TextBlock` with two sections:

1. **Compact**: the reference printed as Julia on one colored line, by `ReferenceToText`.
2. **Human-readable**: the steps in reverse order as English, by `ReferenceToHumanReadableText`.

Before it prints, the projection adds a `TypeReferenceStep` for each step with `annotate_reference_types(target, reference)`. So the compact form shows the `::Type` of each step, and the sentence names the parent type of each step. [reference.md](../../kernel/reference.md) describes both renderings. The text is a computed cell that reads `reference` and `target`, so it follows a change of either.

Both maps of the projection return `nothing`. A click in the panel names a place in the text and not a place in the inspected document, so it makes no operation.

### The selection inspector

`SelectionInspector(source)` shows a selection. The type of `source` picks which one:

| Written as | Shows |
| --- | --- |
| `SelectionInspector()` | the selection of the editor |
| `SelectionInspector(reference)` | that reference, fixed |
| `SelectionInspector(() -> get_selection(other))` | what the function returns, computed again when it changes |
| `SelectionInspector(other)` | the selection of the document `other` |

A function becomes the computation of a cell in the `source` field. So a read of `source` runs the function again when a cell that it read changed, and the view follows another document with no cell in the printer.

`SelectionInspectorToText` holds a `ReferenceInspectorToText` and gives it all the rendering. Its computed text reads `source`, makes a `ReferenceInspector` with `find_inspected_selection(source, root)` and `get_inspected_document(source, root)`, and prints that. `root` is the document of the editor, which the editor puts into the printer context under `:root`. A `nothing` source falls back to `root`, and a reference is read against `root`. So the words of a step are written in one place.

### The theme

`InspectorTheme` holds the font of the inspector and the font and the color of its header. Each value has the default that the slice draws with no
appearance. `ReferenceInspectorToText` holds its fonts and its header color as fields, and no theme;
`make_reference_inspector_projection(; theme, reference_theme)` fills them from an `InspectorTheme`, scaled or not,
and `SelectionInspectorToText` builds through it. With no theme they hold the default values. The tokens of a reference take the colors of `ReferenceTheme` of the text slice. The registration of the inspector gives both scaled themes of the `Appearance`, and the text theme to its `TextToGraphics`.

## How it fits

The code is in `source/platform/inspector/`, one file for each document and each projection. The inspector slice depends on the kernel and on the domain, natural, projection, serialization, style and text slices. It names no domain: it reads a `Reference` and a `Document` of any kind.

Its `__init__` registers the rows of the renderer kind `:inspector` with `register_natural_graphics!`. Each of the two documents draws through its text projection, `WordWrapping` and `TextToGraphics`. A `.pred` file builds both by their names, as it builds any loaded document type. `pred_arguments` of both writes nothing: what a reference inspector holds is a live reference and the document it points into, not data to save, and a function source can not be written as notation either. So a loaded inspector starts empty, and a loaded selection inspector follows the editor.

Both documents have a title, "Reference" and "Selection", and an insertion name, `reference` and `selection`, so a person can open one by its name in an empty tab. The toolbar of the shell slice has a Selection tool that opens a `SelectionInspector`; see [shell.md](../shell/shell.md).

## Design decisions

- **Two forms, one rendering.** `ReferenceInspectorToText` prints both forms, and `SelectionInspectorToText` only chooses the reference. So a change of the words of a step is made in one place.
- **A source can be a function.** The view then follows any selection with no cell of its own. The cost is that the function is not saved; a view that must follow a document after a load takes the document form.

## Usage

```julia
inspector = ReferenceInspector(reference = @reference(document, entries[1].value),
                               target = document)
SelectionInspector()                                  # the selection of the editor
SelectionInspector(() -> get_selection(other))        # follows another document
```

`document` and `other` stand for your own values.

- Tests: `test_reference_inspector_text()` in `test/projectured/projection/ReferenceInspectorTest.jl`, and `test_selection_inspector()` in `test/projectured/projection/ToolViewTest.jl`. The package has no suite of its own.
