# The page of a type shows its fields

Status: IN PROGRESS, 2026-10-26. Branch `help-fields`, worktree
`/home/projectured/workspace/projectured-julia-help-fields`, off main `eb4d80fb0`.

## The ask

The owner, 2026-10-26: "can we add the shape of the document struct type to the
documentation in some way that helps understanding what are the degrees of
freedom? inlcuding field documentation if there's any". To the proposal of a
section of fields on the page of a type, as a table or as the text of the
struct, the owner answered: "I agree, use the table".

## Facts (probe on main `eb4d80fb0`, `ProjecturedAll` loaded)

| | Types with fields | Fields | With a declared type | With a field docstring |
| --- | --- | --- | --- | --- |
| Document types | 269 | 2,091 | 2,088, 385 of them `Any` | 657, in 39 types: themes and settings |
| Projections | 467 | 1,706 | none; the field type is a cell of the value type | none |

- `find_declared_field_type(T, name)` of the kernel gives the type that
  `@document` records for a field.
- A field docstring is in `Base.Docs.meta`, under the key `:fields` of the
  docstring of the type. `@theme` keeps them, and `get_theme_field_texts(T)` of
  the style slice answers them for a theme only.
- Every document has `selection` and `mouse_target`, which are view state.
  `is_view_state_field(T, name)` also answers the fields that
  `get_view_state_fields(T)` names.
- The code records no default value of a field that the help can read.

## The model

- **The kernel reads the field docstrings of any type.** The tool layer gets
  `collect_field_docstrings(T) -> Dict{Symbol,String}`, from `Base.Docs.meta`,
  beside `find_docstring_text`.
- **An entry stores its shape at the build.** `HelpEntry` gets `supertypes`, the
  supertypes of the type without its family type `A<Name>` and without `Any`,
  joined by " <: ", and `fields`, one named tuple for each field: `name`, `type`,
  `description`. The page reads no reflection when it prints (`PAR-PURE-THUNK`).
  - The fields leave out `selection` and `mouse_target`. Another field of view
    state has "View state, which a save does not keep." before its description.
  - The type is the declared type of a document field, and the value type of
    the cell of a projection field. A cell layout `AC<Name>{…}` of a document
    type shows as `<Name>`.
  - The description is the field docstring on one line, or "".
- **The page shows the shape.** Under the module, the line
  `JsonObject <: JsonDocument <: Document`; after the docstring, a table with
  the columns field, type and description: the field and the type as wide as
  their content, the description in the rest. A type with no field shows "No
  fields.".

## Steps

1. [x] **The field docstrings.** Add `collect_field_docstrings` to the tool
   layer of the kernel. Test: new cases in `test_docstring_summary()`. Done:
   19 of 19.
2. [x] **The shape of an entry and its table.** Add `supertypes` and `fields` to
   `HelpEntry`, their build, and the line and the table on the page. Test: new
   cases in `test_help_tree()` and `test_help_pages()`: `HelpTheme` has the
   field `font` of type `StyleFont` with its docstring; `HelpGroup` has four
   fields and no `selection`; `HelpGroupToWidget` has `gap` of type `Int64`; the
   page of `HelpTheme` draws the table. Done: `test_help()` 92 of 92,
   `test_help_themes()` 108 of 108, and `test_platform_layering()` shows only
   the baseline of main (two files with a symbol list on a `using`).
   - Found in the step: `string(T)` names a type with its module path, such as
     `ProjecturedPlatform.CollectionModule.CellVector`, so the formatter removes
     the module paths. It keeps the printed text otherwise, because Julia prints
     a union by its alias, such as `ThemeText`, and rebuilds the text only when
     it shows a cell layout. A name counts as a cell layout only when the module
     defines the name without `AC`, so `ACPSession` stays.
3. [ ] **The guide and a picture.** Update help.md. Draw the page of a theme and
   of a projection in a live window. Move this plan to `plan/done/`.

## Not in this plan

- The default value of a field.
- A field as a node of the tree.
