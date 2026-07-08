# DocumentInsertion — live completion, commitability colouring, Insert-key insertions

**Filed:** 2026-07-08. **Steer (same day):** no registry — static candidate tables are
enough this time; completion names are **derived automatically from type names**; the
**Insert key** turns the `*Nothing` placeholder documents into their domain's
insertion; domain insertions (`JsonInsertion`, `XmlInsertion`, `JuliaInsertion`) get
the same completion behaviour **constrained to their own domain**, matched **without
the domain prefix**.

**Goal:** finish the insertion type-in experience. Typing into
`Insert a new ⟨foo⟩ here` gives live feedback against the candidate list:

- names are auto-derived from the document type name — both the **capitalized type
  name** (`JsonString`) and the **lowercase human-readable form** (`json string`,
  CamelCase split into words) are accepted, with no hand-maintained name lists;
- **unambiguous prefix** → the rest of the name renders as a **pale greenish
  continuation**, the typed characters turn **solid greenish**;
- **no possible completion** → the typed characters turn **reddish**;
- **ambiguous prefix** → typed characters greenish, **no continuation** shown;
  **partial completion** (extend by the candidates' longest common prefix) stays
  available on Tab;
- **Enter** replaces the insertion with the newly created document (exists today for
  exact names — extend to unambiguous prefixes);
- **Insert key**: `DocumentNothing` → `DocumentInsertion`; per domain,
  `JsonNothing` → `JsonInsertion`, `XmlNothing` → `XmlInsertion`,
  `JuliaNothing` → `JuliaInsertion`;
- inside a `JsonInsertion` the candidates are the JSON document types matched
  **without the `Json` prefix** (`string`/`String` → `JsonString`); Julia and Xml
  likewise.

This delivers the part flagged *"Not yet ported: the live completion hint + green/red
commitability colouring"* in
[InsertionToSyntax.jl:22-24](../../package/domain/main/insertion/InsertionToSyntax.jl#L22-L24).

## Current state

| piece | where | status |
|---|---|---|
| `DocumentInsertion` + `DocumentNothing` | [DocumentCore.jl:25-65](../../package/base/main/document/DocumentCore.jl#L25-L65) | done |
| char editing / Enter-commit / Escape-abort on the shared insertion leaf | [InsertionToSyntax.jl:120-189](../../package/domain/main/insertion/InsertionToSyntax.jl#L120-L189) | done |
| name → document factory (`_FACTORY`: `julia`/`json`/`xml`/`sql`/`text`) | [InsertionToSyntax.jl:193-213](../../package/domain/main/insertion/InsertionToSyntax.jl#L193-L213) | generalize to derived-name candidate tables |
| completion suffix computed but **never rendered** | `default_completion` ([InsertionToSyntax.jl:220-227](../../package/domain/main/insertion/InsertionToSyntax.jl#L220-L227)) | render it |
| pale continuation rendering precedent | `JuliaInsertionToSyntaxLeaf` (`close=TextString(() -> julia_completion(…), green)`, [InsertionToSyntax.jl:369-374](../../package/domain/main/insertion/InsertionToSyntax.jl#L369-L374)) | reuse pattern |
| commitability colouring (green/red typed text) | nowhere | new |
| `JsonInsertion` | static `"insert JSON here"` leaf ([JsonToSyntax.jl:37-44](../../package/domain/main/json/JsonToSyntax.jl#L37-L44)); `value::Any = nothing`, **not a text buffer** | becomes a typed-name buffer |
| JSON type-to-replace char gestures (`"`→string, `[`→array, …) | [Json.jl:254-264](../../package/domain/main/json/Json.jl#L254-L264) | keep; share factories with the candidate table |
| `JsonNothing` / `XmlNothing` | do not exist (`JuliaNothing` exists as the AST literal, [Julia.jl:81](../../package/domain/main/julia/Julia.jl#L81)) | add (Lisp parity: `json/nothing`) |
| Insert-key precedent | `@gestures XmlElement` `KeyDown(:insert)` → append `XmlInsertion` child ([Xml.jl:162-168](../../package/domain/main/xml/Xml.jl#L162-L168)) | reuse pattern |

## Design

### A. Candidate tables with auto-derived names (no registry)

Stay with `const` tables in the modules that own them (like today's `_FACTORY` and
`_JULIA_KEYWORD_SCAFFOLDS`). What changes is that a candidate is keyed by its **type**
and its accepted names are **derived**, not listed:

```julia
struct InsertionCandidate
    type_name::Symbol      # :JsonString
    factory::Function      # () -> document with cursor pre-placed (with_selection)
    aliases::Vector{String}# extra short names, e.g. "julia" for JuliaInsertion
end

# derived automatically, once, at table construction:
#   "JsonString"      (the capitalized type name)
#   "json string"     (CamelCase → lowercase words — automatically understood)
# and for a domain-scoped table (strip_prefix = "Json"):
#   "String", "string"
candidate_names(c; strip_prefix = nothing) -> Vector{String}
```

- **Top-level table** (for `DocumentInsertion`): each domain's insertion
  (`JuliaInsertion`, `JsonInsertion`, `XmlInsertion`, `SqlInsertion`, `TextText`) with
  today's short aliases (`"julia"`, `"json"`, …) kept as exact-commit names, **plus**
  each domain's concrete value candidates under their full prefixed names — so
  `JsonString` / `json string` commit a `JsonString` directly from the top level.
- **Domain tables**: JSON — `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`,
  `JsonArray`, `JsonObject`, `JsonObjectEntry`, matched prefix-free; the factories are
  exactly the `with_selection(…)` constructions already used by the char gestures
  ([Json.jl:256-262](../../package/domain/main/json/Json.jl#L256-L262)) — factor them
  out so char-replace and name-commit share one source. XML — `XmlElement`, `XmlText`
  (children context; `XmlAttribute` excluded, it cannot stand alone). Julia — the
  existing `_JULIA_KEYWORD_SCAFFOLDS`: the unprefixed human-readable name of
  `JuliaFunction` *is* `"function"`, so the keyword table already is the Julia
  candidate table; it additionally gains the capitalized forms (`Function`,
  `JuliaFunction`) via the same name derivation.
- Matching is case-insensitive on the derived names; the rendered continuation uses
  the candidate name's own case for the remainder while the typed characters stay
  exactly as typed.

### B. Completion semantics

Pure functions over a candidate table (unit-testable without any projection),
in `InsertionToSyntax.jl`:

```julia
complete_insertion(candidates, typed) -> (state, continuation, matches)
resolve_insertion(candidates, typed)  -> Union{InsertionCandidate, Nothing}
```

- A name matches when `startswith(lowercase(name), lowercase(strip(typed)))`;
  `matches` is the set of **candidates** (deduped — one candidate may match via
  several of its names).
- `state`:
  - `:empty` — blank → neutral colour, no continuation;
  - `:invalid` — non-blank, no match → **red**;
  - `:unambiguous` — exactly one candidate → **green**; `continuation` = the longest
    common prefix of that candidate's matching names beyond `typed`
    (`"jso"` → `"n…"` of the matching name, `"stri"` → `"ng"` inside a JSON hole);
  - `:ambiguous` — ≥2 candidates → **green**, continuation rendered empty (per spec);
    the LCP of all matching names beyond `typed` is still computed for Tab partial
    completion.
- `resolve_insertion`: an **exact** name/alias match wins (so `"julia"` commits
  `JuliaInsertion` even though it is also a prefix of `julia function`, keeping
  today's `default_factory` behaviour); otherwise the single candidate of an
  `:unambiguous` prefix; otherwise `nothing`. `default_factory` /
  `default_completion` become thin wrappers over the top-level table.

### C. Rendering — continuation span + reactive commitability colours

Unchanged from the pre-steer design, now shared by **three** leaves
(`DocumentInsertion`, `JsonInsertion`, `XmlInsertion` — Julia already close):

1. **Structure.** The continuation (pale green) and the label suffix (gray) both sit
   after the value but need different styles, and a `SyntaxLeaf` has a single
   `close::TextString`. The shared `InsertionToSyntaxLeaf` printer emits a
   `SyntaxNode` wrapping one leaf:

   ```
   SyntaxNode(open = prefix label (gray), close = suffix label (gray),
              children = [ SyntaxLeaf(value = typed text  (reactive colour),
                                      close = continuation (pale green)) ])
   ```

   Selection mapping becomes `value{k}` ↔ `children[1]::SyntaxLeaf.value::TextString{k}`;
   gate with `test_text_navigation` on an insertion-bearing example.
2. **Colour.** `TextString` fields are cells, so the typed-text colour is a computed
   cell — no per-keystroke re-print: `:empty → color_default`,
   `:invalid → color_solarized_red`, `:unambiguous`/`:ambiguous →
   color_solarized_green`. The continuation span is a content thunk styled with a new
   **pale green** constant in `Color.jl` (translucent solarized green, alpha ≈ 0.5),
   e.g. `color_completion_hint`; `JuliaInsertionToSyntaxLeaf`'s continuation (today
   solid green) switches to it. Convention: **solid green = typed & committable, pale
   green = what completion would add, red = dead end**.

### D. Gestures on the insertion leaf

- **Enter** (exists): `_insertion_commit` goes through `resolve_insertion` — commits
  on exact name *or* unambiguous prefix; declines on ambiguous/invalid so the key
  keeps propagating.
- **Tab** (new): accept the completion — `ReplaceStringRangeOperation` appending the
  continuation (unambiguous: full remainder; ambiguous: LCP partial completion),
  caret to the new end; declines when the extension is empty (preserving enclosing
  Tab behaviour, e.g. Julia's commit-and-next-hole).
- **Escape** unchanged (abort to the domain's `*Nothing`; see E).

### E. Insert key: `*Nothing` → domain insertion

- New placeholder documents **`JsonNothing`** and **`XmlNothing`** (mirroring
  `DocumentNothing`; Lisp parity `json/nothing`) with minimal gray leaf projections;
  `JuliaNothing` and `DocumentNothing` already exist.
- Document-level gesture tables (the `@gestures XmlElement`/`:insert` pattern):

  ```julia
  @gestures DocumentNothing begin
      KeyDown(:insert) => "Insert a document" =>
          replace_document(∅, with_selection(DocumentInsertion(""), @reference value{0}))
  end
  # likewise: JsonNothing → JsonInsertion, XmlNothing → XmlInsertion,
  #           JuliaNothing → JuliaInsertion — each cursor pre-placed at value{0}
  ```

- Escape from an insertion aborts back to the **matching** `*Nothing`
  (`JsonInsertion` → `JsonNothing`, …) instead of always `DocumentNothing`, closing
  the loop: Insert ⇄ Escape within a domain. The `*Nothing` placeholders are **not**
  candidates in any table (they are not values you insert).

### F. Domain-constrained insertions

- **`JsonInsertion`** grows a `value::String` buffer (today `value::Any = nothing`)
  and is projected through the shared `InsertionToSyntaxLeaf` (own label, e.g.
  `insert a ⟨…⟩ here` — replacing the static `"insert JSON here"` hint) with the JSON
  candidate table, prefix-free matching, and the C/D behaviour. Coexistence with the
  existing single-char type-to-replace gestures is already arranged by
  `_json_replaceable` ([Json.jl:196-208](../../package/domain/main/json/Json.jl#L196-L208)):
  it declines on a **char cursor**, so with the caret inside the insertion's buffer,
  characters type into the buffer (`s`,`t`,`r`… with live completion), while a
  whole-node selection keeps the quick `"`/`[`/`{`/digit replaces.
- **`XmlInsertion`** likewise, over the XML table (`element`/`Element`/`XmlElement`,
  `text`/…).
- **`JuliaInsertion`** keeps its dual commit (keyword scaffold **or** `juliaparse` of
  a complete expression) — only the *feedback* is upgraded to the shared colour
  states: green when the buffer is a keyword prefix **or** parseable as complete
  source, red otherwise, pale continuation for the keyword remainder as today.
- **`SqlInsertion`** stays parse-only (green when `sqlparse` succeeds, red otherwise)
  — no candidate table this round.

### G. ConversationEditor kind chooser

`_composer_factory` ([ConversationEditor.jl:238-243](../../package/domain/main/conversation/ConversationEditor.jl#L238-L243))
delegates to `resolve_insertion` over the top-level table filtered to the kinds the
composer can parse (julia/json/xml), gaining prefix commit; the chooser body
(`_editable_body(::DocumentInsertion)`) reuses the reactive colour + continuation
helpers rather than copy-pasting thunks.

## Steps

- [ ] **A. Tables + name derivation** — `InsertionCandidate`, CamelCase→words
      derivation, prefix stripping; top-level table replaces `_FACTORY` (aliases kept,
      `default_factory`/`default_completion` as wrappers); JSON/XML tables with factories
      factored out of the char-gesture table. Verify: `test_document_insertion()` green
      unchanged, plus name-derivation unit tests (`JsonString` ⇄ `json string`).
- [ ] **B. Semantics** — `complete_insertion`/`resolve_insertion` + unit tests for the
      four states, LCP partial completion, exact-alias-beats-ambiguity, case handling.
- [ ] **C. Rendering** — `SyntaxNode`-wrapping printer, updated reference mapping,
      reactive typed-text colour cell, `color_completion_hint` constant (adopted by the
      Julia leaf). Verify colours/continuation by inspecting printed span cells;
      `test_text_navigation` on an insertion-bearing example.
- [ ] **D. Gestures** — Enter via `resolve_insertion`, Tab accept-completion; tests:
      `"jso"`+Enter commits, ambiguous/invalid declines, Tab appends and moves the caret,
      Julia Tab-to-next-hole unaffected.
- [ ] **E. Insert key** — `JsonNothing`/`XmlNothing` documents + leaf projections;
      `@gestures` Insert on all four `*Nothing`s; Escape aborts to the matching
      `*Nothing`. Tests per domain (the `XmlToSyntaxTest` `:insert` test is the model).
- [ ] **F. Domain insertions** — `JsonInsertion` buffer + shared leaf + JSON table;
      `XmlInsertion` likewise; Julia colour states. Rerun `test_json()`, `test_xml()`,
      `test_julia_typein`, and the JSON repl example (`test_repl(json_example)`) since the
      insertion leaf changes shape.
- [ ] **G. ConversationEditor** — chooser via `resolve_insertion` + shared colouring;
      rerun the conversation tests.
- [ ] **H. Docs** — drop the "Not yet ported" note from the `InsertionToSyntax` module
      docstring; note the Insert/Escape loop and the name-derivation rule in
      `documentation/document/json.md` / `xml.md` where insertion flow is described.

Testing scope per CLAUDE.md: `test_document_insertion()` after each step; the narrow
domain suites after E/F; `test_domain()` once at the end.

## Risks / open questions

- **`SyntaxNode` wrapping (C)** changes the printed shape every downstream projection
  sees; the reference grammar for `children[1]` spans is well-trodden (JSON/collection
  projections), but the text-navigation sweep is the gate.
- **`JsonInsertion` shape change (F)** — `value` goes `Any → String` buffer and the
  projection changes; `jsonparse`, the conversation composer, and the JSON authoring
  tests all touch `JsonInsertion()`. The zero-arg constructor keeps working
  (`value = ""` default), but sweep `test_json()` + `test_json_to_syntax()`.
- **Alias vs ambiguity**: `"julia"` is an exact alias (commits `JuliaInsertion`) while
  also a prefix of other names, so it displays as ambiguous-green with no continuation
  yet commits on Enter. Accepted trade-off to preserve today's behaviour; revisit if
  it confuses.
- **Red-state cost in `JuliaInsertion`** — the parseability probe runs per keystroke;
  `juliaparse` on short buffers is cheap, but the colour cell should memoize on the
  buffer value if it shows up in profiles.
- **Ambiguous rendering**: per spec no continuation is shown on ambiguity, so LCP
  partial completion is Tab-only and invisible until pressed; rendering the LCP pale
  even when ambiguous is a flagged possible follow-up, not in scope.
