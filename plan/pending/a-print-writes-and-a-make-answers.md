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
- [ ] **Step 4: omnet-julia.** The NED and INI methods and every call; the two
      repositories land together.
- [ ] **Step 5: the texts the model reads.** The orientation guide, the S2 code
      (`print_natural_string(people_1)` in place of
      `println(print_natural_text(people_1))`), and the system prompt when the
      owner changes it.
- [ ] **Step 6: the tests** of the file types, the save and the export, the
      naming guard, and a search for the old names.
