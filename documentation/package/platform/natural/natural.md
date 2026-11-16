# The natural notation

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [concepts.md](../../../design/concepts.md), [domain-anatomy.md](../../../design/domain-anatomy.md), [projection-system.md](../../kernel/projection-system.md)

The natural slice of `ProjecturedPlatform` is where a domain says what its text looks like and which format writes it, and how a document of any domain reaches the screen with no projection written for the caller. A domain says the first with methods of the seams of this slice, which `print_natural_text` and `parse_natural_text` read. The renderer table, which `NaturalToGraphics` reads, says the second. This document says what the seams answer, how the renderer table takes the rows of the seams, and in which order the renderer tries its rows.

<img width="396" alt="Natural example" src="../../../asset/image/example/natural.png">

## How it works

### The ladder

A notation is a rung on one ladder:

```
domain ──▶ syntax ──▶ text ──▶ graphics
                        └────▶ string
```

A domain declares the projection of its documents to syntax, and the steps above it are composition. `:syntax` is the rung of a domain with a `*ToSyntax` projection. `:text` is the rung of prose: a `TextDocument` starts there, with the identity projection. A domain that draws itself, for example a page of blocks or a diagram, gives the renderer table a row of its own and has no rung here.

The steps are fixed, so one plain function of the natural slice makes them: `syntax → text`, then `text → graphics` or `text → string`. The natural slice makes the two steps from text itself, with `TextToGraphics` and `TextToString` of the text slice. It must not name the syntax slice, because the syntax slice names this one. So the natural slice declares `make_syntax_to_text_projection(; appearance)` with no method, and the syntax slice adds the one method, which makes `SyntaxToText`. A session with no method of it has no text form and no graphics form for a document that has only a syntax rung.

### The seams of a domain

A domain declares its notation and its format with methods. The JSON domain, in `source/domain/json/JsonToSyntax.jl` and `JsonFile.jl`:

```julia
make_syntax_projection(::Type{<:JsonDocument}; appearance) =
    JsonToSyntax(; theme = get_scaled_theme!(appearance, JsonTheme),
                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))

find_natural_file_format(::JsonDocument) = JsonFileFormat()
```

`JsonFileFormat` is the format of the serialization slice: it declares its extensions, its domain and its parser; see [serialization.md](../serialization/serialization.md). No table and no `__init__` holds any of this, and a domain is known as soon as its package is loaded.

| Seam | Answers | Read by |
| --- | --- | --- |
| `make_syntax_projection(type; appearance)` | the projection of the documents of `type` to syntax | `make_natural_projection`, `get_natural_entries`, `make_document_string` |
| `make_syntax_projection(format; appearance)` | the notation of the domain of `format`; a second format of a domain declares a method of its own | `make_document_string` |
| `find_natural_file_format(document)` | the format that writes `document` when nobody names one, or `nothing` | the fence of a code part, the label and the parser of a part of a conversation, `export_document` |
| `make_document_expression(document)` | the `Expr` that runs `document`; a document that is no code runs as its own value | the evaluator of the conversation slice |
| `make_syntax_to_text_projection(; appearance)` | the step from syntax to text | `make_natural_projection` |

The `FaultLog`, the `GestureLog` and the `MessageLog` declare `make_syntax_projection` and no format: they have a syntax notation and are never a file. The lookup of a notation or a format is the dispatch of Julia, so the most specific method answers, whatever the order of the methods: a method on an abstract root answers for every document under it, and a method on a subtype answers for that subtype. This slice has no method of `make_syntax_projection` for a type, so a caller that is not sure asks `hasmethod` first.

`parse_natural_text(format, text)` takes the short name of a format, its extension without the dot, such as `:json` or `:yml`, and reads `text` with `parse_document_string` of that format. `has_natural_parser(format)` says whether it reads the name: a format of the session has the extension, it parses a string, and its documents have a syntax notation. So plain text, `.pred`, a picture and a source file are no natural format, although `find_file_format` finds them. `describe_natural_formats()` lists the natural formats of the session, one line each.

The Julia domain declares `make_document_expression` for its documents, with `make_julia_expression`, and the evaluator of the conversation slice runs a structured form through `make_document_expression(form)` without depending on the Julia domain.

`make_natural_projection(document, target)` builds the chain from the document up to `:syntax`, `:text`, `:graphics` or `:string`. A `TextDocument` starts at the text rung; any other document starts at the syntax rung, with the projection of its type. The result is a `ChainingProjection` of `RecursiveProjection` stages, or `nothing` when no path exists. `print_natural_text(document)` is `make_natural_projection(document, :string)`, one print and a `String`. The general method of `make_document_string(format, document)` makes the same chain from `make_syntax_projection(format)`, so the string of a file and the natural text of its content are one string.

