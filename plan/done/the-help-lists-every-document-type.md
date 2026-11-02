# The help lists every document type

Status: DONE on the branch `help-all-types`, not landed, 2026-11-02. Worktree
`/home/projectured/workspace/projectured-julia-help-all-types`, off main
`7a3e29df6`.

## The ask

The owner, 2026-11-02, with a picture of the NED group of the Documents tree:
"seems like not all documents are in the help ... there are more documentes in
the NED domain. I think other domains may also miss certain types, why is that?"
To the answer and the question whether the tree must list every type, the owner
said: "The help should list all types and mention if it can be created without
arguments or not."

## Facts (probe in omnet-julia, `ProjecturedAll` and `OmnetIde` loaded)

- The Documents tree took its types from `get_insertion_candidates(Document)`,
  the list of the name completion of an empty tab. 753 document types were
  loaded, and the tree showed 296.
- 442 types were left out because they have no constructor without arguments
  and no `make_insertion_document`, and 15 because they are the typing box of a
  root that is not the entry of its domain.
- NED: 25 types, 5 shown. JSON 9 of 11, Julia 17 of 62, SQL 16 of 42, the
  platform 115 of 293.

## The model

- **The domain slice lists every document type.** `compute_document_types(root)`
  answers the types of `compute_concrete_subtypes(root)` without the layout
  variants of another schema, such as `MFoo` of `Foo`. `get_insertion_candidates`
  filters that list, so both use one definition of a document type.
- **The Documents tree lists them all.** `HelpEntry` gets `creatable`: whether
  the type is one of `get_insertion_candidates(Document)`, that is, whether an
  empty tab creates it without arguments. `typed` holds names only for such a
  type.
- **The help says it.** The table of a group of document types has the column
  "without arguments", "yes" or "no", before "names to type". The page of a
  document type says "An empty tab creates it without arguments. Names to type:
  …" or "It needs arguments, so an empty tab can not create it." The line of
  the tree counts both: "753 document types in 29 packages. An empty tab creates
  296 of them without arguments: type one of their names in it."
- `creatable` means a member of the candidates. A placeholder such as
  `NedNothing` has a constructor without arguments but opts out of the
  candidates (`insertable` is `false`), so it shows "no": an empty tab does not
  create it.

## Steps

1. [x] **The list of every document type.** Add `compute_document_types` to the
   domain slice, and build `get_insertion_candidates` on it.
2. [x] **Every type in the tree, and whether an empty tab creates it.** Add
   `creatable`, the column, the line of the page and the count of the tree.
   Tests: `test_help_tree()` and `test_help_pages()`.
3. [x] **The guides.** help.md and domain.md.

## Not in this plan

- A count of NED in a picture: omnet-julia loads the packages of main, so that
  check runs after the landing.
