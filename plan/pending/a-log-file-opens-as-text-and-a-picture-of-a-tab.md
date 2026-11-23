# A log file opens as text, and a picture of a tab

This is W3 and W1 of step 6 of
[the-editor-for-the-assistant-of-the-catch-up.md](the-editor-for-the-assistant-of-the-catch-up.md).
The owner chose them first on 2026-11-23.

## W3: a `.log` file opens as plain text

Now `TextFileFormat` has the extensions `.txt` and a name with no extension. A text file
opens as plain text, and the find bar of the tab searches in it. `.log` has no format,
so the editor cannot open the walk log.

The design: `.log` is an extension of `TextFileFormat`, so a `.log` file opens as a
`.txt` file does, with the icon of a text file. A filter that shows only the lines that
match is not in this plan: it needs a log as a list of lines, and care with the memory
of a large log that grows.

## W1: a picture of one tab

Now the tool `take_picture` has `part = "window"` or `"selection"`. Only a tool can give
an image to the assistant. A selection of a whole tab maps to the page of the tab:

- a tab that is shown maps to the canvas of its group, so the picture holds the tab
  strip and the page;
- a tab that is not shown maps to nothing, and the picture code goes up to the group,
  so the picture shows the tab that is shown, with no error.

The assistant does not select (`set_selection!` is a name of the person), so a
selection does not give the assistant a picture of a tab that it chooses.

The design is open: the owner asked on 2026-11-23 whether a tab works with a selection
that points at the tab, and the answer goes to the owner first.

## Steps

1. ⬜ `.log` is an extension of `TextFileFormat`, with the icon of a text file. A check
   in `test_text_file`.
2. ⬜ W1, after the decision of the owner.

## State

Open.
