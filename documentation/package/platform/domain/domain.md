# Domain

> **Kind:** design · **Status:** current · **Stands on:** [macros.md](../../kernel/macros.md), [domain-anatomy.md](../../../design/domain-anatomy.md)

The domain slice of `ProjecturedPlatform` holds what makes a set of document types a domain: the `@domain` and `@insertion` macros, the empty placeholder and the insertion buffer that every domain shares, the completion of a typed type name, and the verbs that the structural gestures of a domain call. It is not a domain itself. This document says how these parts work and why they work by reflection and not by registration.

## How it works

### The core documents

| Type | What it is |
| --- | --- |
| `DocumentNothing` | the empty document of no domain, "Empty document" |
| `DocumentInsertion` | the typed-name buffer of no domain, "Insert a new … here" |
| `DocumentReference` | a document that holds a `Reference` into another document |

`DocumentNothing` and `DocumentInsertion` have the same traits that `@domain` makes for a domain. So the Insert and Escape gestures and the completion treat them as they treat `JsonNothing` and `JsonInsertion`.

### The macros

`@domain Json` makes the root `JsonDocument`, `JsonNothing`, `JsonInsertion`, the Insert-key gesture and the traits of the domain. An option adopts a type that exists instead of making one, for example `nothing = JuliaNothing`. `@insertion T = expr` declares what a committed insertion of `T` becomes. [macros.md](../../kernel/macros.md#domain) lists what each macro makes.

`@domain` does not write the two printer rules for the placeholder and the buffer. This package is below the projection packages, so it can not name a projection.

### Completion by reflection

`get_insertion_candidates(JsonDocument)` finds every concrete subtype of the root in the loaded modules. A type is a candidate when it is insertable: it has a zero-argument constructor, or an `@insertion` method. `get_insertion_names(T)` makes the names that a user can type: `JsonString`, `json string`, and inside the domain also `String` and `string`.

`compute_concrete_subtypes(root)` is the walk that `get_insertion_candidates` builds on. It answers every concrete type under `root` in the loaded modules and their submodules, depth first, and it tests nothing about a type except that it sits under `root`. A caller that wants the type tree and not the insertable subset of it calls this function directly; the help slice's list of every projection calls `compute_concrete_subtypes(Projection)`, because a projection is drawn and never inserted. `get_insertion_candidates(root)` then filters that walk down to what a person can insert: it drops the scope's own insertion, a native layout variant of another document's schema, and an insertion cursor that is not its domain's entry point, and it keeps what `insertable` accepts.

`complete_insertion(root, typed)` classifies what you typed as `:empty`, `:invalid`, `:unambiguous` or `:ambiguous`, and computes the common continuation. `resolve_insertion(root, typed)` returns the type to commit. An exact name wins over a prefix. The insertion leaf of the syntax slice shows this state as colours and a pale hint.

Both `compute_concrete_subtypes` and `get_insertion_candidates` are cached for each world age of Julia, one cache per root. So a type is a candidate as soon as its `struct` is evaluated, and when nothing changed the cost is one dictionary lookup.

### The shared verbs

The `@gestures` tables of the domains call three functions of this package. Each returns an operation, so no domain defines an operation type for these edits.

- `replace_selected_document(document, replacement)` replaces the selected node. It first moves a caret on a delimiter or a placeholder label to the node that the delimiter belongs to.
- `append_insertion_operation(document, field, T)` appends a new `T` to a `CellVector` field and places the caret that the `@insertion` of `T` declares.
- `move_to_field(document, from, to)` moves the selection from one field to another. Where the caret lands depends on the kind of the target: a child document is selected as a whole, and a text field gets a caret at `{0}`.

### Paste and open hooks

`accepts_pasted_document`, `accepts_pasted_replacement`, `accepts_pasted_text` and `accepts_opened_file` default to `true`. A domain adds a method to refuse a paste or a file. `compute_context_menu` defaults to `nothing`; a document that has a menu computes it from its own fields, and its type binds a right click to it with `make_context_menu_binding` of the widget slice ([context-menu.md](../widget/context-menu.md)). A tooltip is not here: a document declares a binding of the tooltip package in its own gesture table ([tooltip.md](../tooltip/tooltip.md)).

### The release of a document

A document can hold something outside the document tree: the assistant holds the process of an external agent and an MCP server. When such a document leaves the window, `release_document!(editor, document)` frees it. The default frees nothing, and a document type that holds such a thing adds a method. `ReleaseDocumentOperation(document)` calls it, and the close of a tab adds it after the delete of the tab. It changes no document, so its inverse is `DoNothingOperation()`: an undo of the close brings the document back, and the document starts again what it needs when it needs it.

## How it fits

The domain slice depends on the kernel only. Every domain uses it, and so do the text, syntax, clipboard, pane, file-format and natural slices.

## Design decisions

- **Completion reads the type tree. No list of names exists.** A new document type needs no registration to be a candidate.
- **The package finds subtypes without `InteractiveUtils`.** `compute_loaded_subtypes` is that walk, and the application slice finds a loaded backend with it too. `InteractiveUtils` needs the `Markdown` standard library, and this package is in the dependency closure of every downstream program. The own walk also reads all module names once, not once for each abstract type; the comment at `source/platform/domain/Domain.jl:26` gives the numbers.
- **Behaviour dispatches on traits.** A name is used only to show a type, never to decide what it does.
- **One appender for all domains.** `append_insertion_operation` takes the caret from the `@insertion` of the type, so the domains do not each derive it.

## Usage

```julia
@domain Json
@insertion JsonString = @selected JsonString("") value{0}

get_insertion_candidates(JsonDocument)       # every insertable JsonDocument type
complete_insertion(JsonDocument, "str")      # :unambiguous, with the continuation "ing"
resolve_insertion(JsonDocument, "string")    # JsonString
```

- Example: `json_insertion_example` opens a JSON document that holds an insertion buffer.
- Test: `test_document_insertion()` in `test/projectured/projection/DocumentInsertionTest.jl`. The package has no suite of its own.

## Limits

- `_zero_arg_constructible` calls `T()` in a `try` block, because `hasmethod(T, Tuple{})` does not see a required keyword argument.
- `get_domain_prefix` removes a trailing `Document` from the name of the root. A root with another name gets no prefix unless the domain defines the method.
