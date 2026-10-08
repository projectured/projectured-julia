# Primitive

> **Kind:** design · **Status:** current · **Stands on:** [document.md](../../kernel/document.md), [operation.md](../../kernel/operation.md), [serialization.md](../serialization/serialization.md)

The primitive slice of `ProjecturedPlatform` holds the editable scalar documents, the `ObjectField` that makes one field of any object a document, and the two operations that edit a range of characters. A domain uses these where it needs a value that you edit and that has a selection of its own. This document says how a range edit finds its target, how it is undone, and why `ObjectField` has the form it has.

<img width="396" alt="Primitive string example" src="../../../asset/image/example/primitive-string.png">

## How it works

| Document | Field |
| --- | --- |
| `PrimitiveBool` | `value::Bool` |
| `PrimitiveNumber` | `value`, a `Number` or `nothing` |
| `PrimitiveString` | `value`, a `String` or `nothing` |
| `PrimitiveInsertion` | `value`, what is typed so far, or `nothing`; `allowed_types`, the types that it can become, in the order of a try; `placeholder`, what it shows while it is empty, or `nothing` for `enter a value` |
| `ObjectField` | `object`, the root, and `path`, a `Reference` into it |

Each is an `@document` struct, so the value is in a reactive cell and the document has a `selection`. `PrimitiveDocument` is the abstract root of the first four. A `PrimitiveString` indexes by character, not by byte: `length`, `getindex` and `setindex!` go through `collect` and `splice_string`, so a multibyte character is one position.

This package has no projection. `PrimitiveToSyntax` of [syntax.md](../syntax/syntax.md) prints a primitive as a leaf, and `PrimitiveToText` of [text.md](../text/text.md) prints it as one span. `CellTableToWidgetTable` makes a primitive of each cell of a table.

### The range edits

A typed key reaches the domain as one of two operations. Each holds a `reference` from the root of the editor document and a `replacement` string:

- `ReplaceStringRangeOperation` edits the characters of a string field.
- `ReplaceNumberRangeOperation` edits the text form of a number and parses the result again.

**The path ends in `.<field>[s:e]`, and the field can be on any document.** `_split_replace_reference` splits the path into the target, the field name and the range. `evaluate_operation` then calls `splice_value!` of the kernel with the current value of the field. The kind of that value selects the method: a string, `nothing`, a number, a `TextString` or a `TextBlock`. So one operation edits a `JsonString`, a syntax delimiter and a text span. The number operation does not use this dispatch. It always parses, so an empty field becomes a number when you type a digit. After the edit, the selection is a caret after the inserted text.

**A number ignores a character that can not be part of a number.** `has_only_number_characters(text)` is true for a text of digits, signs, decimal points and exponent marks. A number edit whose replacement fails it changes nothing: the value, its text and the caret stay. A string edit of a field that holds a number does the same, because a text layer edits a number with a string edit. A cleared number holds `nothing`, so the string edit reads the declared type of the field from the native layout of the schema: a field that is declared to hold a number and not a text is a number field, and a digit typed into it makes a number. A `Bool` is not filtered. A replacement that passes the test is an edit even when the result does not parse yet, such as `1e` or `-`: the value is then `nothing` until the text parses. The template reader that makes a `ReplaceNumberRangeOperation` from a text edit declines such a key, so the key makes no edit and no undo step; see [projection.md](../projection/projection.md).

### The type-in of a number

A number holds only a parsed number. A key whose text the number can not show exactly, such as `-`, `1e`, `12.` or `1.50`, replaces the number with a `PrimitiveInsertion` of that text, limited to a number (`allowed_types = (PrimitiveNumber,)`), with the caret where the key left it. The type-in becomes a number again at the key whose text a number shows exactly, `-5` after `-`, and at Enter, when the text parses: `1.50` becomes `1.5`. Both documents keep their characters in `value`, so the path of the caret does not change when one replaces the other. The replace is an ordinary `make_replace_document_operation`, so undo takes it back.

