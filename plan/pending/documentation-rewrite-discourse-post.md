Title: ProjecturEd: one structure, many editable views — with an AI assistant

Category: Tooling
Tags: gui, llm, mcp, ai

Paste everything below the line. Each paragraph is one line, because Discourse turns a newline into a line break.

---

ProjecturEd is an application to view and edit structured data, with an AI assistant built in: one structure, many editable views. It's written in Julia, so it's also a generic user interface for your own Julia programs. It isn't finished, but most of it works, and I think it's far enough along to show and to get some feedback.

Some background on why. Structured data almost always ends up as text. You print it, or you write it to a file and edit the characters, or you write a GUI for that one type and then maintain it. An LLM has the same limit: it writes characters, and you find out afterwards whether the result parses. I wanted the data itself to be the thing you look at and change, with the keyboard or through a model, and I wanted a view to be cheap enough that any value can have one.

ProjecturEd started as a Common Lisp project in 2013. This is a new implementation of the same idea in Julia, with a lot more domains, more backends and the assistant.

[screenshot or video here]

### How it works

The data is the source, and every view is computed from it. A document is a tree of typed Julia values. A projection is a pair of functions. The printer makes the view and records which part of the view came from which part of the data, in what I call the IO map. The reader uses that record to turn a key press, a click or a paste into a typed operation on the data. Projections chain: JSON gets to the screen as JSON → syntax tree → text → graphics → window, and a key press goes back through the same chain to the domain that owns the data.

Every field of a document is a reactive cell. The cells are lazy: a write marks the dependents invalid, and a read recomputes only what the screen asks for. So a one character edit runs a handful of cell computations, and the parts of a document that are off screen cost nothing. A view can show a part of a very large document, or of an infinite lazy list.

### What a domain takes: JSON as the example

The JSON domain is 504 lines in five files, and 158 of them are the parser. This is all of it:

