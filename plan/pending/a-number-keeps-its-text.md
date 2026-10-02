# A number keeps the text that a person types

Status: a plan, not started. Written 2026-10-02 at the owner's word, in the
review of phase 4 of [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md):
"fix the number instead" (the alternative was a string document that the data
frame view keeps for the text of a number cell). The choice of §3 is for the
owner.

## 1. The problem

A number document holds a number or `nothing`, and nothing else:

- `PrimitiveNumber.value::Union{Number, Nothing}` (primitive slice),
- `JsonNumber.value::Union{Real, Nothing}` (JSON),
- `YamlNumber.value::Union{Real, Nothing}` (YAML).

A key in a number makes a `ReplaceNumberRangeOperation`. Its evaluation splices
the print of the value and parses the result with `splice_number`
([Operations.jl](../../source/kernel/operation/Operations.jl)): an `Int` when it
parses as one, a `Float64` when it parses as one, and `nothing` for an empty or
an unparseable text. The printers show `string(value)`. So, from the code:

- `-` and `1e` become `nothing`, and the number shows its placeholder. The minus
  sign and the `1` are lost, so a person can not type `-5` or `1e5`.
- `12.` becomes `12.0`, and the number shows `12.0`. The caret stands before the
  `0` that the person did not type.
- `1.50` becomes `1.5`, and the last key does not show.

A data frame cell that a person edits as a number document needs to hold `1e`
until the next key, and a cell with a text that does not parse keeps it, with a
mark, after the commit (§3.6 of the data frame plan). JSON and YAML have the same
gap today.

## 2. The goal

A number document shows the text that a person typed, character for character,
and its value is the parse of that text, or `nothing` while the text does not
parse. An empty text and a text that does not parse are two different states.

## 3. The design: where the text lives

**Recommendation (mine): the text is the field that is kept, and the value is
computed from it.** Each of the three documents gets a field `text::String`; its
field `value` becomes a computed cell, the parse of `text`, as `kept_rows` of a
`DataFrameView` is a computed field. A reader of `.value` does not change.

- One fact is kept, so the two can never disagree. A write of the text from
  anywhere, an undo, a paste or the assistant, gives the value of that text.
- The way back from a range edit is the whole field as it was
  (`_make_range_inverse`), and it puts back the text with no change.
- JSON and YAML keep the number as it was written in the file, `1.50` and
  `1e5`, as a text editor does.
- The characters live in `text`, so the path of a caret names that field,
  `.text{s:e}`. In the same review the owner said that a path points where the
  state is.

The cost: a constructor from a value makes its text (`JsonNumber(5)` gives the
text `"5"`); a writer of `value` writes the text instead; the forward and the
backward map of the three number leaves, and every test that writes the path
`.value{s:e}` of a number, move to `.text{s:e}`.

**The alternative: a second field beside the value.** `value` stays the field
that is kept, and `text::Union{String, Nothing}` holds the typed text while it
is not the print of the value. Fewer changes, and paths stay `.value{s:e}`. Not
recommended (mine): two facts can disagree, so every other writer of `value`
must clear `text`, and the way back must write both.

## 4. Steps

1. **The primitive number.** `PrimitiveNumber` keeps `text`, and computes
   `value`. The evaluation of `ReplaceNumberRangeOperation` splices the text, and
   keeps the filter of `has_only_number_characters`. Tests: `-5`, `1e5`, `12.5`
   and `1.50` typed key by key show what was typed, with the value after each
   key; Backspace; undo takes back one key.
2. **JSON and YAML.** The same for `JsonNumber` and `YamlNumber`; the templates
   print the text; the parsers keep the text of the number as the file has it.
   Find out what a save writes for a text that does not parse, and what it writes
   now for a cleared number.
3. **The other users.** The callers that make or write a number document
   (33 files for `PrimitiveNumber`, 24 for `JsonNumber`, 7 for `YamlNumber`,
   with the tests), the clipboard, the conversation and the assistant.
4. **The documents** of the primitive slice, JSON, YAML and the reference
   guide where it names `.value{s:e}` for a number.

## 5. Out of scope

A number field of a native object, which `ObjectFieldToWidget` edits, has no
room for a text; it keeps the behaviour of `splice_value!` for a `Number`.
