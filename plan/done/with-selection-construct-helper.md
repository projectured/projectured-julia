# `with_selection` — construct-and-select helper

## Motivation

Building a document literal and then placing a **deep** selection inside it is a
recurring two-step pattern across the codebase:

```julia
doc = SomeDocument(...)
set_selection!(doc, @reference some.deep.path)
```

and, in the gesture→operation builders, a *shallow* local helper that only sets
the top selection cell:

```julia
_sel!(doc, path) = (getfield(doc, :selection)[] = path; doc)        # Json.jl
_xml_sel!(doc, path) = (getfield(doc, :selection)[] = path; doc)    # XmlToSyntax.jl
```

We want one reusable, properly-propagating primitive: **construct a document and
set its selection deeply, returning the document**, usable as a single
expression.

## Why a helper, not a `@document`/constructor change

- The `@document` macro emits exactly **one** inner constructor, which is shared
  by the snapshot/hydrate path (`Foo(ifoo::IFoo)`). Hydration passes the
  already-canonical *stored* selection and must do a plain shallow field-set — it
  must **not** re-walk/re-annotate. So deep propagation cannot live in the inner
  constructor. The existing `selection` field argument (positional / `kwdef`
  keyword) is correctly the shallow set and stays that way.
- Deep propagation is `set_selection!`, which canonicalizes via
  `annotate_reference_types` — a layer **above** the kernel `@document` macro
  (`common/Document.jl`). Calling it from generated constructors is a layering
  inversion.

So: a one-line helper next to `set_selection!`, returning the doc so it reads
constructor-like.

## Design

```julia
with_selection(document, path) = (set_selection!(document, path); document)
```

- Declared in `DocumentApiModule` (`kernel/src/api/Document.jl`) alongside
  `set_selection!` / `clear_selection!`, added to its `export` list. The umbrella
  `Projectured` re-exports every public submodule name mechanically, so
  `with_selection` becomes available via `using Projectured` automatically (no
  edit to the umbrella).
- Implemented in `OperationModule` (`kernel/src/common/Operation.jl`) next to
  `set_selection!`; add `with_selection` to its `import ..DocumentApiModule:`
  line.

## Migration scope

Migrate the genuine **construct-and-select** sites (build a fresh document and
hand it on as one value):

- [x] `Json.jl` — replace `_sel!` at its 8 gesture call sites, delete `_sel!`.
- [x] `XmlToSyntax.jl` — replace `_xml_sel!` at its 2 sites, delete `_xml_sel!`.
- [x] `Formula.jl` — `with_selection(FormulaEnvironment([...]), @reference formulas[1])`.

Deliberately **left on `set_selection!`** — these are in-place selection updates
of an existing/reused document (or a long-lived screen), not construct-and-select,
so `with_selection`'s return-the-doc shape adds nothing:

- `Examples.jl:307` (loop variable, wrapped afterward), `:383` (screen-rooted).
- `LiveExamples.jl:104` / `:113` (in-place / screen-rooted).
- `ProjecturedVideo.jl:134` (conditional clear/set on an existing param).

## Caveat to verify by test (gesture path)

`_sel!` left a **raw** path in the top cell; `with_selection` (via
`set_selection!`) leaves a **canonical** one (type checkpoints). The JSON/XML
type-to-replace gestures feed that top cell through
`replace_document` → `_concat_paths(strip_reference_types(path), inner_sel)`
([Operation.jl]). The editor re-propagates from the root via `update_selection!`,
which re-annotates on divergence, so the final stored state should be identical —
but this must be confirmed empirically, not assumed.

Tests: targeted JSON type-to-replace / repl, XML equivalent, and the Formula
example still constructs with its seeded selection.

## Test results (verified)

Package compiles/loads cleanly with the new wiring. Targeted battery:

- `test_json` 24/24; `test_repl(json_example)` 225/225; `test_repl(xml_example)`
  225/225; `test_formula_to_syntax` 36/36 — all green.
- `test_json_to_syntax_reader` 47/1/0 = documented baseline. The
  **"type-to-replace builds the right document"** subtests (the path this change
  touches) are **19/19 green**; the single failure is the pre-existing
  "array insert appends an insertion" quirk (`_array_insert`, untouched).
- `test_typein(json_example)` 0/22 and `test_typein(xml_example)` 0/51 fail
  wholesale ("no cursor in Graphics image"). **Confirmed pre-existing**: reverting
  the 5 files to the base commit reproduces the identical 0/22 and 0/51, so this
  is unrelated to the change (typing into a leaf char-cursor never hits the
  `when(_json_replaceable …)`-guarded type-to-replace gestures).

Caveat resolved: the canonicalized top-cell selection threads through
`replace_document`/`_concat_paths` correctly — the 19/19 type-to-replace
assertions and 225/225 repl roundtrips confirm no behavioural change.

## Status

Done — implemented in commit `55821d4`, verified no regressions.
