# Primitive

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The primitive substrate: `PrimitiveBool`, `PrimitiveNumber` and `PrimitiveString`,
one document per scalar value, each holding its value in a reactive `Cell`
with a selection and an identity of its own. Every other domain uses these
where it needs an editable scalar instead of inventing its own boolean or
string leaf.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/primitive/PrimitiveModule.jl` | the module, and what it exports |
| `source/primitive/PrimitiveDocument.jl` | `PrimitiveDocument`, `PrimitiveInsertion`, `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString`, and the range operations that edit them |
| `source/primitive/ObjectField.jl` | `ObjectField`, one field of one object addressed by a `Reference` |

## The document types

`PrimitiveDocument` is the abstract root. `PrimitiveInsertion` is the
domain's insertion placeholder, a hole awaiting a value: its `value` field
holds whatever has been typed so far, or `nothing` while still empty.
`PrimitiveBool`, `PrimitiveNumber` and `PrimitiveString` each wrap one value
— a `Bool`; a `Number` or `nothing`; a `String` or `nothing`.

`ReplaceRangeOperation` is the common shape a range edit takes;
`ReplaceNumberRangeOperation` and `ReplaceStringRangeOperation` are the two
concrete operations a text-editing reader resolves a keystroke to, one per
value type.

## `ObjectField`

```julia
ObjectField(server, "name")
ObjectField(net, Reference(FieldReferenceStep("hosts"),
                           ElementReferenceStep(2),
                           FieldReferenceStep("address")))
```

`ObjectField(object, path)` names one field of one object: `object` is the
root and stays fixed, `path` is a `Reference` addressing the value inside it.
`get_object_field_value` reads the value the path names. Read it inside a
reactive cell; reading it outside one freezes the render at the first value.
A write goes through `ReplaceReferencedValueOperation(object, path, value)`. `ObjectField` carries
no label field on purpose: `get_object_field_name` derives one from the last
`FieldReferenceStep` of the path when a projection needs it, and returns
`nothing` for a path that does not end in a field.

## How it fits

The primitive documents are the leaf values every projection pipeline ends
at: `ObjectFieldToSyntax` and `ObjectFieldToWidget` (in the `syntax` and
`widget` slices) each print an `ObjectField` as a single editable control or
token, which is how the reflection view
([reflection.md](../reflection/reflection.md)) and any other one-field
editor render a scalar without a domain of their own. `has_document_duplicate`
is `true` for every `PrimitiveDocument`, so copying one copies its value
rather than sharing the cell.

## What to check when a change touches this slice

There is no `test/primitive/` folder; the direct test is
`test/substrate/document/PrimitiveDocumentTest.jl`, and `ObjectField`'s two
projections are covered by `test/substrate/projection/ObjectFieldToWidgetTest.jl`
and `test/substrate/projection/ObjectToWidgetTest.jl`. Because the primitive
types back the insertion and the range edit of nearly every domain, a broad
regression after a change here usually shows first in
`test/substrate/editor/TypeinTest.jl` or in one domain's own printer/reader
suite rather than in this slice's own test.