The parts of the type-in are in this slice, so the syntax and the text printers share them: `make_type_in_edit_operation(insertion, range, replacement)` edits the text or makes the value that the new text shows exactly, `make_type_in_commit_operation(insertion)` makes the value that the text parses as, and `make_type_in_cancel_operation(insertion)` puts the first allowed type with no value, `make_empty_primitive_document(type)`. `find_value_range` reads the range `value{s:e}` of a selection or of a path, and `find_deletion_range` the range that Backspace or Delete removes. The rule runs in the reader of a primitive that is drawn on its own, as the natural renderer draws one; inside a syntax tree the tree maps a key back itself, and the number keeps the edit of its text.

`make_number_edit_operation(number, operation)` makes this rule for a reader of a key in a number: it answers the range edit itself when the number shows the new text exactly, or else the replace of the number with the type-in. A replacement with a character that no number has stays the edit, which changes nothing. `parse_primitive_document(type, text)` parses a text as a primitive of `type` or answers `nothing`, `get_primitive_text(document)` is the text that a primitive shows, `find_exact_primitive_document(types, text)` finds the first of `types` that shows `text` exactly, and `find_primitive_document(types, text)` the first that `text` parses as. `with_value_caret(document, k)` puts the caret at `k` in the value. The printer of the type-in and the reader that calls the rule are in [syntax.md](../syntax/syntax.md).

A path with no `.<field>[range]` at its end, for example a caret on a span that a projection added, splits to `nothing`. The operation then does nothing, and its inverse is `DoNothingOperation()`.

A projection reader maps a range edit back through the chain with no method of its own. Each operation has methods of `operation_reference`, `retarget_operation` and `reroot_operation`, and the default `read_intent` of the kernel uses these three. [operation.md](../../kernel/operation.md) describes the rerooting.

`ReplaceRangeOperation` is the abstract type of a range edit with these two fields. `ReplaceStringRangeOperation` and `ReplaceTextRangeOperation` of the text package are its subtypes, so the transport methods are written once. `ReplaceNumberRangeOperation` is not a subtype, because its meaning does not depend on the value of the field.

### The undo of a range edit

**The inverse of a range edit is a write of the whole field, not another range edit.** `make_inverse_operation` reads the old value of the field and returns `ReplaceReferencedValueOperation(target, field, old_value)`. The operation holds the target object and not a path from the root, so the undo still works after the document moves in the tree. It also puts back any kind of value: a string, `nothing`, a number or a styled span.

### One field of one object

`ObjectField(object, path)` makes one value inside an object a document, so a projection can show one field of a struct that is not a document. `ObjectField(object, "name")` is the form for one field step. `get_object_field_value` reads the value with `evaluate_reference`, and a write is `ReplaceReferencedValueOperation(object, path, value)`.

`get_object_field_value` must be read inside a cell. A printer that reads it outside one keeps the value of the first print.

`ObjectField` has no label field. `ObjectFieldToWidget` shows a bare control and needs no label, and `ObjectFieldToSyntax` takes the name from the last field step of the path with `get_object_field_name`. A path that ends in an element step has no name, and `get_object_field_name` returns `nothing`.

### Two ways a form edits a plain value

A plain value is a struct, a named tuple or a vector that holds its fields with no cell. A form edits it in one of two ways.

**A, a copy.** `convert_object_to_document(T, object)` makes a document of the `@document` schema `T`. `convert_document_to_object(T, document; base)` makes a plain `T` from a document. Both match a field by its name.

- A field of the schema that the object does not have is an error.
- A field of the object that the schema does not have is not copied, so a schema can show a part of a value. The way back takes such a field from `base`, the value that the document was made from. With no `base`, it is an error.
- A nested value converts when the declared type of the field in the schema is a schema. A vector converts element by element. The declared type comes from the native layout of the schema, so a schema with no native layout copies its values as they are.
- A value that can change is copied, so the document and the value share no object.

A commit is `convert_document_to_object`. A cancel drops the document.

