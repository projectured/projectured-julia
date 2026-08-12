# Removing FileReferenceStep and IdentityReferenceStep — they are not steps

> **Status (2026-08-12): DONE.** The removal commit (`44483f9c`) is on `main`;
> `FileReferenceStep.jl`, `IdentityReferenceStep.jl`, and `IdentityDocument.jl` are
> confirmed absent from the current tree. Nothing further to do.

Status: **done** (2026-08-04), landed on `main` (was branch `tutorial-embeds`).
Phase B removed their last consumer (the `FileProject` marker codec), which was
the gate. Follow-up of `inet-julia/plan/pending/queuing-tutorial-migration.md` §9.

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
  `package/projectured/test/serializer/FileProjectS4Test.jl` / `JsonFileTest.jl` lose their
  step-specific assertions (largely reworked by Phase B already).
- **Docs** — sweep live guides for mentions (`package/kernel/doc/reference.md`). Done
  plans (`plan/done/document-file-storage.md`) are historical records and stay verbatim.
- **Downstream** — omnetpp-julia's presentation loader touches stubs only through
  `resolve!`, and inet-julia not at all (verify with a final grep across all three
  repositories before deleting).

## 3. Steps

- [x] 0: grep across the three repositories — the only sites were the three kernel
      files, their includes/exports and the kernel test. Nothing in omnetpp-julia or
      inet-julia; no live guide mentioned them (Phase B had already removed the
      FileProject/JsonFile assertions)
- [x] 1: deleted the three kernel files; removed their includes and their five
      exported names from `ReferenceModule.jl` (**sealed — permission given
      explicitly by the user in the implementing conversation, 2026-08-04**)
- [x] 2: deleted `IdentityAndFileStepTest.jl` and unwired it from
      `ProjecturedKernelTest`
- [x] 3: docs sweep — nothing to change
- [x] 4: suites unchanged: base 387/387, visual 49287, domain 140012 pass / 0 fail;
      kernel keeps its 5 pre-existing "Rule C" failures (a kernel-only-env artefact,
      not this change); omnetpp-julia presentation 232/232, simulator 5061/5061;
      inet-julia queuing 202/202

## Implementation log

**Done 2026-08-04**, on branch `tutorial-embeds` (worktree
`projectured-julia-tutorial`), in one commit.

The survey came out exactly as predicted: three kernel files, their include and
export lines, and one kernel test. Phase B had already taken the FileProject and
JsonFile assertions with it, so nothing remained there, and no live guide named
either step or the `.file(…)` / `.identity(…)` DSL forms they added.

Removing them takes those two `@reference` extension forms with them, which is
the point — the reference syntax is now closed over steps that a selection
genuinely carries.

Status: **done**. The branch has landed on `main`; this plan is ready to move to
`plan/done/`.
