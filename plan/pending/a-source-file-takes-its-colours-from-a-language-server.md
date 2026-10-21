# A source file takes its colours from a language server

> **Kind:** plan · **Status:** pending, design, 2026-10-21. The owner decided
> five points on 2026-10-21 (section 6). No question is open. No step is
> started.

## 1. The goal

A person opens a C or C++ file, such as `omnet-cpp/src/sim/csimulation.cc`, in a
tab. The text shows the names in the colours of their kinds: a function, a
class, a parameter, a field, a macro, a namespace. The colours come from a
language server, `clangd`. The person types, and the colours follow the text.
The editor never waits for the server.

The document stays text. The server gives colours to a text; it gives no tree.
A language that has a domain, such as Julia or SQL, keeps its tree.

## 2. The idea, with an example

The document holds the original string of the file and the marks that the
server gave. A projection makes the lines from the string, and splits each line
at the marks, with each piece in the colour of its kind.

```julia
# The document: the original string, and the marks that the server gave
SourceFile(filename = "/…/hello.c",
           content  = MarkedText(text  = "int main() {\n    int count = 0;\n    return count;\n}",
                                 marks = [TextMark(4, 8;   text = ColorRole(:function_name)),   # main
                                          TextMark(21, 26; text = ColorRole(:variable)),        # count
                                          TextMark(43, 48; text = ColorRole(:variable))]))      # count

# MarkedTextToText prints the lines, already split at the marks
TextBlock(TextLine(TextString("int "), TextString("main" … function colour …), TextString("() {")),
          TextLine(TextString("    int "), TextString("count" … variable colour …), TextString(" = 0;")),
          …)
```

An edit goes back to the string. The person types `s` after the second
`count`: the reader maps the caret at flat offset 48 to offset 48 of `text`, and
the string gets the `s`. The projection prints the lines again, and keeps each
line whose text and marks did not change.

Over time:

| Moment | The text | The screen shows | The server |
| --- | --- | --- | --- |
| The person opens the tab | version 1 | plain text | starts, and gets version 1 |
| About 0.5 s later | version 1 | plain text | sends the tokens of version 1 |
| The next frame | version 1 | the names in colour | — |
| The person types a key | version 2 | the colours of version 1, moved to version 2 | gets version 2 |
| About 0.05 s later | version 2 | the colours of version 2 | sends the tokens of version 2 |

## 3. The facts

1. **`clangd` 21.1.8 is installed** (`/usr/bin/clangd`). A probe on
   `omnet-cpp/src/sim/csimulation.cc` (1082 lines) gave:

   | | Tokens | First answer | Answer after a change of the full text |
   | --- | --- | --- | --- |
   | No include paths | 402 | 0.15 s | 0.03 s |
   | With include paths | 1827 | 0.50 s | 0.05 s |

   The start and `initialize` take 0.015 s. `clangd` agrees to count positions in
   characters (`positionEncoding: utf-32`), and it takes a change as the full
   text or as a range (`textDocumentSync.change = 2`). It also gives 121
   folding ranges and pushes diagnostics without a request.
2. **`clangd` finds the include paths in a `compile_commands.json`** in a folder
   above the file. Neither `omnet-cpp` nor `inet-cpp` has one now. Without it,
   `clangd` colours about one name in five. The person makes the file outside
   the editor, for example with `bear -- make`.
3. **`clangd` sends names only.** Its kinds: variable, parameter, function,
   method, property, class, interface, enum, enumMember, type, unknown,
   namespace, typeParameter, concept, macro, modifier, operator, bracket, label,
   comment. It sends `comment` for the code of an inactive `#if` branch. It
   sends no keyword, string or number (option A accepts this).
4. **The colour theme has a role for each of these kinds** (`ColorTheme`):
   `function_name`, `field`, `type_name`, `type_parameter`, `module_name`,
   `parameter`, `variable`, `enum_member`, `macro_name`, `keyword`, `operator`,
   `punctuation`, `comment`. A role resolves through the appearance
   (`resolve_theme_color`).
5. **A `.cc` file does not open now.** No format claims the extension, so
   `get_file_document_type` throws, and no tab appears.
6. **A string of many lines takes no Enter now.** A `TextFile` holds a
   `PrimitiveString`, and `PrimitiveToText` refuses an edit that holds a break,
   because a primitive has one line. Its `PrimitiveStringToTextBlock` is the
   model for the new projection: it prints a string as lines, and maps a caret
   to an offset of the string.