**B, in place.** Each field of the form is an `ObjectField` whose `object` is the plain value in a `Cell`. Every field of the form shares that `Cell`. A write goes through the write rules of `ReplaceReferencedValueOperation`; see [operation.md](../../kernel/operation.md). A plain value that is given as it is gets a cell of its own in each field. An immutable value is then replaced in that one cell, so another field does not see the edit. `get_object_field_root(field)` is the root that a write carries: the object when it is a document, and else the cell.

| | A, a copy | B, in place |
| --- | --- | --- |
| Needs | a `@document` schema with the field names of the value | one `Cell` that holds the value |
| Edits | a document that is a copy | the value itself |
| Commit | `convert_document_to_object` | none; each edit is a commit |
| Cancel | drop the document | none; undo takes back an edit |
| Use when | the person must be able to cancel, or the form shows a part of the value | the edit must show at once in the value and in other views of it |

**The caret of a field** is a range in the text of its value. In the document it is the path `object.<path of the field>{start:stop}`. `make_object_field_range_reference(field, start, stop)` makes it, and `find_object_field_range(field, reference)` reads it, or answers `nothing` for another path. The object of a field is no child of the field for a walk of children: `child_reference_steps(::ObjectField) = ()`. A selection still goes through `object`.

## How it fits

The primitive slice depends on the kernel and on the serialization slice. The text, syntax, widget and projection slices, and panes and many domains, depend on it. `ObjectField` is in this slice because it is the lowest slice that both the widget and syntax slices use, and each of them holds one projection of it.

A `.pred` file builds `PrimitiveString` by its name, so a file can hold a bare string, such as the title of a tab. The field has no default, so the macro gives no keyword constructor, and the reader builds it from its field: `PrimitiveString("hi")` or `PrimitiveString(value = "hi")`. `has_document_duplicate` is `true` for every primitive, so a duplicated pane copies the value and does not share it; see [document.md](../../kernel/document.md).

## Design decisions

- **A scalar is a document.** A value then has its own selection and identity, and a domain does not write its own boolean or string leaf.
- **The edit dispatches on the value, not on the field name.** The field name is data. A new kind of text value needs one `splice_value!` method and no new operation.
- **The undo writes the whole field.** A range edit back would need a path that stays valid and a value of the same kind; the whole-field write needs neither. The reason is in `source/platform/primitive/PrimitiveDocument.jl`.
- **The number edit stays outside `ReplaceRangeOperation`.** It parses the text in every case, so it does not share the dispatch of the string edit.
- **`ObjectField` has no label.** The two projections need different labels, so a stored label would be wrong for one of them.

## Usage

```julia
flag = PrimitiveBool(true)
limit = PrimitiveNumber(42)
name = PrimitiveString("hé!")
length(name)                  # 3 characters
name[1:2]                     # PrimitiveString("hé")

edit = ReplaceStringRangeOperation(@reference(value{3}), " there")   # insert at the end

field = ObjectField(server, "name")
path  = ObjectField(net, Reference(FieldReferenceStep("hosts"), ElementReferenceStep(2),
                                   FieldReferenceStep("address")))
get_object_field_value(field)
get_object_field_name(path)   # "address"
```

- Examples: the atomic catalog has `primitive/string`, `primitive/number` and `primitive/bool`, from `example/platform/PrimitiveDocumentExample.jl`. `collection_example` shows a vector of `PrimitiveString`.
- Tests: `test_primitive()` in `test/platform/document/PrimitiveDocumentTest.jl`, `test_primitive_type_in()` in `test/platform/document/PrimitiveTypeInTest.jl`, `test_primitive_to_text()` and `test_object_field_to_widget()` in `test/platform/projection/`. A fault in a range edit often shows first in `test/platform/editor/TypeinTest.jl` or in the reader test of a domain.

## Limits

- Where no reader makes a type-in, a number edit whose text does not parse yet, such as `1e`, sets the value to `nothing`, and the text that was typed is gone: inside a syntax tree, in the math domain and in an operation that no reader made. JSON and YAML have the same limit for their own numbers.
- A type-in takes any character, also a letter, which shows red, while a number ignores a letter.
- The docstring of `ReplaceStringRangeOperation` leaves the result undefined when the caret is on the boundary between two adjacent strings.