* [JsonDocument.jl](https://github.com/projectured/projectured-julia/blob/main/source/json/JsonDocument.jl) (116 lines): the document types, what a new element starts as, and the key bindings.
* [JsonToSyntax.jl](https://github.com/projectured/projectured-julia/blob/main/source/json/JsonToSyntax.jl) (133 lines): the projection, one template per document type, to the generic syntax domain.
* [JsonParser.jl](https://github.com/projectured/projectured-julia/blob/main/source/json/JsonParser.jl) (158 lines): a recursive descent parser from JSON text to the document, to open a file and to paste text.
* [JsonFile.jl](https://github.com/projectured/projectured-julia/blob/main/source/json/JsonFile.jl) (26 lines): the `.json` file, and how JSON spells a reference to another file.
* [JsonModule.jl](https://github.com/projectured/projectured-julia/blob/main/source/json/JsonModule.jl) (71 lines): the module, and the registration of the `.json` extension and the notation.

There's no reader, no navigation code and no drawing code in it. JSON projects to the generic syntax domain, which XML, SQL and Julia code use too, and from there the syntax, text and graphics projections do the rest. The caret, navigation, selection, the clipboard, search, sorted and filtered views, save and load, every backend and the assistant all come from the chain. Shortened, but real code:

```julia
@domain Json                     # the abstract JsonDocument type, and the placeholder types

@document struct JsonString <: JsonDocument   # each field becomes a reactive cell
    value::String
end

@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
end

@gestures JsonArray begin        # the text is what F1 and the command palette show
    KeyPress(',') => "Insert a new element" => append_insertion_operation(doc, :elements, JsonInsertion)
end

@projection_template JsonArrayToSyntaxNode JsonArray (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

register_natural_domain!(JsonDocument; rung = :syntax, make = () -> JsonToSyntax(),
                         format = :json, extension = ".json", parse = parse_json)
```

A printer is a template of the output, with markers where the engine has to wire something: `collection(:elements)` hands each element to its own projection, `bound(:value, ...)` makes a field editable, and `project(:value)` delegates one child. The reference map in both directions comes from the template, so the reader is derived, not written. The package of the domain depends on the engine packages and on no other domain. The tests of JSON are 599 lines and the examples 109. The [new domain guide](https://github.com/projectured/projectured-julia/blob/main/documentation/guide/new-domain-guide.md) walks through the same parts for a domain of your own.

### What I think is good about it

* Edits are typed operations on the data, not text patches. Your key presses, the assistant and an external MCP client all make the same operations. The same tests cover all three, and Ctrl+Z takes back a change of the assistant like one of yours.
* Projections compose. A sort, a filter, a search, a focus or a collapse is one more step in the chain, in front of any domain. A sorted or filtered view still takes edits, because each step maps the edit back through the step below it.
* Domains nest. JSON inside XML inside Markdown, a formula in a table cell, a Julia function whose body is an XML table whose rows come from a Julia loop. Navigation and editing cross the boundaries.
* The selection is a path into the data, not a caret position in a text. It survives a sort, a filter, an edit somewhere else in the document, and a switch to another view of the same data.
* Any value gets a view. `run_value_viewer(x)` opens a window on any Julia value, a running object included, as a tree that opens one level at a time. The tree is a shadow of the object, not a copy of it.
* The assistant is part of the kernel, not a plugin. It searches the API of the loaded packages by name, by pattern or by meaning (embeddings), reads the guides, and runs Julia in the editor process with `editor` bound. There's no fixed list of commands, it calls the same API you would. It runs on a local model through Ollama by default, or on Claude. The conversation is a document too, so you can select, edit and save it, and run Julia in it yourself.
* MCP is included. Start with `--mcp`, and Claude Code or any other MCP client gets the same tools at `http://127.0.0.1:9876/mcp`.
* The rendering is Julia code: layout, TrueType text, widgets and PDF output. SDL only puts the pixels in a window. The same view runs in a native window, in a browser, in a terminal, and with no screen at all for tests. It also goes to a vector PDF with selectable text, a PNG or an MP4.
* Data can share parts. Ctrl+N and a paste put the same object in a second place, so an edit in one place shows in both, and Ctrl+Shift+V pastes a copy instead. A text file uses the notation of its domain, and several files can refer to each other, so shared parts and mutually recursive structures come back unchanged after a save and a load.
* A domain is a package of its own, and no other domain depends on it. A new domain gets navigation, search, the clipboard, sorted and filtered views, a file format, every backend and the assistant with little or no extra code.
* A fault in a printer, a reader, an operation or a tool stays where it happened. The broken change is rolled back, the error is drawn where the view would be, and the editor keeps running.

About twenty domains exist today: JSON, YAML, XML, Markdown, reStructuredText, SQL, Julia code, math, tables, charts, sequence charts, graphs with automatic layout, state machines that generate runnable Julia, process flowcharts with breakpoints, widgets, the file system and a few more.

### Where it fits, and where it doesn't

I don't think it replaces anything you already use. Pluto and Jupyter are the better place for a narrative of code and prose, and ProjecturEd starts from the data instead of from the cell. It isn't a general text editor either, it edits the domains it has. Makie with Observables is the same idea in one direction, a picture that follows a value. ProjecturEd adds the way back, so a key press or a click in the picture changes the data, and it does that for trees, text, forms and tables too. With Gtk4, QML, Genie or Stipple you write the mapping from your data to the widgets and back yourself. Here that mapping is the thing you write, and the general features come with it.

The idea itself isn't new. JetBrains MPS is the big projectional editor, and Hazel and Lamdu are structure editors for one language each. If you know a tool that already does this combination (composable projections over arbitrary Julia data, fine grained reactivity, and a model that makes the same typed edits as the user), I'd really like to hear about it.

### What doesn't work yet

* Typing single characters doesn't behave the same way in every domain.
* A table renders and navigates, but a cell doesn't take an edit yet.
* A click selects only where a projection wires it. Elsewhere it does nothing.
* The packages aren't in the General registry, so you clone the repository.
* The first start compiles for a few minutes.
* The assistant needs a running Ollama server with a pulled model, or an Anthropic API key. A small local model makes more mistakes than Claude, so ask it for one change at a time.
* `execute_julia_code` runs anything the process can run. It's not a sandbox, and the MCP server has no authentication, it only listens on the loopback address. Don't start it on a machine you share.
* I use and test it on Linux. The native window needs SDL2 and SDL_ttf.

### Try it

```sh
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
bin/projectured                        # a window with a file navigator, tabs and the assistant
bin/projectured --backend=web a.json   # the same in a browser, at http://127.0.0.1:8080
bin/projectured --mcp a.json           # with the MCP server for an external client
```

`bin/build_projectured` compiles the application into a directory that runs without Julia and starts in well under a second.

From a REPL started with `julia --project=environment/all`:

```julia
using Projectured, ProjecturedExample, ProjecturedSdl

struct Point; x::Int; y::Int; end
run_value_viewer(Dict("origin" => Point(0, 0), "points" => [Point(1, 2), Point(3, 4)]))

run_example("json")   # one of the examples, in a window
```

The README has the guides and the full list of limits: https://github.com/projectured/projectured-julia
The web page: https://projectured.org
The Common Lisp original: https://github.com/projectured/projectured-lisp

### Licence, and how the code was written

It's free for noncommercial use, modification included. Commercial use needs a licence from me. So it isn't open source in the OSI sense, and I'd rather say that up front. Forks and pull requests are welcome.

The Julia code is about 110k lines plus 50k lines of tests, written with AI assistance (Claude Code). None of it was typed by hand. The test suite walks every example: the printer output, the reader, and the navigation to every position.

### What I'd like to hear

* Would you use it for your own data, and for what kind of data?
* Does the projection model make sense to you, or does it look like too much machinery for what it gives?
* What would you expect from an assistant that edits the data instead of the text?

I'm happy to answer questions about the projections, the reactive cells, or how a domain of your own would fit.
