# Helper for the "construct doc, set selection, return doc" pattern in examples

Goal: factor out the recurring three-line idiom that appears in nearly every
`make_*_document_example` function, and let callers of those functions either
keep the default selection, override it, or opt out of setting any selection
at all.

The pattern today, repeated across 8 example files
([example/src/document/Json.jl:1-30](../../example/src/document/Json.jl#L1-L30),
 [Json.jl:36-40](../../example/src/document/Json.jl#L36-L40),
 [Syntax.jl:1-26](../../example/src/document/Syntax.jl#L1-L26),
 [Text.jl:1-9](../../example/src/document/Text.jl#L1-L9),
 [Book.jl:1-73](../../example/src/document/Book.jl#L1-L73),
 [LineNumbering.jl:1-18](../../example/src/document/LineNumbering.jl#L1-L18),
 [Math.jl:1-13](../../example/src/document/Math.jl#L1-L13),
 [Primitive.jl:1-5](../../example/src/document/Primitive.jl#L1-L5)):

```julia
function make_<name>_document_example()
    document = <Constructor>(...)
    set_selection!(document, @reference <path>)
    document
end
```

The three steps are mechanical: build, set, return. We want one place that
expresses that idiom, and we want every example function to accept an
optional `selection` argument so external code (tests, the workbench, the
introspection pages) can ask for the same document without a baked-in
selection — or with a different one.

---

## 1. The helper

Add a small two-method helper alongside the example utilities. The most
natural home is a new file, e.g. `example/src/document/Helpers.jl`, included
from [example/src/ProjecturedExample.jl](../../example/src/ProjecturedExample.jl)
**before** the per-domain document files (so they can use it). One file, two
methods:

```julia
"""
    with_selection(document, selection)

Set `document.selection` to `selection` and return `document`. The
no-op overload (`selection === nothing`) returns the document unchanged.
Used by the `make_*_document_example` factories to express the
"build → set selection → return" pattern as a single expression while
still letting the caller opt out by passing `selection=nothing`.
"""
with_selection(document, selection) = (set_selection!(document, selection); document)
with_selection(document, ::Nothing) = document
```

Export it from `ProjecturedExample` next to the other small helpers
(`make_graphics_caching`, etc.) — see
[example/src/ProjecturedExample.jl:97-100](../../example/src/ProjecturedExample.jl#L97-L100).

Why two methods and not a single one with a default `nothing`: the call site
in each factory passes a real reference by default, so the `nothing`
dispatch only happens when an outside caller explicitly requests it. Keeping
the methods separate keeps the hot path branchless and reads better at the
call site than `selection === nothing || ...`.

Why the name `with_selection` and not `select!` / `selecting`: `select!`
collides with Julia's verb conventions for in-place filtering (`Base.select!`
in DataFrames-style APIs); `with_selection(doc, sel)` reads as the
non-mutating-from-the-caller's-view operation it actually is (the caller
receives back `doc` ready to use), and visually pairs with `set_selection!`
which it wraps.

---

## 2. Update each example factory

Eight functions to update. Each gains one keyword argument and wraps the
constructor in `with_selection`. Default value of the keyword is the
existing hard-coded reference path; the body collapses to a single
expression.

### [example/src/document/Json.jl](../../example/src/document/Json.jl)

```julia
function make_json_document_example(; selection=@reference entries[1].value.value{2})
    with_selection(
        JsonObject(
            "name"    => JsonString("Alice"),
            ...,
            "placeholder" => JsonInsertion(),
        ),
        selection,
    )
end

function make_json_null_document_example(; selection=nothing)
    with_selection(JsonNull(), selection)
end

function make_json_string_document_example(; selection=@reference value{1})
    with_selection(JsonString("Hello, world"), selection)
end
```

Note `make_json_null_document_example` currently has no selection; we still
add the keyword for uniformity. Its default stays `nothing`, so its
external behaviour is unchanged.

### [example/src/document/Syntax.jl](../../example/src/document/Syntax.jl)

```julia
function make_syntax_document_example(; selection=@reference children[2].value{1})
    with_selection(
        SyntaxNode("(", ")", " ", SyntaxDocument[ ... ]; indentation=1),
        selection,
    )
end
```

### [example/src/document/Text.jl](../../example/src/document/Text.jl)

```julia
function make_text_document_example(; selection=@reference elements[1].content{3})
    regular = font_ubuntu_monospace_regular_24
    with_selection(
        TextText(TextString("Lorem ipsum ...", regular, color_default)),
        selection,
    )
end
```

(`regular` stays a local because it's reused if/when `nl()` comes back —
see the current body. If it isn't reused after the rewrite, inline it.)

### [example/src/document/Book.jl](../../example/src/document/Book.jl)

```julia
function make_book_document_example(; selection=@reference title{1})
    with_selection(
        BookBook([ ... ]; title="Projectured User Guide", author="..."),
        selection,
    )
end
```

### [example/src/document/LineNumbering.jl](../../example/src/document/LineNumbering.jl)

```julia
function make_line_numbering_document_example(; selection=@reference elements[3].content{10})
    newline = TextNewline(font=font_ubuntu_monospace_regular_24)
    with_selection(
        TextText( TextString(...), newline, ..., TextString(...) ),
        selection,
    )
end
```

### [example/src/document/Math.jl](../../example/src/document/Math.jl)

```julia
function make_math_document_example(; selection=@reference target.name{1})
    with_selection(
        MathAssignment(
            MathVariable("X"),
            MathBinaryOperation(:/, ..., PrimitiveNumber(2))),
        selection,
    )
end
```

### [example/src/document/Primitive.jl](../../example/src/document/Primitive.jl)

```julia
function make_primitive_string_document_example(; selection=@reference value{0})
    with_selection(PrimitiveString("Hello, world"), selection)
end
```

### [example/src/document/Xml.jl](../../example/src/document/Xml.jl)

Currently the `set_selection!` line is commented out
([Xml.jl:38](../../example/src/document/Xml.jl#L38)). We keep the same
behaviour by defaulting the keyword to `nothing`, and leave the commented
example reference as a developer hint inside the function body — or drop
the comment entirely, since the keyword now documents the opt-in.

```julia
function make_xml_document_example(; selection=nothing)
    with_selection(
        XmlElement("library", [...], [ ... ]),
        selection,
    )
end
```

### Not touched

Factories with no `set_selection!` call today —
`make_collection_document_example`,
`make_filesystem_document_example`,
`make_focusing_document_example`,
`make_julia_document_example`,
`make_lazy_document_example`,
`make_lazy_bidirectional_document_example`,
`make_layout_document_example`,
`make_mixed_document_example`,
`make_navigator_document_example`,
`make_object_document_example`,
`make_table_document_example`,
`make_math_table_document_example`,
`make_text_to_string_document_example`,
`make_widget_document_example`,
`make_widget_tabbed_pane_document_example`,
`make_word_wrapping_document_example`,
`make_workbench_document_example`,
`make_assistant_document_example`,
`make_wrapper_*` —
**stay as-is**. Adding a `selection=nothing` keyword to every factory "for
uniformity" is busywork on functions that don't have the pattern; the goal
is to factor a duplication, not to invent a new convention.

---

## 3. Call-site audit

The factories are called from a few places — verify each still works
because every new keyword has a default that matches the old behaviour:

- [example/src/Examples.jl:11-41](../../example/src/Examples.jl#L11-L41) —
  `Example("json", make_json_document_example, ...)` passes the factory as
  a zero-arg callable. `make_document()` in the `Example` constructor and
  in `run_example(... reset=true)`
  ([Examples.jl:105](../../example/src/Examples.jl#L105)) still calls it
  with no arguments → default selection applies. **No change required.**
- [example/src/document/Workbench.jl:10-16](../../example/src/document/Workbench.jl#L10-L16)
  calls six factories with no arguments. **No change required.**
- [test/src/projection/GraphicsToFileTest.jl:4,25](../../test/src/projection/GraphicsToFileTest.jl#L4)
  calls `make_json_document_example()` with no arguments. **No change
  required.**
- Any test that wants the *unselected* JSON document can now write
  `make_json_document_example(selection=nothing)` instead of constructing
  by hand.

Run the test suite (`test/runtests.jl`) after the change — the only
behavioural risk is a typo in a default reference; the suite already
exercises printers, readers, and selection round-trips through these
documents.

---

## 4. What we are *not* doing

- **Not** replacing `set_selection!` itself. It remains the underlying
  mutating API; `with_selection` is a thin convenience that wraps it.
- **Not** changing the `Example` struct, `run_example`, or
  `print_example` / `write_image_example`. They already work because the
  factory signatures stay zero-arg-callable.
- **Not** introducing a global "default selection" registry or any
  selection-config mechanism. The default lives at the factory call site
  as a keyword default — local, greppable, no indirection.
- **Not** adding a positional-arg form `make_json_document_example(sel)`.
  Keyword-only keeps call sites self-documenting and matches the rest of
  the example API (`make_widget_document_example(; width, height)`,
  `make_navigator_document_example(; root)`).
- **Not** moving `with_selection` into `Projectured` proper. It is purely
  an examples-side convenience; the `program/` API surface stays as
  `set_selection!` / `clear_selection!`.

---

## 5. Execution checklist

1. Create [example/src/document/Helpers.jl](../../example/src/document/Helpers.jl)
   with the two `with_selection` methods and a docstring.
2. Add the `include(... "Helpers.jl")` line at the top of the document
   includes in [example/src/ProjecturedExample.jl](../../example/src/ProjecturedExample.jl#L7)
   (before `Json.jl`), and `export with_selection` in the export block
   near [ProjecturedExample.jl:97](../../example/src/ProjecturedExample.jl#L97).
3. Rewrite the eight factories listed in §2.
4. Run `test/runtests.jl`. Investigate any failure; the most likely class
   is a reference-path typo in a `selection=` default.
5. Spot-check via the REPL: `run_example("json")`, `run_example("book")`,
   `run_example("primitive_string")` — the cursor should land in the same
   place it does today.