7. **A block made from a string keeps its unchanged lines.** `make_text_block`
   from a function keeps the objects of the lines of the common head and of the
   common tail, so a layout keyed by the line lays out only the lines that
   changed.
8. **A file type gives its view by one method**,
   `make_graphics_projection(::Type{T}; measure, appearance)`, as `JuliaFile`
   does with `FileToContent(; content, accepts)`: a chain that ends with
   `TextLineNumbering` and `TextBlockToScrollLayout`.
9. **The background cell brings an answer from another task** with no wait in
   the print (`make_background_cell(source, inputs; default, apply)`). A read
   before the answer gives the last answer, or the default. Its work runs on a
   thread of the default pool, so it can wait for a pipe. The work gets the
   inputs only, not the editor. Two works of one source can run at the same
   time. `source/kernel/editor/BackgroundCells.jl` is not sealed.
10. **The open of a tab acquires the file** (`acquire_document!`), and the close
    releases it. The method for a `FileDocument` watches the file on disk.
11. **Per-editor state** is a session document (`get_session_document!`). A
    wrapper of `build_editor` adds a stop step, which runs when the editor ends.
12. **An adapter brings a dependency.** The adapters read JSON with `JSON3`.
    The ACP adapter speaks JSON-RPC over pipes through an outside package, one
    message on each line. A language server frames each message with a
    `Content-Length` header, so that transport does not fit.
13. **The deferred plan
    [a-highlighted-text-marks-given-ranges.md](a-highlighted-text-marks-given-ranges.md)**
    puts marks on a `HighlightedText`, whose `text` is a block that exists, and
    splits its runs. This plan does not use it: here the projection makes the
    runs from the string.

## 4. The design

### D1. The marked text, in the text slice of the platform

`MarkedText(text, marks)` is a document of the text slice. `text` is a string
of any number of lines. `marks` is a vector of `TextMark`, or a cell that gives
one.

*Found in step 1:* the field is declared `marks::Any`. A field declared
`Vector{TextMark}` becomes a `CellVector`, one cell for each mark, so an answer
of 1827 marks would make 1827 cells and write each of them. Declared `Any`, the
cell holds the vector as one value, and a new answer is one write.

`TextMark(start, stop; text)` is a range of offsets of the string, from 0,
`stop` excluded, and `text` is the colour of its glyphs, a `ThemeColor`. A
break counts one, so an offset of the string is a flat offset of the printed
block. The deferred plan names the same type with two more fields, `surface`
and `underline`; a later plan adds them when it needs them.

### D2. The projection `MarkedTextToText`

`MarkedTextToText(; style, appearance)` prints a `MarkedText` as a block of
lines:

- A line for each line of the string. A piece of a line that no mark covers is
  in `style`. A piece that a mark covers takes the colour of the mark, which
  the appearance resolves. Where marks overlap, the last one wins. A mark past
  the end is cut, and an empty mark draws nothing.
- A line whose text and marks, counted from its own start, did not change keeps
  its object (fact 7).
- A caret and a range map to the same offsets of `text` in both directions.
- An edit of the flat range is an edit of `text` at the same offsets, a break
  included. So Enter, a join and a paste of many lines work.

*Found in step 1:* an edit across two runs, such as Delete of a range that
holds the end of `int ` and the start of `main`, comes to the projection as the
key itself. The stages after it lower a flat edit to one run, and they refuse an
edit that crosses two. So `MarkedTextToText` reads a key that comes back to it
against its own block, with no lowering, and makes the edit of the string.

`compute_moved_text_marks(marks, old_text, new_text)` (named `move_text_marks`
in the design; the naming rules give `compute_` to a function that loops and
changes nothing) moves marks that were made for an
old text to a new text. It finds the common head and the common tail of the
two texts. A mark in the head stays, a mark in the tail moves by the difference
of the lengths, and a mark that touches the changed part goes.

### D3. The file type, in the adapter

`SourceFile(filename, content, server, answer)` is a file document of the
adapter.

- `content` is a `MarkedText`. Its `marks` is a cell that takes the last answer
  of the server and moves it to the text now (`compute_moved_text_marks`).
- `server` is a cell. It holds `nothing` until a tab acquires the file, and
  then the server of that editor for the command of the file (D5, Q1).
