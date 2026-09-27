# A print writes to an IO, and a make answers the value

> **Status:** pending. Written 2026-09-26. Starts after
> `the-assistant-reaches-a-referenced-document.md` is done.

## 1. The request

In the S2 code of `the-assistant-reaches-a-referenced-document.md` §3, the model
writes `println(print_natural_text(people_1))`, because `print_natural_text`
answers a `String` and prints nothing. The owner (2026-09-26): "I would expect
print to print, no?", then:

- "We should have a clear naming rule for this. Printing using the projection
  into a document and printing immediately to an IO."
- "This is its own plan after this is done."
- "I would call print_natural_string to print to IO and make_natural_string to
  return it."

## 2. What exists

- **Two senses of "print".** The naming rules (`documentation/rule/naming-rules.md`,
  under "Functions") make read, evaluate and print the three rungs of the editor
  loop: `print_document(projection, …)` runs the printer of a projection and
  answers an IoMap, which holds the output document. `print_child`,
  `print_document_pure`, `print_child_pure`, `print_pure` and
  `print_template_rule` are of that sense. In Julia, `print(io, x)` writes to an
  IO and answers `nothing`. The rules do not say which sense a `print_` name has.
- **`print_natural_text(document) -> String`** (`source/natural/NaturalNotation.jl`)
  runs the natural projection down to a string. Its docstring calls it "a
  shorthand, not a seam". It has a method for a `FileDocument`
  (`source/fileformat/DocumentFile.jl`) and one for a `ReferencedDocument`. On
  2026-09-26 it had 25 calls in this repository, among them the `emit_text` of the
  JSON, Julia, Markdown, Math and XML files and `export_document`. omnet-julia
  imports it to add methods for its NED and INI files
  (`NedFileDocument.jl`, `IniFileDocument.jl`).
- **Other `print_` functions to classify:** `print_pred_text`
  (`source/serialization/PredFile.jl`, which `emit_text` of a pred file uses as a
  string), `print_object` (`source/syntax/ObjectToSyntax.jl`, whose examples show
  a string), `print_example` (`example/`) and `print_build_report!`
  (`source/builder/Executable.jl`). Not yet read: which of them write and which
  answer a value.
- **The application's system prompt** names `print_natural_text(tab.content)`
  (D18 of the referenced-document plan keeps the prompt unchanged for the S2
  rehearsals).

## 3. Decisions

- **D1. The naming rule.** A `print_` function writes. Two senses, each with its
  own form:
  - A **projection printer**, `print_document` and the rest of the printer rung,
    prints a document through a projection into an output document, and answers
    the IoMap. Its name ends in the unit that flows in (`_document`, `_child`),
    as the rules say now.
  - A **writer** prints to an IO at once: `print_<what>(io, x)` writes and
    answers `nothing`, as `Base.print` does; without an `io` it writes to
    `stdout`.
  - A function that answers the text as a value is a `make_<what>`, because the
    rules use `make_` for a function that makes a new value.
  The rule goes into `naming-rules.md`, with the two senses and an example of
  each, and into the naming guard if the guard can tell them apart.
- **D2. `print_natural_string([io,] document)`** writes the natural text of
  `document` and answers `nothing`. **`make_natural_string(document) -> String`**
  answers it. The owner chose the two names (2026-09-26). `print_natural_text`
  goes; its methods for a file document and a referenced document move to the
  two new names.
- **D3. The pair with the reader.** `parse_natural_text` reads a string into a
  document. Whether it becomes `parse_natural_string`, so the three names share
  the noun, is for the owner to decide at the start of this plan.
- **D4. The other `print_` functions** follow D1: each one that answers a value
  becomes a `make_`, and each one that writes takes an `io`. The inventory of §2
  decides which is which.
