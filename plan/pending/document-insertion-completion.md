# DocumentInsertion — live completion, commitability colouring, extensible registry

**Filed:** 2026-07-08. **Goal:** finish the `DocumentInsertion` type-in experience.
Typing into `Insert a new ⟨foo⟩ here` should give live feedback against the list of
insertable document types — both **type names** (`JsonInsertion`) and **human-readable
names** (`json insertion`, plus short aliases like `json`):

- **unambiguous prefix** → the rest of the name is rendered as a **pale greenish
  continuation** after the caret, and the typed characters turn **solid greenish**;
- **no possible completion** → the typed characters turn **reddish**;
- **ambiguous prefix** → the typed characters are greenish but **no continuation** is
  shown; **partial completion** (extending by the candidates' longest common prefix)
  is still available on Tab;
- newly defined document types are **automatically** part of the completion list;
- **Enter** replaces the insertion with the newly created document (this exists —
  extend it to also accept an unambiguous prefix, not only an exact name).

This is exactly the part flagged as *"Not yet ported: the live completion hint +
green/red commitability colouring"* in
[InsertionToSyntax.jl:22-24](../../package/domain/main/insertion/InsertionToSyntax.jl#L22-L24),
generalized with an extensible registry replacing the hard-coded `_FACTORY` table.

## Current state

| piece | where | status |
|---|---|---|
| `DocumentInsertion` (value buffer, `Insert a new … here` label) | [DocumentCore.jl:39-65](../../package/base/main/document/DocumentCore.jl#L39-L65) | done |
| char editing / Enter-commit / Escape-abort reader | [InsertionToSyntax.jl:120-189](../../package/domain/main/insertion/InsertionToSyntax.jl#L120-L189) | done |
| name → document factory | hard-coded `_FACTORY` table, [InsertionToSyntax.jl:193-213](../../package/domain/main/insertion/InsertionToSyntax.jl#L193-L213) | replace with registry |
| completion suffix computation | `default_completion` ([InsertionToSyntax.jl:220-227](../../package/domain/main/insertion/InsertionToSyntax.jl#L220-L227)) — computed but **never rendered** | rewire onto registry, render it |
| pale continuation rendering precedent | `JuliaInsertionToSyntaxLeaf` renders `close=TextString(() -> julia_completion(…), green)` ([InsertionToSyntax.jl:369-374](../../package/domain/main/insertion/InsertionToSyntax.jl#L369-L374)) | reuse the pattern |
| commitability colouring (green/red typed text) | nowhere | new |
| second render/commit site | ConversationEditor kind chooser: `_composer_factory` ([ConversationEditor.jl:238-243](../../package/domain/main/conversation/ConversationEditor.jl#L238-L243)), `_editable_body(::DocumentInsertion)` | reuse registry + colouring |

## Design

### A. Insertion registry (replaces `_FACTORY`, auto-extensible)

A registry of insertable document types. It must sit **below** every module that
defines an insertable document — `TextText` lives in the *visual* package, the domain
insertions in *domain* — so it goes in **base**, next to `DocumentInsertion` itself
(new `package/base/main/document/InsertionRegistry.jl`, sibling of `DocumentCore.jl`):

```julia
struct InsertionCandidate
    names::Vector{String}   # e.g. ["JsonInsertion", "json insertion", "json"]
    factory::Function       # () -> Document
end

register_insertion!(factory; type_name::Symbol, aliases=String[])
insertion_candidates() -> Vector{InsertionCandidate}
```

- `names` is auto-derived from `type_name`: the type name itself (`"JsonInsertion"`)
  plus the human-readable form (CamelCase → lowercase words: `"json insertion"`), plus
  explicit `aliases` to preserve today's short names (`"julia"`, `"json"`, `"xml"`,
  `"sql"`, `"text"`).
- **Automatic membership:** each module that defines an insertable document registers
  it at its own top level (`Julia.jl`, `Json.jl`, `Xml.jl`, `Sql.jl` in domain;
  `Text.jl` in visual). Defining a new document domain = one `register_insertion!`
  line in its own module; the insertion projection, its completions, and the
  ConversationEditor pick it up with **zero edits** to the insertion code. Registration
  is idempotent (keyed by `type_name`) so re-`include` during development is safe.
- All current registrants are submodules of packages that load the registry first, so
  top-level registration is baked in at precompile time; external/user packages call
  `register_insertion!` at their own load time (document in the registry docstring).
- *Rejected alternative:* fully-reflective `subtypes(Document)` enumeration. It drags
  in visual/infra document types (`SyntaxLeaf`, `TextString`, …), can't tell which
  types are meaningfully constructible as an empty insertion, and has load-order /
  world-age issues. One explicit registration line per type keeps the list exact and
  is still "automatic" from the insertion machinery's point of view.

### B. Completion semantics

In the registry module (pure functions over the candidate list, unit-testable
without any projection):

```julia
complete_insertion(typed) -> (state, continuation, matches)
resolve_insertion(typed)  -> Union{InsertionCandidate, Nothing}
```

- A *name matches* when `startswith(lowercase(name), lowercase(strip(typed)))` —
  case-insensitive so `json`/`Json`/`JsonInsertion` all type naturally; the rendered
  continuation uses the candidate name's own case for the remainder, the typed
  characters stay exactly as typed.
- `matches` = the **candidates** (deduped — one candidate may match via several of
  its names) with at least one matching name.
- `state`:
  - `:empty` — `typed` is blank → neutral colour, no continuation;
  - `:invalid` — non-blank, `matches` empty → **red**;
  - `:unambiguous` — exactly one candidate → **green**, `continuation` = the longest
    common prefix of that candidate's matching names beyond `typed` (so `"jso"` →
    `"n"`; `"json"`, which matches both the alias and `"json insertion"`, gets an
    empty continuation but is already exactly committable);
  - `:ambiguous` — ≥2 candidates → **green**, `continuation` rendered empty (per
    spec), but the LCP of *all* matching names beyond `typed` is still computed for
    Tab partial completion (e.g. candidates `json insertion` / `json document`:
    `"js"` ⇥ extends to `"json "`).
- `resolve_insertion(typed)`: an **exact** name match wins; otherwise the single
  candidate of an `:unambiguous` prefix; otherwise `nothing`. `default_factory` /
  `default_completion` become thin wrappers (kept exported so
  `DocumentInsertionTest` and any external callers keep working).

### C. Rendering — continuation span + reactive commitability colours

Today the printer emits one `SyntaxLeaf` (`open`=prefix, `value`, `close`=suffix)
with **static** styles. Two changes:

1. **Structure.** The continuation (pale green) and the `" here"` suffix (gray) both
   sit after the value but need different styles, and a `SyntaxLeaf` has only a
   single `close::TextString`. Restructure the printed output of
   `InsertionToSyntaxLeaf` to a `SyntaxNode` wrapping one leaf:

   ```
   SyntaxNode(open = "Insert a new " (label gray),
              close = " here"        (label gray),
              children = [ SyntaxLeaf(value    = typed text   (reactive colour),
                                      close    = continuation (pale green)) ])
   ```

   Selection mapping becomes `value{k}` ↔ `children[1]::SyntaxLeaf.value::TextString{k}`
   (both directions); verify caret enumeration with `test_text_navigation` on an
   example containing an insertion.
2. **Colour.** `TextString` fields are cells, so the typed-text colour is a computed
   cell — no per-keystroke re-print:

   ```julia
   TextString(() -> something(ins.value, ""), font,
              Cell(() -> _insertion_state_color(complete_insertion(something(ins.value, ""))[1])))
   ```

   with `:empty → color_default`, `:invalid → color_solarized_red`,
   `:unambiguous`/`:ambiguous → color_solarized_green`. The continuation span is a
   content thunk `() -> complete_insertion(…)[2]` styled **pale green** — a new
   constant (translucent solarized green, `StyleColor` alpha ≈ 0.5) exported from
   `Color.jl`, e.g. `color_completion_hint`. Switch `JuliaInsertionToSyntaxLeaf`'s
   continuation (today solid `color_solarized_green`) to the same constant so both
   insertions read identically: **solid green = typed & committable, pale green =
   what completion would add**.

### D. Gestures

Extend the `InsertionToSyntaxLeaf` gesture table
([InsertionToSyntax.jl:139-158](../../package/domain/main/insertion/InsertionToSyntax.jl#L139-L158)):

- **Enter** (exists): `_insertion_commit` goes through `resolve_insertion` — commits
  on exact name *or* unambiguous prefix; declines (`nothing`) on ambiguous/invalid,
  so the key keeps propagating as today.
- **Tab** (new): accept the completion — emit a `ReplaceStringRangeOperation`
  appending the continuation (unambiguous: the full remainder; ambiguous: the LCP
  partial completion) with the caret moved to the new end. Declines when the
  extension is empty, preserving any enclosing Tab behaviour.
- **Escape** unchanged (abort to `DocumentNothing`).

### E. ConversationEditor kind chooser reuses the registry

- `_composer_factory` delegates to `resolve_insertion`, filtered to the kinds the
  composer supports as source editors (julia/json/xml today) — the conversation
  chooser gains prefix commit for free without offering kinds it can't parse.
- `_editable_body(::DocumentInsertion)` gets the same reactive typed-text colour and
  pale continuation span (shared helpers exported from the registry / a small style
  helper, not copy-pasted thunks).

## Steps

- [ ] **A. Registry** — `InsertionRegistry.jl` in base (`register_insertion!`,
      `insertion_candidates`, name derivation `CamelCase → "camel case"`); registrations
      in `Julia.jl` / `Json.jl` / `Xml.jl` / `Sql.jl` / visual `Text.jl` with today's
      aliases; delete `_FACTORY`; `default_factory`/`default_completion` become wrappers.
      Verify: `test_document_insertion()` still green unchanged.
- [ ] **B. Semantics** — `complete_insertion` / `resolve_insertion` + unit tests for all
      four states, LCP partial completion, case handling, and "registering a new test-local
      document type makes it completable".
- [ ] **C. Rendering** — `SyntaxNode`-wrapping printer, updated forward/backward reference
      mapping, reactive typed-text colour cell, pale `color_completion_hint` constant
      (also adopted by `JuliaInsertionToSyntaxLeaf`). Verify colours/continuation by
      inspecting the printed spans' cells in `DocumentInsertionTest`; run
      `test_text_navigation` on an insertion-bearing example for the new structure.
- [ ] **D. Gestures** — Enter via `resolve_insertion` (unambiguous-prefix commit),
      new Tab accept-completion binding; tests: Enter on `"jso"` commits `JsonInsertion`,
      Enter on ambiguous/invalid declines, Tab appends continuation / LCP and moves caret.
- [ ] **E. ConversationEditor** — `_composer_factory` via registry (with the composer's
      kind filter), chooser body colouring; rerun the conversation editor tests.
- [ ] **F. Docs** — drop the "Not yet ported" note from the `InsertionToSyntax` module
      docstring; document the registry (one line in `documentation/document/` where the
      insertion flow is described).

Testing scope per CLAUDE.md: `test_document_insertion()` after each step, the
conversation tests after E, one `test_repl`/`test_text_navigation` on an
insertion-bearing example after C, `test_domain()` once at the end.

## Risks / open questions

- **`SyntaxNode` wrapping (C)** changes the printed shape every downstream projection
  sees (`SyntaxToText`, navigation, conversation decoration). The reference grammar for
  `children[1]` leaf spans is well-trodden (JSON/collection projections), but the text
  navigation sweep is the gate before merging.
- **Ambiguous rendering**: spec says no continuation on ambiguity; the LCP partial
  completion is therefore Tab-only and invisible until pressed. If that proves
  undiscoverable, the natural extension is rendering the LCP extension pale even when
  ambiguous — flagged as a possible follow-up, not in scope.
- **Registration timing**: top-level registration inside the existing packages is
  precompile-safe (single-image mutation); external packages must register at load
  time. If a cross-package precompile issue surfaces, fall back to `__init__`-time
  registration per package.
- **`JuliaInsertion` keyword completion** stays on its own `_JULIA_KEYWORD_SCAFFOLDS`
  table (keywords are not document types); only the pale-continuation style is shared.
