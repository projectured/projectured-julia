# Removing FileReferenceStep and IdentityReferenceStep — they are not steps

Status: **pending** (2026-08-04). **Gated** on the queuing-tutorial migration's Phase B
(the marker language) landing in this repository — that phase removes their last consumer.
Follow-up of `inet-julia/plan/pending/queuing-tutorial-migration.md` §9.

## 1. Why

A reference step's contract is structural: given a parent document, descend **exactly one
level** — that is what selection propagation walks child by child, and what IO maps map
through projections. Judged against that contract, neither of these qualifies:

- **`FileReferenceStep`** never descends from anything. It is an entry-point locator into
  the project namespace: its `evaluate_reference_step` has *no default implementation*
  (it errors unless the `FileProject` driver overrides it), it only ever appears as a
  chain head, and no selection or iomap ever carries one. It is a function wearing a step
  costume — and with the marker language it *is* a function, `file("path")`.
- **`IdentityReferenceStep`** does take a parent, but evaluates by DFS **search over
  arbitrary depth** — it does not identify one child per level, so the selection walker
  has nothing to hold onto — and it requires `IdentityDocument` wrappers that no domain
  parser produces. Name-based fragment addressing is `definition(doc, "name")` in the
  marker vocabulary, reading the name a definition already carries.

Removing them keeps the reference syntax closed over the structural steps (field,
element/range, position, projection-introduced, plus type checkpoints, plus the
visual-layer geometry steps — which pass the test: a selection genuinely carries them).

## 2. What removal touches (surveyed 2026-08-04)

- **Kernel** — `reference/FileReferenceStep.jl`, `reference/IdentityReferenceStep.jl`,
  `reference/IdentityDocument.jl`: all three are *outside* the sealed inventory (they
  postdate it) and simply get deleted, each defining its own `@reference` extension form
  via the (sealed, untouched) extension seam in `ReferenceSyntax.jl`.
  **⚠ Their `include` lines live in `reference/ReferenceModule.jl:92-94`, which is
  sealed** — that one edit needs explicit permission in the implementing conversation,
  per repository policy. Exports of the three names from the same module go with it.
- **Base** — `serialization/FileProject.jl`: today `ReferenceStub.reference` is a
  `ConcreteReference` headed by a `FileReferenceStep`, and `marker_text`/
  `parse_marker_text` are the reference↔text codec. Tutorial Phase B replaces this with
  source-text stubs evaluated through the marker vocabulary; after it lands, nothing here
  constructs either step. This plan only deletes what Phase B left dead.
- **Tests** — `package/kernel/test/reference/IdentityAndFileStepTest.jl` (delete);
  `package/base/test/serialization/FileProjectTest.jl` and
  `package/domain/test/serializer/FileProjectS4Test.jl` / `JsonFileTest.jl` lose their
  step-specific assertions (largely reworked by Phase B already).
- **Docs** — sweep live guides for mentions (`package/kernel/doc/reference.md`). Done
  plans (`plan/done/document-file-storage.md`) are historical records and stay verbatim.
- **Downstream** — omnetpp-julia's presentation loader touches stubs only through
  `resolve!`, and inet-julia not at all (verify with a final grep across all three
  repositories before deleting).

## 3. Steps

- [ ] 0: after Phase B lands — grep projectured-julia, omnetpp-julia, inet-julia for
      `FileReferenceStep`/`IdentityReferenceStep`/`IdentityDocument`; confirm the only
      remaining sites are the three kernel files, their includes/exports, tests and docs
- [ ] 1: delete the three kernel files; remove their includes/exports from
      `ReferenceModule.jl` (**sealed — ask permission first**)
- [ ] 2: delete `IdentityAndFileStepTest.jl`; strip residual step assertions from the
      FileProject/JsonFile tests
- [ ] 3: docs sweep (`package/kernel/doc/reference.md` and any other live guide)
- [ ] 4: full suites green in all three repositories

## Implementation log

(append: permissions granted, deviations, final grep results)
