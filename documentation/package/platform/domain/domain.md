# Domain

> **Kind:** design · **Status:** current · **Stands on:** [macros.md](../../kernel/macros.md), [domain-anatomy.md](../../../design/domain-anatomy.md)

The domain slice of `ProjecturedPlatform` holds what makes a set of document types a domain: the `@domain` and `@insertion` macros, the empty placeholder and the insertion buffer that every domain shares, the completion of a typed type name, and the verbs that the structural gestures of a domain call. It is not a domain itself. This document says how these parts work and why they work by reflection and not by registration.

## How it works

### The core documents

| Type | What it is |
| --- | --- |
| `DocumentNothing` | the empty document of no domain, "Empty document" |
| `DocumentInsertion` | the typed-name buffer of no domain, which shows a pale "Type a kind" until the first key |
| `DocumentReference` | a document that holds a `Reference` into another document |

`DocumentNothing` and `DocumentInsertion` have the same traits that `@domain` makes for a domain. So the Insert and Escape gestures and the completion treat them as they treat `JsonNothing` and `JsonInsertion`.

### The macros

`@domain Json` makes the root `JsonDocument`, `JsonNothing`, `JsonInsertion`, the Insert-key gesture and the traits of the domain. An option adopts a type that exists instead of making one, for example `nothing = JuliaNothing`. `@insertion T = expr` declares what a committed insertion of `T` becomes. [macros.md](../../kernel/macros.md#domain) lists what each macro makes.

`@domain` does not write the two printer rules for the placeholder and the buffer. This package is below the projection packages, so it can not name a projection.

### Completion by reflection

`get_insertion_candidates(JsonDocument)` finds every concrete subtype of the root in the loaded modules. A type is a candidate when it is insertable: it has a zero-argument constructor, or an `@insertion` method. `get_insertion_names(T)` makes the names that a user can type: `JsonString`, `json string`, and inside the domain also `String` and `string`.

`compute_concrete_subtypes(root)` is the walk that `get_insertion_candidates` builds on. It answers every concrete type under `root` in the loaded modules and their submodules, depth first, and it tests nothing about a type except that it sits under `root`. A caller that wants the type tree and not the insertable subset of it calls this function directly; the help slice's list of every projection calls `compute_concrete_subtypes(Projection)`, because a projection is drawn and never inserted. `get_insertion_candidates(root)` then filters that walk down to what a person can insert: it drops the scope's own insertion, a native layout variant of another document's schema, and an insertion cursor that is not its domain's entry point, and it keeps what `insertable` accepts.

`complete_insertion(root, typed; place)` classifies what you typed as `:empty`, `:invalid`, `:unambiguous` or `:ambiguous`, and computes the common continuation. `resolve_insertion(root, typed; place)` returns the type to commit. An exact name wins over a prefix. The insertion leaf of the syntax slice shows this state as colours and a pale hint.

**A word of a name matches where no whole name does.** When no name starts with the typed text, a name of which a later word starts with it matches, as "chart" matches "sequence chart". Such a match has no continuation, because its name does not start with the text. `find_insertion_choices(root, typed; place, include)` gives the candidates for a list that a person picks from while typing, in two parts: those of which a whole name starts with the text, then those of which a word does. `include` keeps a type, such as `is_element_type`.

**A kind says what it shows and where it stands.** `get_insertion_icon(T)` is the glyph that a list of kinds shows before `T`, `nothing` by default, and the note after it is the summary of its docstring (`compute_docstring_summary`). `is_element_type(T)` says that a document of `T` stands on its own as an element of a record, such as code, a page of text, a table or a chart that a research item or a workflow step holds; it is `false` by default, and a domain says `true` for the documents that it offers so.

**The candidates follow the place.** `place` is the declared type of the place where the insertion stands, and only a candidate `T <: place` counts, so a person sees only what the place admits. `find_declared_place_type(reference)` finds that type from the reference of the place: the declared type of the field that its last step names, or the element type of the list whose element it names. It answers `nothing` when the reference records no type of the document that holds the place. The template builders give each child a context whose reference ends in steps typed against the parent, so the reference of an insertion that a template prints names the type of its place.

Both `compute_concrete_subtypes` and `get_insertion_candidates` are cached for each world age of Julia, one cache per root. So a type is a candidate as soon as its `struct` is evaluated, and when nothing changed the cost is one dictionary lookup.

### The shared verbs

The `@gestures` tables of the domains call three functions of this package. Each returns an operation, so no domain defines an operation type for these edits.

- `replace_selected_document(document, replacement)` replaces the selected node. It first moves a caret on a delimiter or a placeholder label to the node that the delimiter belongs to.
- `append_insertion_operation(document, field, T)` appends a new `T` to a `CellVector` field and places the caret that the `@insertion` of `T` declares.
- `move_to_field(document, from, to)` moves the selection from one field to another. Where the caret lands depends on the kind of the target: a child document is selected as a whole, and a text field gets a caret at `{0}`.

### Paste and open hooks

`accepts_pasted_document`, `accepts_pasted_replacement`, `accepts_pasted_text` and `accepts_opened_file` default to `true`. A domain adds a method to refuse a paste or a file. `make_pasted_document_operation(document, path, value)` defaults to `nothing`; a document that holds parts adds a method to take a pasted document that is no plain text, at a text cursor inside it, with an operation of its own (the clipboard asks it, see [clipboard.md](../clipboard/clipboard.md)). `compute_context_menu` defaults to `nothing`; a document that has a menu computes it from its own fields, and its type binds a right click to it with `make_context_menu_binding` of the widget slice ([context-menu.md](../widget/context-menu.md)). A tooltip is not here: a document declares a binding of the tooltip package in its own gesture table ([tooltip.md](../tooltip/tooltip.md)).

### The acquire and the release of a document

A document can need something when it enters the window: a sheet computes its values, and a file watches its disk file. It can also hold something outside the document tree: the assistant holds the process of an external agent and an MCP server. `acquire_document!(editor, document)` starts what the document needs, and `release_document!(editor, document)` frees what it holds. Both default to nothing, and a document type that needs or holds such a thing adds a method.

`AcquireDocumentOperation(document)` and `ReleaseDocumentOperation(document)` do not call the two functions directly. They add and remove a holder of the document. The open of a tab adds an acquire after the insert of the tab, and the close adds a release after the delete. The inverse of each is the other, so an undo of a close starts again what the tab needs.

**The count of holders.** The editor counts the holders of each document, as a session document. `add_document_holder!(editor, document)` counts one more holder and calls `acquire_document!` at the first holder. `remove_document_holder!(editor, document)` counts one less and calls `release_document!` at the last holder. So a document that two holders show starts what it needs once and frees it once. A mock editor that is not an `Editor` counts nothing and calls the hook at each call. `is_document_held(editor, document)` says whether a holder holds the document now, and changes nothing: a document that reads outside state for each of the parts that it shows, such as the rows of a long table that a view shows, reads only for the parts that a holder holds. A mock editor answers `true`.

**A view of a page.** `make_document_view(document)` makes the view document that shows a document as a page: it keeps the state of one view, such as the place of a long table, and names the document with `get_edited_field`. The default answers the document itself. `follow_content_selection!(view)` makes the selection of a new view and its part under the pointer follow those of the document, so a selection path keeps going through the document. A method of `make_document_view` changes no state, because a reader makes a view also for an answer that it only describes. The navigator makes the view of the page of each visit and holds it ([navigator.md](../navigator/navigator.md)).

**A holder that shows other documents.** A tab, a tree and a navigator hold the documents that they show. Each calls `hold_documents!(editor, holder, documents)` from its own `acquire_document!`, and `release_held_documents!(editor, holder, documents)` from its own `release_document!`. The editor records what each holder holds. So the release frees the documents that the holder held when it was acquired, also after the holder showed other documents.

`ChangeHeldDocumentsOperation(holder, released, acquired)` changes what a holder holds, as a node of a tree opens, a scroll brings rows of a tree into view, or a navigator visits another page. It acts only while the holder is held. A holder that no tab shows passes nothing on. A document that it already holds is not held again, and one that it does not hold is not released. Its inverse swaps `released` and `acquired`. The acquire, the release and the change are self-contained operations, so each goes up the readers of the views around a tree as it is.

### The read of outside state

A print reads only what a document holds. A document that needs outside state, such as the listing of a folder, reads it in an operation. `start_document_read!(editor, read, apply; wait)` runs `read()` on a task off the loop and applies the answer with the operation that `apply(answer)` returns. The answer is the value of `read`, or the exception that it threw, so `apply` also writes a failure.

The call waits for the read at most `DOCUMENT_READ_WAIT` seconds (0.05). A read that ends inside the wait is applied at once, in the evaluation that started it, so a small folder is complete in the first frame. A longer read posts its operation with `post_operation!` when it ends, and the next frame applies it. The document shows what it holds meanwhile. A mock editor that is not an `Editor` runs the read at once on the calling task. The call runs in the evaluation of an operation, such as an acquire, and never in a print.

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
