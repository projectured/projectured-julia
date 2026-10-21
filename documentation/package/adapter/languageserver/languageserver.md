# The language server adapter

> **Kind:** design · **Status:** current · **Stands on:** [text.md](../../platform/text/text.md), [communication-anatomy.md](../../../design/communication-anatomy.md), [filesystem.md](../../platform/filesystem/filesystem.md)

`ProjecturedLanguageServer` opens a C or C++ file as text whose names take the colours of their kinds: a function, a class, a parameter, a field, a macro, a namespace. A language server gives the kinds; the adapter starts `clangd`. This document says how the text goes to the server and how its answer comes back without a wait in the print, which server a file talks to, and what the adapter does not do.

## How it works

### The document and the projection

A source file is a `SourceFile(filename, content)`. Its content is a `MarkedText` of the text slice: the string of the file and the marks that colour ranges of it; see [text.md](../../platform/text/text.md). `MarkedTextToText` prints the lines of the string, split at the marks, and every edit of the lines is an edit of the string. The string is the simple representation: the server gets it, a save writes it, and the marks count its characters.

```julia
SourceFile(filename = "/…/hello.c",
           content  = MarkedText(text  = "int main() {\n    int count = 0;\n    return count;\n}",
                                 marks = [TextMark(4, 8;   text = ColorRole(:function_name)),
                                          TextMark(21, 26; text = ColorRole(:variable)),
                                          TextMark(43, 48; text = ColorRole(:variable))]))
```

The view of a file (`make_graphics_projection(::Type{SourceFile})`) is `FileToContent` with `MarkedTextToText`, `TextLineNumbering` and `TextBlockToScrollLayout`, as the view of a Julia file is. The extensions `.c`, `.h`, `.cc`, `.cpp`, `.cxx`, `.hh`, `.hpp` and `.hxx` open as a `SourceFile` (`SOURCE_FILE_LANGUAGES`); `.c` is the language `c`, and the others `cpp`, because the headers of a C++ project are C++.

### From a key to the colours of the server

**The print never waits for a server.** A source file holds the last answer of the server in a plain cell (`answer`), and a background cell (`request`) whose inputs are the server, the path and the text. A read of the marks gives the stored answer, moved to the text of now (`compute_moved_text_marks`): a mark before the change stays, a mark after it moves by the difference of the lengths, and a mark on it goes. The read also reads `request`, with no tracking: if the answer for the text of now is missing, that read writes a note of it. After the print, the editor starts the work of the cell on a thread of the default pool. The work sends the text to the server and then the request for its tokens (`semanticTokens/full`), and the answer comes back to the owner task as an operation through the inbox, which stores it in `answer` (`StoreSourceFileAnswerOperation`). The next print shows it.

**The marks stay final while an answer is to come.** A read of a background cell that has no answer is provisional, and a provisional value computes again at each read by a computation. The lines of a text read the marks once for each line, so marks that read the background cell with tracking would split the whole text again at each line, and the print of a large view would not end. The untracked read and the stored answer keep the marks final. [communication-anatomy.md](../../../design/communication-anatomy.md) describes the background cell.

One round trip, when the person types `1` after `0` on line 1:

| When | Where | What happens | The marks |
| --- | --- | --- | --- |
| Frame 1 | owner task, reader | The key edits the string to version 2. | — |
| Frame 1 | owner task, print | The read of the marks finds an answer for version 1, notes the demand, and moves the marks to version 2. | 4–8, 21–26, 44–49 |
| After the print | the loop | One work starts on a thread with the server, the path and version 2. | — |
| +0 ms | the thread | `didChange` with the full text, then `semanticTokens/full`. | — |
| +50 ms | the thread | The tokens become marks of version 2, posted as one operation. | — |
| Frame k | owner task | The answer is written, and the print shows it. | 4–8, 21–26, 44–49 |

A tab that nobody sees prints nothing, so no question goes to the server for it. Two works of one file run one after the other, under the lock of the connection, so the server gets the versions in order, and the editor drops an answer to an older demand.

### The server of an editor

**Each editor has its own servers**, one for each command, in a session document (`LanguageServers`). A server holds one text of each file, and two editors can hold two texts of one file, so a server is not shared between editors. The open of a tab acquires the file (`acquire_document!`): the file watches its file on disk, as every file does, and its cell `server` takes the connection of the editor for the command of the file. The acquire starts no process. The first work starts it, off the loop. The close of the tab releases the file: the server gets `didClose` on a task, and the file keeps its marks. The wrapper `language_server` of `build_editor`, on by default, stops every server of the editor when its loop ends.

### The connection