- `answer` is a background cell. Its inputs are the server, the path and the
  text. Its answer is the text that the server coloured, with its marks.

The adapter registers `.c`, `.h` (language `c`) and `.cc`, `.cpp`, `.cxx`,
`.hh`, `.hpp`, `.hxx` (language `cpp`), each with the command `clangd`. The
table is a constant of the adapter. A save writes `content.text`.

### D4. The view

`make_graphics_projection(::Type{SourceFile})` gives `FileToContent` with a
chain of `MarkedTextToText`, `TextLineNumbering` and `TextBlockToScrollLayout`,
as the Julia file has.

### D5. One server for each editor and command

The servers of an editor are a session document: one connection for each
command. A server is per editor, because one server holds one text for each
file, and two editors can hold two texts of the same file.

- The acquire of a `SourceFile` sets `server` to the connection of its command,
  and does no I/O. The connection starts its process at the first work.
- The work of the background cell, on its thread, takes the lock of the
  connection. It opens the file in the server with the first text
  (`didOpen`), or sends the full text as a new version (`didChange`). Then it
  asks for the tokens (`semanticTokens/full`) and waits for the answer. It
  turns the tokens into marks in offsets of the text that it sent.
- The release sends `didClose` on a task and sets `server` to `nothing`.
- A wrapper of `build_editor`, on by default, adds the stop step: `shutdown`,
  `exit`, and a kill after a short wait.
- A command that does not start, or a server that fails, gives no marks: the
  text stays plain, and the message log gets one line for each command.

**Nothing of this happens in the print.** The print only reads the cell `marks`.
If the answer for the text now is missing, the read writes a note and shows the
last answer, moved to the text now. The loop starts the work after the print,
and the answer comes back through the inbox as an operation. So a tab that
nobody sees sends nothing to the server. This is no feed: a feed is for data
that the outside sends when it wants, such as the diagnostics, which a later
plan brings.

One round trip. The tab of window 1 shows version 1, and the person types `1`
after `0` on line 1:

```
version 1: "int main() {\n    int count = 0;\n    return count;\n}"
version 2: "int main() {\n    int count = 10;\n    return count;\n}"
```

| When | Where | What happens | The marks on screen |
| --- | --- | --- | --- |
| Frame 1 | owner task, reader | The key edits the string to version 2. | — |
| Frame 1 | owner task, print | The read of `marks` finds an answer for version 1, writes a note, and moves the marks of version 1 to version 2. | 4–8, 21–26, 44–49 |
| After the print | owner task, loop | One work starts on a thread with the inputs `(clangd of window 1, "/…/hello.c", version 2)`. | — |
| +0 ms | the thread | The work sends the text and the question to `clangd`. | — |
| +50 ms | the thread | The work turns the answer into marks of version 2 and posts one operation: write this answer into this cell. | — |
| Frame k | owner task | The owner writes the answer, and the print shows the new marks. | 4–8, 21–26, 44–49 |

The messages on the pipe:

```
→ {"method": "textDocument/didChange",
   "params": {"textDocument": {"uri": "file:///…/hello.c", "version": 2},
              "contentChanges": [{"text": "int main() {\n    int count = 10;\n    return count;\n}"}]}}
→ {"id": 7, "method": "textDocument/semanticTokens/full",
   "params": {"textDocument": {"uri": "file:///…/hello.c"}}}
← {"id": 7, "result": {"data": [0,4,4,3,3,  1,8,5,1,3,  1,11,5,1,0]}}
```

Each group of five numbers is one name: the line counted from the line before,
the column, the length, the kind (an index in the table of `clangd`: 3 is a
function, 1 a variable), and the modifiers. The work turns them into the flat
offsets of version 2.

A person who types fast starts one work in each frame that has a new text. The
lock of the connection sends them to the server one after the other. An answer
to an older text has an older note number, and the owner drops it, so the
colours never go back to an older text.

### D6. The connection

A connection holds the process, a reader task, the waits of its requests by
id, and a lock. It writes `Content-Length` frames with `JSON3`. The reader task
gives each answer to its wait, answers a request of the server with an error
"method not found", and drops a notification. A task reads the error stream of
the process and drops it, so the pipe never fills. `initialize` offers
`utf-32` and `utf-16`; with `utf-16`, the work converts each column through its
line.

### D7. The package

