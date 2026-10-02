# A number that can not show a key becomes a type-in

Status: a plan, not started. Written 2026-10-02 at the owner's word, in the
review of phase 4 of [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md).
The design of §3 is the owner's; the points of §4 are mine, for the owner to
decide.

## 1. The problem

A number document holds a number or `nothing`, and nothing else:

- `PrimitiveNumber.value::Union{Number, Nothing}` (primitive slice),
- `JsonNumber.value::Union{Real, Nothing}` (JSON),
- `YamlNumber.value::Union{Real, Nothing}` (YAML).

A key in a number splices the print of the value and parses the result with
`splice_number` ([Operations.jl](../../source/kernel/operation/Operations.jl)):
an `Int` when it parses as one, a `Float64` when it parses as one, and `nothing`
for an empty or an unparseable text. The printers show `string(value)`. So, from
the code:

- `-` and `1e` become `nothing`, and the number shows its placeholder. The minus
  sign and the `1` are lost, so a person can not type `-5` or `1e5`.
- `12.` becomes `12.0`, and the number shows `12.0`. The caret stands before the
  `0` that the person did not type.
- `1.50` becomes `1.5`, and the last key does not show.

A cell of a data frame that a person edits as a `PrimitiveNumber` must hold `1e`
until the next key, and a text that does not parse must stay, with a mark, after
the commit of the cell (§3.6 of the data frame plan).

## 2. The first design, rejected

The first version of this plan kept the text in the number and computed the
value from it (or kept a second field `text` beside the value). The owner,
2026-10-02: "I think it would be better to store the number when it's parsed."

## 3. The design (the owner, 2026-10-02)

"We could use a PrimitiveInsertion when it's a type-in? Just like in any other
domains. The number needs to replace itself only when the change cannot be
immediately represented. The PrimitiveInsertion could have a parameter to limit
what it can be turned into, so the user can't turn a PrimitiveNumber into a
PrimitiveString if that's not right in the context."

- A `PrimitiveNumber` holds only a parsed number. A key whose result the number
  can show changes the number in place, as now.
- A key whose result the number can not show replaces the number with a
  `PrimitiveInsertion` that holds the typed text, with the caret where the key
  left it.
- The insertion has a field that limits what it can become. In a number cell it
  can become a `PrimitiveNumber` and nothing else.
- Both documents keep their characters in `value`, so a path of a caret,
  `….value{k}`, does not change when one replaces the other.

What exists for it now:

- `PrimitiveInsertion` has the field `value`. No projection prints it, and no
  code makes one
  ([primitive.md](../../documentation/package/platform/primitive/primitive.md)).
- A source insertion is `InsertionToSyntaxLeaf(commit; completion =
  parse_completion(parser))`, and SQL uses it
  ([InsertionToSyntax.jl](../../source/platform/syntax/InsertionToSyntax.jl)).
  Its text is green when it parses and red when it does not. Enter calls
  `commit(text)` and replaces the insertion with the document that it gives,
  through `replace_document`. Escape replaces it with the empty document of the
  domain, `get_nothing_document`, which is `DocumentNothing` for a type that
  names no other.
- JSON replaces a document with a number only at a digit key (`@gestures
  JsonDocument`), so a `-` does nothing there.

Example: `-5` typed into a number.

1. `-` makes a text that the number can not show. The number becomes
   `PrimitiveInsertion("-")`, limited to `PrimitiveNumber`, with the caret after
   the `-`. The `-` shows red.
2. `5` makes `-5`. It parses, and the number prints it as `-5`, so the insertion
   becomes `PrimitiveNumber(-5)` (point 2 of §4).

## 4. Points for the owner

Each recommendation is mine.

1. **"Can not be represented."** The number does not print the typed text
   exactly: `-`, `1e`, `.`, `12.`, `1.50`, `007`, `+5`, `1e5`. The test uses the
   print of the printer that shows the number, because each printer has its own.
   Otherwise `12.` jumps to `12.0`.
2. **When the insertion becomes a number again.** At each key whose text the
   number prints exactly, so the document is a number whenever it can be. At
   Enter, a text that parses and prints another way becomes its number: `1.50`
   becomes `1.5`. A text that does not parse stays red, and Enter does nothing,
   as a source insertion does now.
3. **Who replaces the number.** The reader of the number: for a key that the
   number can not show, it answers `replace_document` with the insertion
   instead of a range edit. Undo takes back an ordinary replace. Every reader
   that turns a key into an edit of a number calls one helper, so the rule is in
   one place.
4. **The limit.** A field `allowed_types` of the insertion: a tuple of document
   types, `(PrimitiveNumber,)` in a number. The data frame still checks the type
   of the column at its own commit, so `1.5` in an `Int` column gets the mark of
   the cell.
5. **An empty text.** It becomes the insertion and shows the placeholder,
   because an empty text is not a number. `PrimitiveNumber(nothing)` stays valid
   for the code that makes an empty number.
6. **Escape in the insertion.** It gives the first allowed type with no value,
   `PrimitiveNumber(nothing)`, as the Escape of a domain insertion gives the empty
   document of its domain. In a data frame cell, Escape drops the whole entry of
   the cell before the insertion gets the key (the data frame plan).
7. **The scope.** The primitive domain only. JSON and YAML keep their gap for a
   later plan, with their own insertions.

Points 2 and 6 need two options of `InsertionToSyntaxLeaf` that a domain can
use: a function of the text after a key that answers a document when the key
must replace the insertion at once, and a function that gives the document of
Escape. Both default to what the leaf does now.

## 5. Steps

1. **The type-in of a primitive.** `PrimitiveInsertion` gets `allowed_types`,
   and a printer: a source insertion leaf whose commit parses the text into the
   first allowed type that takes it, registered beside `PrimitiveNumber` in the
   natural renderer. The two options of `InsertionToSyntaxLeaf` (§4). Tests: the
   text shows green and red; Enter commits `1.50` to `1.5`; Enter does nothing on
   `1e`; Escape gives an empty number; a key that makes `-5` gives the number.
2. **The number becomes a type-in.** The helper of point 3, and each reader of
   a key in a number calls it. Find out which they are: the leaf of the natural
   renderer (`PrimitiveNumberToSyntaxLeaf`), `PrimitiveNumberToText`, and the
   math domain, which prints its numbers with the same leaf. Tests: `-5`, `1e5`,
   `12.5` and `1.50` typed key by key show each key, and give the number at the
   end; Backspace in an insertion; undo takes back one key, also the key that
   replaced the number; a caret path stays the same over each replace.
3. **The math domain.** A `-` in a number of a formula can mean a minus of the
   formula, not of the number. Find out what its tests expect, and ask the owner
   before the math domain changes.
4. **The documents** of the primitive slice and of the syntax slice (the source
   insertion and its two options).

## 6. Risks

- **A field that holds types.** `allowed_types` is a tuple of types. A save of a
  document that holds an insertion, a duplicate and the copy to the clipboard
  must carry it; check each in step 1.
- **The cost of a replace.** Each key that crosses between a number and a
  type-in replaces a document, and the printer prints the new one. A person types
  a few keys, so it is not a cost of a loop; it is a cost of a print per key.
