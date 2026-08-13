# Symbolic requirement IDs

Replace the sequential numbers in
[requirements.md](../../documentation/requirements.md) and
[architecture-requirements.md](../../documentation/architecture-requirements.md)
with **stable symbolic IDs** — `PAR-PURE-THUNK` instead of `AR-1`, `PR-NO-INVALID-STATES`
instead of product requirement `1` — and rewrite every citation across the repo.

## Why

The numbering has already stopped being a sequence. The requirement numbers in
`architecture-requirements.md`, in document order, run:

```
1 … 41, 69, 42 … 50, 72, 73, 51 … 68, 70, 71
```

New requirements get appended the next free number and are then inserted where they
topically belong. That is the standard workaround for renumbering pain, and it leaves
the worst of both worlds: the numbers no longer renumber *and* they no longer tell you
where anything is. The IDs are already opaque; this plan makes them *good* opaque IDs.

Four concrete wins, in the order they matter here:

1. **Citations become self-describing.** `AR-45` means nothing in a commit message, a
   review comment, or a layering-guard error string. `PAR-PER-EDITOR-STATE` means
   something without opening an 857-line file. This matters more here than in most
   repos because [CLAUDE.md](../../CLAUDE.md) makes an AI audit every kernel file
   against this document *and report the result* — a finding that names the rule is
   legible on its own and survives context truncation.
2. **Guard messages get better for free.** `CheckLayering.jl` cites AR-73 / AR-48 /
   AR-72 in the failures it prints. `PAR-QUALIFIED-EXTENSION` in a failure message is a
   diagnosis; `AR-73` is a lookup task.
3. **Reorganizing the documents becomes free.** Today, moving a requirement between
   sections either breaks a citation or deepens the number scramble.
4. **The prefix disambiguates.** [chase-animation.md:68](../pending/chase-animation.md)
   cites bare "requirement 2" and "requirement 3" with no prefix — impossible to tell
   whether it means a product or an architectural requirement. `R-` / `AR-` fixes that
   permanently. *(Implementation note: on inspection those two turned out to cite
   neither document — see "What changed during implementation" below.)*

**The cost, stated honestly:** a name can rot when a requirement's prose drifts while
its name stays put. A number can never be wrong because it never says anything. The
mitigation is the naming rule below (name the *rule*, not the topic) plus the
never-reuse rule — not perfection.

## Decisions

### Format

`PAR-SCREAMING-KEBAB` for architectural requirements, `PR-SCREAMING-KEBAB` for product
requirements. Uppercase makes a citation unmistakable in running prose and in a Julia
comment; kebab keeps it greppable as one token.

### Rendering: a heading holding **only** the ID

Promote each requirement from an ordered-list item to a heading whose text is the ID and
nothing else, keeping the bold lead sentence exactly where it reads today — as the first
words of the body:

```markdown
### PAR-PURE-THUNK

**Every reactive computation must be a pure function of the cells it reads.** A
`Cell(() -> …)` thunk (and the parts of `print_document` that build them) must have
no side effects and must depend only on the cells it reads — no clocks, RNG, or
external mutable state. …
```

**Decided during implementation: the ID is the whole heading.** The first draft of this
plan put the rule's title in the heading too (`### PAR-PURE-THUNK — every reactive
computation is …`). That is wrong, and for the very reason this plan exists: a GitHub
anchor is derived from the *entire* heading text, so the anchor would have been
`#ar-pure-thunk--every-reactive-computation-is-a-pure-function-…` — long, ugly, and
**changing every time the title is reworded**. That reintroduces exactly the citation
fragility the numbers had. With the ID alone in the heading, the anchor is `#par-pure-thunk`
and is stable under any prose edit.

The payoff: a citation can deep-link to the exact requirement —
`[PAR-PURE-THUNK](../../documentation/architecture-requirements.md#par-pure-thunk)` — which
list items cannot do today (every existing link lands at the top of the file and makes
the reader hunt). It also keeps the body text byte-identical to what was there before.

Both documents also get an **index table** at the top (ID → one-line gloss), so an
auditor — human or AI — can pick the right ID without reading the whole file. The table is
*generated from the documents themselves*, each gloss being that requirement's own bold
lead sentence, so an index row cannot drift from the rule it names.