`ProjecturedLanguageServer`, code in `source/adapter/languageserver/`
(`LanguageServerModule`), with `ProjecturedLanguageServerTest` and
`test_languageserver()`, which the naming law names after the folder of the
slice. It depends on `ProjecturedKernel`,
`ProjecturedPlatform` and `JSON3`. Its `[auto-integration]` table has the
trigger `Projectured` and the default `auto` (Q2).

## 5. The steps

The work is done in a worktree. Before each edit, check the file in
`SEALING.md`.

1. ✅ **The marked text (D1, D2).** `MarkedText`, `TextMark`,
   `MarkedTextToText` and `compute_moved_text_marks` in the text slice, and the
   example `text_marking_example` (named as `text_highlighting_example` is), with
   its atom `text/marked` for the catalog. The section of `MarkedText` in
   `text.md` is written here, not in step 5. Tests: the pieces and their
   colours; overlapping marks; a mark past the end; a caret and a range round
   trip; a key, Enter, a join and an edit across two runs change the string; an
   unchanged line keeps its object; the moves of `compute_moved_text_marks`.
   *Results:* `test_marked_text_to_text()` 35 pass; for the example,
   `test_printer` 402, `test_reader` 230, `test_repl` 230,
   `test_position_navigation(; check_reaches_all = true)` 120, `test_typein` 156,
   all pass; `test_highlighted_text_to_text()` and the platform layering guard
   pass; the tree guards (`test/suite/*.jl`) report the same findings as `main`.
   The catalog guard, run in step 2: `text/marked` renders and round-trips
   naturally. `test_catalog_coverage` fails on six types that are not of this
   plan (`BackgroundWorkLog`, `Dashboard`, `Explorer`, `ExplorerSearch`,
   `ExplorerSection`, `WorkspaceExplorer`), and `test_natural_renders_every_atom`
   on `filesystem/chooser`, a known-broken atom that renders now: both are
   failures of `main`, which other sessions' types bring.
2. ✅ **The package and the connection (D6, D7).** The two packages, the lists
   that name an adapter (`environment/all` and its manifest, `ProjecturedTest`,
   `ProjecturedSuite.jl`, `IntegrationLoadingTest.jl`, the builder program and
   its summary, `BuilderTest.jl`, the CI matrix), and the connection. The
   third-party table of `package-rules.md` moves to step 5, with the other
   documents, because its column of slices is known only after step 4. Test: a
   fake server in the process, on two streams: the start and the legend, a
   server that names no encoding, a request and its answer, an error answer, a
   request of the server, a notification, a request with no answer, the end of
   the server, the stop, a command that is not installed, the file URI.
   *Facts:* the naming law names the entry point `test_languageserver()`, after
   the folder of the slice. A request waits on a channel with a timer, not on a
   poll. A connection whose start failed does not try again, so a missing
   `clangd` costs one try. The builder summary names
   `documentation/package/adapter/languageserver/languageserver.md`, so
   `PackageReleaseTest` passes only after step 5 writes it.
   *Results:* `test_packages_declare_triggers` 32 pass and
   `test_umbrella_loads_integrations` 8 pass, with the new adapter.
3. ✅ **The tokens (D5 without the editor).** Open, change, ask; the relative
   encoding to marks; the table from a kind to a role; the `utf-16` columns.
   Tests with the fake server, and one with `clangd` when `Sys.which("clangd")`
   finds it. *Names:* `compute_semantic_text_marks(connection, path, language,
   text)` sends the text and asks; `convert_semantic_tokens(data, text,
   token_types, encoding)` makes the marks; `close_language_server_document!`
   sends `didClose`; `SEMANTIC_TOKEN_ROLES` is the table, which also holds the
   kinds that `clangd` adds (`concept`, `bracket`, `label`). *Results:*
   `test_languageserver()` 57 pass, the test with `clangd` 21.1.8 included:
   `main` 4–8 is a function, and `count` 21–26 and 43–48 are variables.
