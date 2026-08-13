# One requirement-id prefix pair per repository

Status: pending. Decided 2026-08-13.

## 1. The decision

A requirement id says which repository owns it. Two prefixes per repository:
one for the product requirements, one for the architectural ones.

| repository | product | architecture |
| --- | --- | --- |
| **projectured-julia** | `R-` → **`PR-`** | `AR-` → **`PAR-`** |
| omnetpp-julia | `OR-` | `OAR-` |
| inet-julia | `IR-` | `IAR-` |

The two sibling repositories are already correct. Only this one renames, and
the sibling citations that name it follow.

## 2. Why

The siblings had already diverged on what to call an upstream rule.
omnetpp-julia's `documentation/architecture-requirements.md` cites upstream as
`PAR-…` and links to `#par-…` anchors, which do not exist — **all seven of its
upstream links are broken today**. inet-julia cites the same rules as `AR-…`
with anchors that resolve. So a reader of the two documents sees one rule under
two names, and one of the two spellings is dead.

Renaming here fixes both at once. omnetpp-julia's links start working with **no
edit to that document at all**, because the anchors it already points at come
into existence. inet-julia's four link definitions retarget.

A prefix that names the repository also answers, at the point of citation,
the question a reader of a four-repository stack actually has: whose rule is
this, and which document do I open?

## 3. Scope

Measured at `main`, excluding `.git`:

| repository | `R-` → `PR-` | `AR-` → `PAR-` | total |
| --- | ---: | ---: | ---: |
| projectured-julia `documentation/` | 96 | 193 | 289 |
| projectured-julia `package/` | 120 | 138 | 258 |
| projectured-julia `plan/` | 46 | 285 | 331 |
| omnetpp-julia | 0 | 28 | 28 |
| inet-julia | 3 | 6 | 9 |
| **total** | **265** | **650** | **915** |

77 `### AR-…` headings and their index rows; ~96 `#ar-…` anchors and ~30
`#r-…` anchors in links.

**Decided with the scheme:** `plan/` is renamed too, including `plan/done/`.
A done plan that cites a dead id is worse than one whose vocabulary was
updated. Sealed files may be opened for this rename — one is affected,
`package/kernel/main/clock/Clock.jl:26`, which cites `AR-PER-EDITOR-STATE`.

## 4. Order

The order matters: a citation must never point at an anchor that does not
exist yet.

- [ ] **P1 — Dry run.** List every distinct token that `\bR-[A-Z]` and
  `\bAR-[A-Z]` match, per repository, and read the list before any edit.
  `\b` already excludes `OR-`, `IR-`, `OAR-` and `IAR-`, because the boundary
  falls before the first letter — confirm that on the real list rather than on
  the argument.
- [ ] **P2 — Rename in projectured-julia.** Headings, index rows, self-cites,
  link definitions, `#ar-…` → `#par-…`, `#r-…` → `#pr-…`, across
  `documentation/`, `package/`, `plan/`. One commit.
- [ ] **P3 — Check the anchors resolve.** Every `[PR-…]`/`[PAR-…]` shortcut
  reference has a definition; every definition's anchor matches a heading;
  no `\bAR-`/`\bR-` survives outside a quotation.
- [ ] **P4 — Retarget omnetpp-julia** (28 sites: 20 `package/`, 8 `plan/`).
  Its `architecture-requirements.md` needs no edit — its `#par-…` anchors
  become correct when P2 lands.
- [ ] **P5 — Retarget inet-julia** (9 sites, of which 4 are the link
  definitions in its `documentation/architecture-requirements.md`).
- [ ] **P6 — State the scheme** in each repository's requirements document
  header: the prefix names the repository, and here is the table.

## 5. Risks

- **A rename that rewrites a string it should not.** The known failure mode in
  this codebase is a word-boundary rename that also edits file-path strings.
  `R-` and `AR-` do not appear in a path here, but P1 exists to see the token
  list rather than to assume it.
- **A half-landed rename breaks every link.** P2 through P5 are one campaign;
  between P2 and P4 the sibling citations name a prefix that no longer exists.
  Land them together, or land P2 last if the siblings are edited first.
- **`plan/done/` is history.** Renaming there changes what a record says was
  written at the time. Accepted deliberately: a dead id in a record helps
  nobody, and the rename is mechanical, not semantic.