### The renderer table

`NaturalToGraphics(; measure, font, wrap, extra, appearance)` returns a `RecursiveProjection` over one `TypeDispatchingProjection` that draws almost any document to a `GraphicsCanvas`. The first row whose type matches the document wins, and each child of a matched row enters the same dispatcher again. So a JSON value inside a page and a widget inside a diagram each draw in their own domain. The dispatcher adds no printer, reader or reference map of its own; see [plan/done/natural-projection.md](../../../../plan/done/natural-projection.md).

Three keyed factory lists fill the table. The key of a factory is a `Symbol` that names the domain and makes a second call do nothing. A factory runs on each table build with the `Appearance` of the editor, so each renderer gets its own projection instances, and the factory fills the styles of each instance from the scaled theme of its domain in that editor. A row is never registered ready-made, because a projection holds the styles of one editor.

| List | Filled by | Read by |
| --- | --- | --- |
| syntax factories | `register_natural_syntax!(key, (; appearance) -> rows)` | `get_natural_syntax_entries(; appearance)` |
| graphics factories | `register_natural_graphics!(key, (; measure, appearance) -> rows)` | `get_natural_graphics_entries(; measure, appearance)` |
| fallback factories | `register_natural_fallback!(key, (; measure, font, wrap, appearance) -> rows)` | `get_natural_fallback_entries(; …)` |

A method of `make_syntax_projection` takes the same keyword `appearance`, and a method of `make_graphics_projection(T; measure, appearance)` takes `measure` too. `NaturalToGraphics` and `make_natural_projection` default to a new `Appearance`; inside the registries the keyword is required, so no step loses the appearance of the editor in silence. Every widget of the renderer draws with the `WidgetTheme` of the appearance.

**The renderer table takes the rows of the seam.** `get_natural_syntax_entries(; appearance)` returns the rows of the syntax factories, then `get_natural_entries(; appearance)`: a row for each type that has a method of `make_syntax_projection`, each before its supertypes. So one method is enough for a file, for text export and for a tab. The factory rows come first, so a factory row wins over the row of the seam for the same type. Markdown and RST use this: their syntax factory gives the rendered style to a tab, and their method of `make_syntax_projection` gives the source form to a file. A syntax factory serves the renderer only, and gives the type no notation.

`NaturalToGraphics` puts the rows in this order:

1. `extra`, the rows of the caller, so an application can replace any row;
2. the layouts, then the widgets;
3. `get_natural_graphics_entries`: the domains that draw themselves;
4. a `PrimitiveDocument` as plain text, through `PrimitiveToText` and `TextToGraphics`;
5. the fallback rows for exact types;
6. `DocumentNothing` as the phrase "empty document", a `GraphicsDocument` as itself through `GraphicsToGraphics`, an `ImageDocument` through `ImageToWidget`, `TextDocument` as prose with optional word wrap, and a `CellVector` as a stack of blocks, one for each element;
7. the fallback rows for `Any`;
8. `Any` as the phrase "no natural rendering for T".

**A picture draws as the label that shows it** (row 6). `ImageToWidget` prints an `ImageDocument` through a `WidgetLabel`, which draws the pixels at their natural size, or smaller in their shape to fit the maximum of its slot (`_fit_image_size`). The slot decides the size: a place that gives no limit, such as a scroll pane at its natural size, shows the pixels as they are. An `Image` whose size is not known yet draws a box with its path, and after a failed read it draws the path and the reason. The print reads `failure` and `get_image_natural_size` of the `Image`, which asks a task for the size in the head of the file, and never its pixels, so only the paint of a backend asks for a decode. The projection has no part of its own, and has no key.

**A primitive document draws as plain text** (row 4). A cell of a table, an element of a collection and a value in a tab show a string with no quotes, because the column, the field or the tab says the type. A primitive inside a syntax tree keeps its syntax leaf and its quotes: the syntax table prints that tree child by child, and there the quotes tell `"2"` from `2`. The text domain has the type-in of a number and the keys of a Bool; see [primitive.md](../primitive/primitive.md). `make_natural_primitive_row(; measure, appearance)` makes that row. `NaturalToGraphics` uses it, and a view with a table of its own, such as the pane of a task group, puts it in its dispatch, so the primitives of a document in that view draw as they draw in a tab.

The syntax rows reach the renderer through the fallback. The syntax slice registers a fallback whose `Any` row is the syntax fabric: `make_natural_to_syntax_dispatch(; appearance)`, then `SyntaxToText`, then `TextToGraphics`. That dispatch starts with `get_natural_syntax_entries(; appearance)` and ends with the collection rows and the reflection table of `ObjectToSyntax`. So a `JsonObject` in a tab matches no row above step 7, goes into the fabric, and draws through `JsonToSyntax`. A value of no domain draws as its reflected fields; see [reflection.md](../reflection/reflection.md). A session that loads no platform at all has no fallback at all: the same document then draws as the phrase of step 8, and the renderer never raises an error.