`LanguageServerConnection(command; directory, streams)` speaks JSON-RPC 2.0 with a `Content-Length` header before each message, over the pipes of the process, or over two streams that a test gives. A task of its own reads the answers: it gives each answer to the request that waits for it, answers a request of the server with the error "method not found", and drops a notification. Another task reads the error stream of the process and drops it, so the pipe never fills. In `initialize`, the client lists two ways to count a column: in characters (`utf-32`) and in UTF-16 units. `clangd` takes characters. For a server that takes UTF-16 units, `convert_semantic_tokens` converts each column through its line.

The command is `clangd --log=error --background-index=false`, so `clangd` writes no index into the folder of a project. `clangd` finds the include paths of a file in a `compile_commands.json` in a folder above it. With none, it gives the kinds of fewer names: on a C++ file of 1082 lines of a simulator, it gave 402 tokens with no include paths, and 1827 with them.

### When a server fails

A command that does not start writes one warning to the message log, and its files show plain text; the connection does not try again. A request with no answer ends at its timeout. A server that ends starts again at the next work, and the connection forgets the files that the old process held, so each file opens again as its first version. A work that meets a `LanguageServerException` answers no marks, so the text is plain until the next answer.

### A reload

A file that changed on disk, or Ctrl+O, puts a new document into the history of the file. `replace_wrapped_document!(::MarkedText, ::MarkedText)` writes the new string into the old text and answers it, and the history passes the new document on to the document that it holds. So the text keeps its computed marks, and the colours follow the new string as they follow an edit.

## How it fits

The code is the slice `LanguageServerModule`, in `source/adapter/languageserver/`. The package depends on `ProjecturedKernel`, `ProjecturedPlatform`, `JSON3` and `PrecompileTools`. `JSON3` is the reason that it is a package of its own; see [package-rules.md](../../../rule/package-rules.md). The platform does not depend on it: the package adds a method to `acquire_document!` and `release_document!` of the domain slice, to `parse_file_content`, `emit_text` and `get_file_domain` of the serialization slice, to `make_graphics_projection` of the widget slice, and to the wrapper seams of the editor. Its `__init__` registers the extensions. AutoIntegration loads it with `Projectured`, so every session opens a C or C++ file; see [autointegration.md](../../autointegration/autointegration.md). The entry file compiles the natural rows in a `@compile_workload`.

## Design decisions

- **The document holds the string of the file, and a projection applies the marks.** The server, the save and the marks use the same string and the same offsets. See [plan/done/a-source-file-takes-its-colours-from-a-language-server.md](../../../../plan/done/a-source-file-takes-its-colours-from-a-language-server.md).
- **The server is the only source of colours.** `clangd` sends names and no keyword, string or number, so those stay plain; a stage of base colours before the server stage can come later and does not change it.
- **A file finds the server of its editor in a cell that the acquire sets.** The work of a background cell gets its inputs and not the editor, so the server is one of the inputs. The other way, a kernel that gives the editor to every work, changes a contract of the kernel.
- **The answer is a background cell, not a feed.** The tokens answer a question; a feed is for what a server sends when it wants, such as its diagnostics.
- **A server is per editor.** It holds one text of each file.
- **The text goes as the full text at each version.** On a file of 1082 lines, `clangd` answers a change of the full text in about 0.05 s; a change sent as a range is not needed yet.

## Usage

```julia
using ProjecturedLanguageServer
file = make_file_tab("/home/me/project/hello.cc")      # a SourceFile; a tab of an editor colours it
connection = LanguageServerConnection(["clangd", "--log=error"]; directory = "/home/me/project")
marks = compute_semantic_text_marks(connection, "/home/me/project/hello.cc", "cpp", read("/home/me/project/hello.cc", String))
stop_language_server!(connection)
```

- Tests: `test_languageserver()` runs the layering guard, `test_language_server_connection()`, `test_semantic_tokens()` and `test_source_file()`. A server in the test process (`FakeLanguageServer`) answers them on two streams; the tests that start `clangd` skip themselves when it is not installed.
- The package has no example of its own. `text_marking_example` shows the marked text, and the application opens a C or C++ file from the Files pane or the command line.

## Limits

- Only C and C++, with `clangd`. The table of servers is a constant, and no setting changes it.
- Only colours. The diagnostics, the folding ranges, the hover, go to definition and completion are not read.
- Keywords, strings and numbers stay plain, because `clangd` does not send them.
- A headless editor computes nothing that nobody reads: a test walks the output as the evaluation of the editor and applies what the tasks posted, as a paint and the loop do.
- No test is marked `@test_broken`.
