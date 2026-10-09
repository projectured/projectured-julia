# Examples for the plain value forms and the find bar

> **Status (2026-10-09): DONE** on the branch `feature-examples`, in the
> worktree `projectured-julia-feature-examples`. Not on main. The owner asked for an example of
> each feature of the two plans of 2026-10-08 that has none yet:
> [a-form-edits-a-plain-value.md](../done/a-form-edits-a-plain-value.md) and
> [text-projection-config-into-document.md](../done/text-projection-config-into-document.md).

## What exists

Registered examples on main 023f66488:

- `text_highlighting`, `text_filtering`: a `HighlightedText` and a `FilteredText`
  around a text, without a bar.
- `object_to_widget`, `nested_object_to_widget`, `chart_inspector`,
  `sequencechart_inspector`: `ObjectToWidget` with its defaults.
- `object_field_form`: a hand-laid form of bare fields of two objects.
- `plain_server_copy_form` (A), `plain_server_cell_form` (B),
  `object_field_widget_form` (C, with a text, a spin box and a switch).
- The gallery flags `text_highlighting = true` and `text_filtering = true` wrap a
  text example in a `FindBarView`.

## What is missing

- A registered find bar view, for find and for filter. Its overlay button, its keys
  Ctrl+F and Escape, the dormant caret and the solid card are reachable in it.
- A filter around a highlight.
- `ObjectToWidget` with `make_widget`, and with `is_record` on a plain nested value.
- A form of bare fields whose table chooses the widgets
  (`make_object_field_widget_dispatch(...; make_widget)`).
- A plain mutable value that a form changes in place.
- A field in the value slot of a select (with its popup), a radio group, a slider,
  a toggle and a checkbox.

## Steps

Each step is one commit. Check each new example with `walk_printer_output` and
`walk_repl_loop`, which must report no error. `test_example` fails the type-ins of
every widget example on main, so its counts are a record and no gate.

1. ✅ **The find bar.** `make_find_bar_document` and `make_find_bar_projection` move
   from the gallery examples to the platform examples, so one function builds the
   bar for the gallery and for the new examples. Register `find_bar` and
   `filter_bar`.

   Done: `FindBarViewDocumentExample.jl` and `FindBarViewProjectionExample.jl` in
   `example/platform/`; the text is `_make_lorem_lines_block()`, which the filter
   example shares.
2. ✅ **A filter around a highlight.** Register `highlighted_filtered_text`.

   Done: the filter keeps the lines with a word that starts with "do" (`\bdo`,
   a regular expression), and the highlight marks "DOLOR" with case ignored.
3. ✅ **`ObjectToWidget` arguments.** Register `object_to_widget_chosen_widgets`
   (`make_widget`) and `object_to_widget_plain_record` (`is_record`).

   Done: the chosen widgets are a switch, two spin boxes and a toggle on the nested
   settings; the plain record is a `PlainResolution` in a `ProjectorSettings`. The
   three chains of `ObjectToWidget` share `_make_object_form_chain`.
4. ✅ **A form of bare fields with chosen widgets.** Register
   `object_field_form_chosen_widgets`.
5. ✅ **A plain mutable value in place.** Register `plain_server_mutable_form`.
6. ✅ **The value widgets.** `object_field_widget_form` gets a checkbox, a select, a
   radio group, a slider and a toggle, each with a field of the plain server.

   Done, steps 4 to 6 in one commit, because they edit the same files. The form of
   bare fields chooses a spin box and a switch in `make_object_field_widget_dispatch`;
   the mutable server is a `PlainMutableServer` in a cell; the plain server gets the
   fields `mode`, `priority`, `load` and `pinned`. Found: a radio group whose
   `selected` holds a field stores the option itself, not its index, so `priority`
   holds a string. A probe through an editor checks one feature of each new example:
   a key in the find bar, the lines of the filter around the highlight, a copy of the
   plain record, an edit in place, the checkbox, the radio group and the toggle on
   their fields. `walk_printer_output` and `walk_repl_loop` report no error on the
   thirteen new and changed examples; the guards of `test/suite` pass.
7. ✅ Move this plan to `plan/done/`.

## Decisions

The choices of the implementation, recorded in the steps: the two functions of
the find bar move to the platform examples (step 1); steps 4 to 6 share one commit
(step 6).