A `ListNode` stays in the syntax fabric and does not become a stack of blocks, because a list can be lazy or infinite. A conversation or a pane is not drawn by this dispatcher: its own projection makes widgets, and a caller that needs one inside a content slot adds a row with `extra`.

## How it fits

The natural slice depends on the kernel and on the text, layout, widget, graphics, domain and serialization slices: the serialization slice holds `FileFormat` and the seams of a format. It does not depend on the syntax slice or on a domain. The file-format slice depends on it.

| Registers | With |
| --- | --- |
| JSON, XML, YAML, SQL | `make_syntax_projection` and `find_natural_file_format` |
| Julia | `make_syntax_projection`, `find_natural_file_format` and `make_document_expression`, and a graphics factory that closes the dispatch of `JuliaToSyntax` |
| Markdown, RST, math | `make_syntax_projection` and `find_natural_file_format`, a syntax factory and a graphics factory |
| the message log, the gesture log, the fault log | `make_syntax_projection` |
| book | a syntax factory only |
| the file system | a syntax factory, and a graphics factory for the workspace |
| graph, formula, file format, inspector, assistant, evaluator | a graphics factory |
| the syntax slice | the fallback, and the method of `make_syntax_to_text_projection` |

**Prose.** `make_prose_document(text)` makes the document of a run of prose written in Markdown. It answers the document that the Markdown parser of the seam reads from `text`, when a format of the session reads `:md`. Else, or when the parse fails, it answers a text block of `text`. The conversation, the assistant and the work plan make their prose with it.

The file-format slice reads and writes files with `print_natural_text` and `parse_natural_text`; see [fileformat.md](../fileformat/fileformat.md). Each `XFile` type prints its content with `print_natural_text` in `emit_text`. The assistant checks `make_natural_projection(document, :string)` before it gives a document to the model as text. The [application slice](../application/application.md) draws every tab through `NaturalToGraphics`, with rows in `extra` for the documents that have a designed view.

## Design decisions

- **The renderer table names no domain.** A table that named each domain would put the renderer above all of them. Each domain registers its own row in a file that it already has, so the renderer sits below every domain. See [plan/done/natural-projection.md](../../../../plan/done/natural-projection.md).
- **What is not loaded is not supported.** The syntax step and the reflection tail come from the syntax slice of `ProjecturedPlatform`. A program that loads no platform at all, such as the kernel alone, carries neither.
- **The seams and the renderer table serve two questions.** The seams answer "this document, up to this target", where the notation of the document must win. The renderer table answers "any document, in any nesting, to pixels", where a caller or a domain can override a row.
- **The steps of the ladder are a plain function.** They are fixed, so no table holds them. The one step that the natural slice can not make, from syntax to text, is a seam with one method in the syntax slice, because the arrow between the two slices can not turn.
- **A row is a factory when it holds state.** A factory gives each renderer its own projection instances, so two windows do not share reactive state.
- **The renderer degrades and never fails.** The last row draws a one-line message, so a tab with an unknown value still shows something.

## Usage

```julia
document = parse_natural_text(:json, "{\"name\": \"Alice\"}")
text     = print_natural_text(document)
has_natural_parser(:json)                  # true
find_natural_file_format(document)         # JsonFileFormat()
chain    = make_natural_projection(document, :string)
renderer = NaturalToGraphics(measure = FontFileMeasure())
```

- Example: `natural_example` draws a `CellVector` of a JSON, a math, a Julia, a text and an XML document with `NaturalToGraphics` alone.
- Tests: no `test/natural/` folder exists. `test_natural_renders_every_atom()` checks that every atomic example draws through `NaturalToGraphics`, and `test_natural_round_trips_every_atom()` checks that every atom with a format prints and parses back. Both are in `test/projectured/projection/CatalogCoverageTest.jl`. `test_natural_notation()` checks that the most specific method gives the notation and the format, that a type with a notation is a row of the renderer before its supertype, that a document that is no code runs as its own value, and that the natural text of a document is the string of its format. `test_natural_registry()` checks that each build calls a syntax factory with its own `Appearance` and that a key registered twice keeps the first factory; both are in `test/projectured/projection/`. The first adds methods for types of its own and removes them when it ends, and the second puts the table back as it found it.

## Limits

- `NaturalToGraphics` takes the rows of `make_syntax_projection`, but not the text rung. `TextDocument` has a row of its own in the renderer, so no document loses its view today.
- A document that reaches the reflection tail shows its fields. It does not get the view of its domain.