Heading level: `###` in `architecture-requirements.md` (whose sections are `##`), and
`####` in `requirements.md`, whose group headings (Correctness, Editing, …) already
occupy `###`.

### Rules to write into both preambles

- **A name is permanent and is never reused.** Retiring a requirement retires its name;
  a deleted `PAR-FOO` is never reassigned to a different rule. (Same discipline a number
  needs — now the stakes are visible.)
- **The name names the rule, not the section**, so it survives regrouping:
  `PAR-ACYCLIC-CELLS`, never `PAR-REACTIVITY-3`.
- **Adding a requirement means appending a heading and one index row.** Nothing else
  moves. That is the entire point.

## Blocker — a sealed file cites AR-45

[`package/kernel/main/cell/Clock.jl:25`](../../package/kernel/main/cell/Clock.jl#L25) is
**🔒 sealed** and contains `a principled AR-45 carve-out`. Renaming AR-45 to
`PAR-PER-EDITOR-STATE` requires a one-token edit to that line.

Per [CLAUDE.md](../../CLAUDE.md) this needs **explicit permission for that specific
file** before the migration touches it. No other sealed file cites a requirement ID
(checked: `PerformanceCounter.jl`, `AbstractCell.jl`, `ReactiveCell.jl`, `MutableCell.jl`,
`ImmutableCell.jl`, `document/Forward.jl`, `reference/ReferenceLayer.jl` — all clean).

If permission is withheld, the fallback is to leave `Clock.jl` citing `AR-45` and keep a
retired-number → name table in the requirements preamble. That is strictly worse; ask
first.

## Proposed names — architectural requirements

Sorted by current number. Section order is unchanged by this plan; only the IDs change.

### Reactivity — the cell engine

| Now | Name | Rule |
| --- | --- | --- |
| 1 | `PAR-PURE-THUNK` | Every reactive computation is a pure function of the cells it reads |
| 2 | `PAR-NO-WRITE-IN-THUNK` | A thunk never writes another cell or mutates shared document state |
| 3 | `PAR-ACYCLIC-CELLS` | The cell dependency graph stays acyclic |
| 4 | `PAR-MONOTONE-INVALIDATION` | Never hand-set `valid`; never partially invalidate |
| 5 | `PAR-WRITE-DRIVEN-PROPAGATION` | Propagation is write-driven, not value-driven |
| 6 | `PAR-NO-PROJECTION-GLOBALS` | No global mutable state in projections or the machinery they call |
| 7 | `PAR-DERIVED-CELLS` | Derive state through the engine; never read a cell before its wiring is complete |
| 8 | `PAR-FINEST-GRANULARITY` | Choose the reactive container that preserves the finest granularity |

### Documents and domains

| Now | Name | Rule |
| --- | --- | --- |
| 9 | `PAR-FIELDS-ARE-CELLS` | Every document field is a `Cell`, accessed transparently |
| 10 | `PAR-FIELD-NAMES-ARE-API` | A document's struct field names are its public reference vocabulary |
| 11 | `PAR-WIDE-FIELD-TYPES` | A field's declared type admits every value the field can hold |
| 12 | `PAR-NO-NESTED-CELL` | A macro-wrapped field never holds a `Cell` or a `Function` as its value |
| 13 | `PAR-DOCUMENT-IDENTITY` | Two documents with equal fields are not assumed `==` |
| 14 | `PAR-DOMAINS-INDEPENDENT` | Domains are independent; a document owns no cross-domain edge |
| 15 | `PAR-DOMAIN-OWNS-EDITS` | Every domain defines its own structural operations and insertion type |
| 16 | `PAR-WIDGETS-ARE-PRESENTATION` | The edited document stays in its semantic domain; widgets are presentation only |
| 17 | `PAR-SEARCH-DONT-WALK` | Prefer `search_references` / `search_documents` over hand-walking the tree |

### Projections

| Now | Name | Rule |
| --- | --- | --- |
| 18 | `PAR-FOUR-FUNCTIONS` | The four functions are the entire projection interface |
| 19 | `PAR-RECURSION-CONTRACT` | All recursion flows through those four functions and only those four |
| 20 | `PAR-DELEGATE-ONE-LEVEL` | Recurse one level, then delegate ("School A") |
| 21 | `PAR-RECURSE-VIA-PRINT-CHILD` | Recurse through `print_child`, never open-coded |
| 22 | `PAR-BIDIRECTIONAL-PROJECTION` | Every projection is bidirectional: a printer needs its inverse |
| 23 | `PAR-MAPPERS-ARE-INVERSES` | Forward and backward reference mappers are mutual inverses |
| 24 | `PAR-PREFER-REFERENCE-RETARGET` | Write `read_intent` only when re-targeting a reference is not enough |
| 25 | `PAR-GEOMETRY-FREE-IN-DOCUMENT` | Geometry-free gesture handling belongs to the document, not the projection |
| 26 | `PAR-DELEGATE-AND-LIFT` | A structural reader delegates a raw gesture to the selected child and lifts the result |
| 27 | `PAR-SHARED-CHILDREN-IOMAP` | A compound projection stores child IoMaps in one shared cell and returns a `ChildrenIoMap` |
| 28 | `PAR-CROSS-DOMAIN-LATE` | Cross domains as late as possible in the mappers |
| 29 | `PAR-HIGHER-ORDER-IS-DOMAIN-FREE` | Higher-order projections touch no domain |
| 30 | `PAR-USE-PROJECTION-MACRO` | Use `@projection` for projection structs with reactive fields |

### References and selection

| Now | Name | Rule |
| --- | --- | --- |
| 31 | `PAR-ONE-BASED-INDEXING` | All indexing is 1-based; elements are distinguished from boundaries |
| 32 | `PAR-REFERENCE-DSL` | Build and match reference paths with the DSL, not by hand |
| 33 | `PAR-EVERY-DOCUMENT-HAS-SELECTION` | Every concrete `Document` has a `selection::Cell` |
| 34 | `PAR-REPLACE-SELECTION` | Change selection with `replace_selection!`, not a bare `set_selection!` |
| 35 | `PAR-EMPTY-PATH-IS-SELECTION` | The empty path is a first-class whole-element selection, not an absence |
| 36 | `PAR-FOLDED-CHECKPOINTS` | Folded node-type checkpoints are canonical; produce and consume them, don't fabricate them |
| 37 | `PAR-REACTIVE-OUTPUT-SELECTION` | Wire the output selection reactively; focus is the selection |

### Operations

| Now | Name | Rule |
| --- | --- | --- |
| 38 | `PAR-ONE-WAY-TO-EDIT` | `evaluate_operation(editor, op)` is the one way to change the document |
| 39 | `PAR-PREFER-REPLACE-VALUE` | Prefer `ReplaceReferencedValueOperation` before writing a new operation type |
| 40 | `PAR-REGISTER-NEW-OPERATION` | A reference-carrying operation is registered in both `read_intent` and `reroot_operation` |
| 41 | `PAR-MUTATE-OR-NULL-IOMAP` | Mutate the cells already wired into the projection graph — or null `editor.iomap` |
| 69 | `PAR-INVERTIBLE-OPERATIONS` | Design every operation to be invertible; keep its inverse well-defined |

### Editor, devices, and backends

| Now | Name | Rule |
| --- | --- | --- |
| 42 | `PAR-BACKEND-SEAM` | Keep backends behind the `Backend`/`Device` seam; the same editor runs unchanged across them |
| 43 | `PAR-OPT-IN-DEPENDENCY` | Add a backend/engine as an opt-in package behind a factory seam |
| 44 | `PAR-PROFILE-WITH-COUNTERS` | Profile edits with the per-frame performance counters |
| 45 | `PAR-PER-EDITOR-STATE` | No process-global state; one process must run many editors at once |

### Package, layer, slice, and module structure

| Now | Name | Rule |
| --- | --- | --- |
| 46 | `PAR-PACKAGE-CHAIN` | Respect the package chain and the four-level division |
| 47 | `PAR-LOWEST-PACKAGE` | Code lives in the lowest package of its DAG whose API it hard-references |
| 48 | `PAR-MODULE-BOUNDARY-IS-API` | Imports name only exported symbols |
| 49 | `PAR-FRAMEWORKS-SINK` | Frameworks sink below their users via the seam pattern; only per-domain methods stay above |
| 50 | `PAR-PROJECTION-PLACEMENT` | Honor the projection placement invariant |
| 72 | `PAR-INTERFACE-DECLARES-ONLY` | An interface file declares; it never implements |
| 73 | `PAR-QUALIFIED-EXTENSION` | Name a module with bare `using ..Xxx`; extend its generics by qualification |
| 51 | `PAR-PARALLEL-TRIADS` | Keep the main/test/example triads parallel and minimal-environment runnable |

### Testing and verification

| Now | Name | Rule |
| --- | --- | --- |
| 52 | `PAR-SMALLEST-TEST` | Run the smallest test that covers the change; never default to `test_all()` |
| 53 | `PAR-MARK-BROKEN-TESTS` | Every currently-failing assertion is `@test_broken` with a `# @broken:` reason |
| 54 | `PAR-NEW-CODE-SHIPS-TESTS` | New code ships with tests, in the lowest test package that can express them |
| 55 | `PAR-NO-INTROSPECTION-METHOD` | The recursion contract stays externally validated; add no per-projection introspection |
| 56 | `PAR-DRIVE-THE-BEHAVIOUR` | Verify a change by driving the behaviour, not only by reading code |

### Documentation, vocabulary, and process

| Now | Name | Rule |
| --- | --- | --- |
| 57 | `PAR-DIVISION-VOCABULARY` | Use package / layer / slice / module exactly, and no synonyms |
| 58 | `PAR-NEVER-GUESS-NAMES` | Do not guess names or signatures — search for them |
| 59 | `PAR-GREEN-LAYERING-GUARDS` | Keep the layering guards green and let them enforce the structure |
| 60 | `PAR-UPDATE-THE-GUIDE` | Update the guide documenting behaviour you changed; teach concepts before mechanisms |
| 61 | `PAR-HONEST-DOCS` | Keep documentation honest; flag aspirational designs as such |
| 62 | `PAR-FOCUSED-DIFFS` | Keep diffs focused — no unrelated reformatting |
| 63 | `PAR-STABLE-FOUNDATIONS` | Respect the stable foundations and the roadmap ordering |
| 64 | `PAR-AI-SAME-GUARANTEES` | AI edits carry the same guarantees as human edits |
| 65 | `PAR-NAMING-LAW` | Names must be guessable in both directions |
| 66 | `PAR-MODULE-DOCSTRING` | Every source file opens with a module docstring stating its contract |
| 67 | `PAR-PERSISTENCE-BY-VALUE` | Persistence crosses cell boundaries by value and never enters the reactive graph |
| 68 | `PAR-NO-TEST-DOUBLES-IN-MAIN` | No test doubles live in `main` packages |
| 70 | `PAR-NO-CONSUMER-DOCS` | A module's documentation describes its own contract, never its consumers |
| 71 | `PAR-TIGHT-COMMENTS` | A comment carries only what the code cannot |

## Proposed names — product requirements

| Now | Name | Rule |
| --- | --- | --- |
| 1 | `PR-NO-INVALID-STATES` | The document never reaches a malformed state |
| 2 | `PR-MEANINGFUL-POSITIONS` | Every position the cursor can occupy is meaningful |
| 3 | `PR-DISPLAY-IS-TRUTH` | What is shown always reflects the content |
| 4 | `PR-EDIT-WHAT-IS-SHOWN` | Whatever is displayed can be edited directly |
| 5 | `PR-NATURAL-GRANULARITY` | Editing at whatever granularity the content has |
| 6 | `PR-CONTEXT-APPROPRIATE-EDITS` | Only meaningful edits are offered at any position |
| 7 | `PR-UNDO-REDO` | Reversible editing |
| 8 | `PR-REVISITABLE-HISTORY` | A history that can be revisited |
| 9 | `PR-INTERMEDIATE-STATES` | Every intermediate state is representable |
| 10 | `PR-REACH-ANY-PART` | The selection can reach any part of the content |
| 11 | `PR-STRUCTURAL-AND-LINEAR-NAVIGATION` | Both structural and linear navigation |
| 12 | `PR-SEARCH-AND-JUMP` | Search the content and jump to a match |
| 13 | `PR-MANY-VIEWS-OF-ONE-DOCUMENT` | More than one way to see the same data |
| 14 | `PR-SORT-AND-FILTER` | Sort and filter any collection without losing editing |
| 15 | `PR-FOCUS-AND-REORGANIZE` | Narrow and reorganize the view |
| 16 | `PR-COMBINE-CONTENT-KINDS` | Different kinds of content combine |
| 17 | `PR-ARBITRARY-NESTING` | Any kind of content nests in any other, arbitrarily |
| 18 | `PR-ANY-PART-IS-A-DOCUMENT` | Any fragment can be a document on its own |
| 19 | `PR-KEYBOARD-AND-POINTER` | Both keyboard and pointer work |
| 20 | `PR-MULTIPLE-ROUTES` | Multiple routes to the same action |
| 21 | `PR-DISCOVERABLE-ACTIONS` | Available actions are discoverable |
| 22 | `PR-CLIPBOARD` | Copy, cut, and paste content in and out |
| 23 | `PR-ADJUST-SCALE` | The scale of what is shown can be changed |
| 24 | `PR-IMMEDIATE-FEEDBACK` | Immediate, visible feedback for every action |
| 25 | `PR-INFORMATION-ON-DEMAND` | Supplementary information on demand |
| 26 | `PR-MULTIPLE-VIEWS-AT-ONCE` | Several views open at once |
| 27 | `PR-RESPONSIVE-AT-ANY-SIZE` | Editing stays responsive at any content size |
| 28 | `PR-UNBOUNDED-CONTENT` | Unbounded content can be presented and edited |
| 29 | `PR-SAME-EDITOR-EVERYWHERE` | The same editor runs in different environments |
| 30 | `PR-MANY-EDITORS-ONE-PROCESS` | One process runs many editors (the external face of `PAR-PER-EDITOR-STATE`) |
| 31 | `PR-SAVE-AND-INTERCHANGE` | Save, reload, and interchange work |
| 32 | `PR-RENDER-HEADLESS` | Render what is seen without a display |
| 33 | `PR-AI-SAME-GUARANTEES` | AI edits with the same guarantees (the external face of `PAR-AI-SAME-GUARANTEES`) |
| 34 | `PR-EDIT-BY-REQUEST` | Editing by natural-language request |
| 35 | `PR-CLEAN-CHECKOUT` | Runs from a clean checkout |
| 36 | `PR-ONE-STEP-EXAMPLE` | Any example launches in one step |
| 37 | `PR-DEVELOP-HEADLESS` | A contributor can work without a display |
| 38 | `PR-CHEAP-NEW-DOMAIN` | New kinds of content are cheap to add |
| 39 | `PR-COMPOSABLE-PROJECTIONS` | New presentations and interactions compose |
| 40 | `PR-VERIFY-IN-THE-SMALL` | Change can be verified in the small |
| 41 | `PR-SEPARABLE-OPTIONALS` | Optional capabilities are separable |
| 42 | `PR-SHIPPABLE-APPLICATION` | Can be delivered as an application |
| 43 | `PR-DOCUMENTED-PATH-IN` | Documented with a clear path in |
| 44 | `PR-PREDICTABLE-CONVENTIONS` | Predictable by convention |

## Migration

Naming is the reviewable part; the rest is mechanical. Steps 3–5 are a good fit for a
Sonnet subagent once the tables above are approved, with the rename driven from this
file so no name is invented on the fly.

**Done.** Implemented on branch `worktree-symbolic-requirement-ids` in four commits:
the two documents, the repo-wide citations, the comment reflow, and the finishing
pass. All 117 IDs are live; 191 numeric citations were rewritten across 31 files.

- [x] **1. Approve the names.** Review the two tables. Names are permanent once shipped,
      so this is the step that deserves the time. Anything renamed later costs a second
      sweep.
- [x] **2. Get permission for the sealed file.** `Clock.jl:25` (see *Blocker* above).
      Do not start step 4 without it.
- [x] **3. Rewrite `architecture-requirements.md`.** Convert the 73 list items to `###`
      headings with IDs, add the index table, and rewrite the preamble (lines 19–22
      currently say *"is numbered for reference (cite them as PAR-N …)"*). Also rewrite
      the **11 intra-document citations** (e.g. AR-69's body cites AR-38).
- [x] **4. Rewrite `requirements.md`.** Same treatment for the 44 product requirements.
- [x] **5. Rewrite every citation repo-wide.** Full inventory, verified by grep
      (excluding `package/executable/build/` artifacts, which contain unrelated
      coincidental `AR-\d` matches in vendored `.hwdb` / `.h` files):

      | File | Citations |
      | --- | --- |
      | `package/kernel/test/layering/CheckLayering.jl` | 37 |
      | `plan/done/document-layer-cleanup.md` | 29 |
      | `plan/done/device-layer-restructure.md` | 21 |
      | `plan/done/qualified-extension.md` | 18 |
      | `plan/done/per-editor-animation-clock.md` | 11 |
      | `plan/done/kernel-agent-stack.md` | 8 |
      | `plan/done/interface-file-purity.md` | 8 |
      | `plan/tentative/from-scratch-structure.md` | 7 |
      | `package/projectured/test/ExportCollisionTest.jl` | 6 |
      | `plan/done/document-interface-layering.md` | 4 |
      | `package/kernel/main/tool/Documentation.jl` | 3 |
      | `package/kernel/doc/agent.md` | 3 |
      | `plan/pending/text-domain-kit.md` | 2 |
      | `plan/done/reference-step-cleanup.md` | 2 |
      | `package/kernel/test/ProjecturedKernelTest.jl` | 2 |
      | `package/kernel/main/binding/GestureBinding.jl` | 2 |
      | `package/kernel/doc/cell.md` | 2 |
      | `package/kernel/main/cell/Clock.jl` 🔒 | 1 |
      | `package/kernel/main/{editor/Editor.jl, document/DocumentWalk.jl, llm/LlmModule.jl, tool/Tool.jl, tool/ToolModule.jl, tool/DefaultTools.jl}` | 1 each |
      | `package/{sdl,web}/main/Projectured{Sdl,Web}.jl` | 1 each |
      | `package/{visual,projectured}/test/*.jl`, `package/domain/test/projection/ConversationEditorTest.jl` | 1 each |
      | `package/kernel/doc/{editor.md, devices-and-backends.md}`, `documentation/concepts.md` | 1 each |

      `plan/done/` is included: a done plan citing an `AR-45` that no longer exists is a
      dangling reference. Renaming an ID there is not a history rewrite.
- [x] **6. Fix the prose that describes the scheme**, not just the IDs:
      [documentation/README.md](../../documentation/README.md) (lines 50, 105 — "the
      numbered … requirements", "Numbered internal development requirements (PAR-N)") and
      [documentation/architecture-rules.md](../../documentation/architecture-rules.md)
      (line 19 — "the numbered PAR-N"). `CLAUDE.md` references the document but no ID, so
      it needs no change.
- [x] **7. Resolve the two bare citations.** `plan/pending/chase-animation.md:68` cites
      "requirement 2 / requirement 3" and `plan/done/reference-layer-file-split.md` cites
      "requirement 66 / 48". Read the context, decide whether each means `R-` or `AR-`,
      and write the prefixed name.
- [x] **8. Upgrade the citation links.** Now that requirements have anchors, existing
      links that point at the whole file (`package/kernel/doc/editor.md:279`,
      `package/kernel/doc/agent.md:40`) should point at the requirement:
      `…/architecture-requirements.md#par-per-editor-state`.

## Verification

- [x] `grep -rn 'AR-[0-9]' documentation/ package/*/main package/*/test package/*/doc plan/ *.md` — zero hits
      outside `package/executable/build/`.
- [x] Every proposed ID appears at least once in its requirements document (no name
      defined but never rendered), and every cited ID resolves to a defined one (no
      dangling citation). A short script over the two index tables is enough.
- [x] The renamed strings in `CheckLayering.jl`, `ExportCollisionTest.jl`, and
      `ProjecturedTest.jl` are inside comments and failure *messages*, not logic — but
      run `test_kernel()` and the export-collision test anyway to confirm nothing that
      pattern-matched a message broke.
- [x] Anchors resolve: spot-check that `#par-per-editor-state` and `#par-qualified-extension`
      land on the right heading in a rendered view.

## What changed during implementation

Five things the plan did not foresee. They are recorded here because each one is a
constraint the next person would otherwise re-discover the hard way.

1. **The ID must be the *entire* heading** — see *Rendering* above. The plan's original
   `### PAR-PURE-THUNK — every reactive computation is …` form derives an anchor from the
   whole heading text, so the anchor would change whenever the title was reworded. That
   is the very fragility this plan set out to remove. Fixed before any file was written.

2. **`chase-animation.md` was not citing these documents at all.** The plan listed its
   bare "requirement 2 / requirement 3" as ambiguous `R-`/`AR-` citations and proposed
   prefixing them. Reading the context showed they point at *that plan's own* unnumbered
   bullet list of hard requirements — "(a) the flip site (rejected — requirement 2)"
   means the bullet *Independent of how the input changes*, which forbids arming code at
   the flip site. Prefixing them would have manufactured a citation that was never there.
   They are now named in place. The four bare citations in
   `plan/done/reference-layer-file-split.md` *were* architectural requirements (66 → the
   module-docstring rule, 46 → the package-chain rule, 48 → the module-boundary rule),
   verified against the rule text each sentence describes, and renamed.

3. **Longer IDs overrun the source's wrap width.** Substituting `PAR-QUALIFIED-EXTENSION`
   for `AR-73` pushed comment, docstring, and `*`-concatenated error-message lines out to
   90–152 columns, mostly in `CheckLayering.jl`. This needed a whole reflow pass (its own
   commit) that moves words between lines without changing one of them. Budget for it:
   it is the standing tax of long names, and it will recur whenever a rule is cited in
   source.

4. **The plan file itself must be excluded from the rename.** It quotes the old IDs
   deliberately ("`AR-45` means nothing in a commit message"), and the sweep happily
   rewrote those quotes into nonsense. Excluded and restored.

5. **One sentence in the requirements document became meaningless and was deleted**:
   PAR-INVERTIBLE-OPERATIONS ended with *"This requirement lives with the Operations
   section (AR-38–41); it is numbered 69 to keep the existing AR numbers stable."* Its
   only job was to apologise for the number scramble. With names there is nothing to
   apologise for. This is the sole prose deletion in either document — everything else is
   word-for-word identical, mechanically verified.

**Not done, deliberately:** `Clock.jl` stays 🔒 sealed. Permission was granted for the
single AR-45 citation in its docstring and used for exactly that; the seal still holds
and its entry in [CLAUDE.md](../../CLAUDE.md) is unchanged.

## Verification performed

- Both documents are **word-for-word identical** to their originals apart from the
  preamble rewrite, the citation renames, and the one deleted sentence above — checked by
  diffing the word sequence, not by eye.
- Every re-flowed source file's word sequence is unchanged; all 294 string literals in
  `CheckLayering.jl` are character-identical once whitespace runs are collapsed (three
  concatenated error messages were re-split across lines).
- `test_kernel_layering()` 10/10 and `test_export_collisions()` passing — these are the
  tests whose own source carries the renamed IDs in its failure messages.
- `ProjecturedKernel`, `ProjecturedVisual`, `ProjecturedDomain`, `ProjecturedSdl`, and
  `ProjecturedWeb` all load.
- Zero numeric `PAR-N` citations remain outside `package/executable/build/` (vendored
  artifacts with coincidental matches). Zero dangling ID citations: every `AR-…`/`R-…`
  cited anywhere resolves to a defined heading, and all 117 defined IDs are rendered.
- Every `architecture-requirements.md#…` anchor link resolves to a real heading.