- **D5. `print` of any document writes its natural text** (the owner,
  2026-09-26: "print should call print_natural_string by default for any
  document"). The Julia contract, as found before the decision:
  - `print(io, x)` writes the plain text for a reader, "canonical
    (un-decorated)", and falls back to `show(io, x)`; `string(x)`, `"$x"`,
    `println` and `join` use it.
  - `show(io, x)`, with two arguments, writes a short, one-line form with type
    information, parseable where it can be; `repr(x)` and an element inside a
    container use it.
  - `show(io, MIME"text/plain"(), x)`, with three, writes the full form for a
    person; `display(x)`, the REPL and the last value of `execute_julia_code` use
    it, and it falls back to the two-argument `show`.
  - Documents had only a two-argument `show`, the depth-limited debug form in
    `DocumentDefaults.jl`, so `string(JsonString("Cleo"))` was
    `JsonString("Cleo")`.
  So `Base.print(io, document)` writes what `print_natural_string(io, document)`
  writes, and `string(document)` is the natural text. The points to keep:
  1. `print` never fails: string interpolation, `join` and error messages call
     it. A document type with no natural text falls back to `show`.
  2. The method `Base.print(io, ::Document)` goes in `ProjecturedNatural`,
     because the kernel does not know natural text. That is a method of a Base
     function on a kernel type, which Julia calls type piracy; no rule of the
     project forbids it. Without `ProjecturedNatural` loaded, `print` of a
     document is `show`.
  3. Every place that makes a document into a string changes: each `"$(node)"`,
     `string(node)` or `join` of documents in an error message or a log gives the
     natural text, which can be long, in place of the debug form. A printer of a
     projection that calls `string` on a document would start the natural
     printer inside a printer. An inventory of these places comes first.
  4. A JSON string leaf prints as its JSON literal, with the quotes:
     `string(JsonString("Cleo"))` is `"Cleo"` with the two quotes. The bare text
     stays `.value`, as the orientation guide shows.
  5. **A table prints as its rows** (the owner, 2026-09-27: "Yes, natural table
     printing is right"). A `WidgetTable` has no natural text now
     (`print_natural_text` fails: "no natural text for WidgetTable"), so without
     one `print` of a table falls back to the debug form. Its natural text is its
     column headers and its rows, one line each, with the cells of a column
     lined up. A tab prints as what it shows. Found in the rehearsal of S2
     (`plan/pending/a-fast-loop-for-the-assistant.md`): a model that wrote
     `println(table_tab)` read the debug form, and stated the count of an earlier
     turn; with the rows it reads the count and the names. The three-argument
     `show` of a tab and a table stays the summary that landed on 2026-09-27
     (a2ad3898), `PaneTab("People", WidgetTable(5 rows × 3 columns: name, age, city))`.
  In the same step, a `ReferencedDocument` follows the contract: `print` of it
  prints its document; its long form `ReferencedDocument{T} at …: …` moves to
  the three-argument `show`; its two-argument `show` becomes short. Found in the
  S2 rehearsal of 2026-09-26: `string(person["name"])` printed the long form into
  every cell of the table, because `print` fell back to the two-argument `show`.

- **D6. A form that returns a widget shows it drawn, not printed** (the owner,
  2026-09-27: "when a form returns a table widget it should be displayed as a
  table and not printed"). What exists: the evaluator and a block of code of the
  assistant embed a returned `Document` as the result, so it draws as itself; the
  model then receives the natural text of that result, or the debug form when
  the document has none, which a table needs D5 point 5 for. A
  `ReferencedDocument`, which `find_pane`, `get_edited_document` and `open_pane!`
  answer, is not a `Document`, so it shows as text. To decide: whether a
  referenced document draws its document in the block, for a widget or for any
  document, with the text for the model kept apart; a block that draws a live
  document shows it as it is now, not as it was when the code ran.

## 4. Steps

- [ ] **Step 1: the rule.** D1 in `naming-rules.md`; the owner reads it before
      the code changes.
- [ ] **Step 2: the natural string.** D2 in `ProjecturedNatural`, the file
      format and the reference layer, with a rename of every call: a call that
      uses the value calls `make_natural_string`, a call that shows the text
      calls `print_natural_string`. `workspace/bin/julia-rename.jl --report`
      first; a second pass for the prose and the docstrings; a search for the
      old name in strings, guides and the system texts.
- [ ] **Step 3: the other `print_` functions** (D4).
- [ ] **Step 3a: `print` of a document** (D5). First the inventory of the places
      that make a document into a string, and of the printers that call `string`
      or `print` on a document; then the method in `ProjecturedNatural` with the
      fallback to `show`; then the `show` and `print` of `ReferencedDocument`.
      Tests: `string` of a JSON array and of a JSON string leaf, of a document
      with no natural text, of a referenced document, and `repr` of a vector of
      referenced documents. The natural text of a table (point 5), and `string` of a
      table and of a tab that holds one.
- [ ] **Step 3b: a returned widget is drawn** (D6), after the owner decides its
      open question.
- [ ] **Step 4: omnet-julia.** The NED and INI methods and every call; the two
      repositories land together.
- [ ] **Step 5: the texts the model reads.** The orientation guide, the S2 code
      (`print_natural_string(people_1)` in place of
      `println(print_natural_text(people_1))`), and the system prompt when the
      owner changes it.
- [ ] **Step 6: the tests** of the file types, the save and the export, the
      naming guard, and a search for the old names.