4. ✅ **The file and its view (D3, D4, D5).** The type, its registrations, the
   acquire and the release, the session document, the wrapper, the view, the
   save, and a command that is not installed. Test: an editor opens a
   `SourceFile` with the fake server; the runs of a name take its colour after
   the answer; a key keeps the colours of the other lines; a save writes the
   text.
   *Decisions and facts found here:*
   - `SourceFile(filename::AbstractString, content::Document)` builds the cells:
     the `@document` macro makes an untyped two-argument form, and a typed form
     is a different signature, so both exist (no precompile clash). Each file has
     its own `BackgroundSource`, so the work of one file asks only its server.
   - `.h` is C++ (`cpp`): the headers of `omnet-cpp` and `inet-cpp` are C++.
     The command is `clangd --log=error --background-index=false`, so `clangd`
     writes no index into the folder of a project.
   - **A reload keeps the text object.** Ctrl+O and the reload of a file that
     changed on disk put a new document into the history of the file, which
     would drop the computation of the marks with the old `MarkedText`. The
     contract of `replace_wrapped_document!` says that a node that must survive
     a replacement writes the new document into itself. So
     `replace_wrapped_document!(::MarkedText, ::MarkedText)` writes the new string
     into the old text and answers it, and the history (`UndoBuffer`) passes the
     new document on to the document that it holds, as an arrangement does. For
     every other type the default answers the new document, so nothing else
     changes.
   - A server that ended starts again at the next work, and it holds no file,
     so the connection forgets the versions at each start.
   - The start of a server that fails writes one warning to the message log.
   - The package has `@compile_workload run_natural_rows_workload(LanguageServerModule)`
     and depends on `PrecompileTools`, as the package graph test asks of a
     package with a natural row.
   - **A print is lazy.** In a headless test, nothing reads the output, so no
     background cell asks; the test walks the output as the evaluation of the
     editor (`run_with_evaluation_editor`), as a paint does, and applies what the
     tasks posted (`drain_operations!`), as the loop does.
   *Results:* `test_languageserver()` 99 pass, with two tests with `clangd`
   (an editor that opens a C file, and a server that ended and starts again);
   `test_marked_text_to_text()` 41, `test_undo()` 126,
   `test_arrangement_program()` 13, `test_file_tab()` 33,
   `test_package_graph()` 405, `test_packages_declare_triggers()` 32,
   `test_umbrella_loads_integrations()` 8,
   `test_integrations_load_with_extensions()` 3; the tree guards report what
   `main` reports, and one finding that step 5 removes: no guide names the
   slice `source/adapter/languageserver` yet.
5. ⬜ **The example, the live check and the documents.** An example that opens a
   small `.cc` file. In the application: open
   `omnet-cpp/src/sim/csimulation.cc` and a file of `inet-cpp`, see the colours,
   type, and measure the time of a frame for a key. The design document
   `documentation/package/adapter/languageserver/languageserver.md`, the
   section of `MarkedText` in `text.md`, and the tables of `system-anatomy.md`,
   `package/README.md` and `testing-guide.md`.

## 6. Decisions and questions

**Decided by the owner, 2026-10-21:**

- Option A: the server is the only source of colours. A base stage for
  keywords, strings and numbers is not in this plan.
- The marks are on the input document, which wraps the original string of the
  file, and a projection applies them (D1, D2). The owner proposed this shape.
- `MarkedText` and `MarkedTextToText` are in the text slice of the platform,
  not in the adapter, because they need nothing from a server.
- **Q1, the link from a file to the server of its editor: (a).** A cell of the
  file that the acquire sets (D3, D5), and the work finds the server in its
  inputs. The other way was (b): the kernel gives the editor to the work of a
  background cell, which changes the kernel for every background cell. The
  owner asked how the text goes to the server and how the marks come back, and
  accepted the round trip of D5: no work in the print, and no feed.

- **Q2, the load: (a).** The adapter loads with `Projectured` (`auto`), as the
  Ollama adapter, so a `.cc` file opens in every session; with no `clangd` it
  shows plain text. `JSON3` loads already for the Ollama adapter. The other way
  was (b): a person loads it by name, as the ACP adapter, and a `.cc` file
  stays an error in a session without it. No other repository claims the
  extensions (`omnet-julia`, `inet-julia`, `projectured-julia`, checked
  2026-10-21).

**Open:** none.

## 7. Not in this plan

- A base colour stage for keywords, strings and numbers (option B or C).
- Diagnostics: the line under a range, the mark in the gutter, the tooltip.
- Folding ranges, hover, go to definition, completion, symbols, rename.
- A change sent as a range, and tokens asked for the lines in view only.
- A setting for the table of servers; NED and other languages.
- A change of `HighlightedText`; the deferred plan stays deferred.
