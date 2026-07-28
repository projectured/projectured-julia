# Base package — file/folder structure & domain→base moves

Planning note (not yet an implementation task). Answers three questions:

1. The target file/folder structure for `package/base`.
2. Which domain files should move down into `base`.
3. How `base` would be rearranged internally with no backward-compat concern.

The authorities used throughout: [architecture-rules.md](../../documentation/architecture-rules.md)
(placement), [architecture-requirements.md](../../documentation/architecture-requirements.md)
(`AR-LOWEST-PACKAGE`, `AR-FRAMEWORKS-SINK`, `AR-DOMAINS-INDEPENDENT`,
`AR-PROJECTION-PLACEMENT`), and [base/doc/architecture.md](../../package/base/doc/architecture.md).

Base's membership rule (base doc): *"the type is generic enough that every domain
reuses it, so it doesn't belong in any single slice."* A feature domain (its own
document types, one consumer) is **not** base even when its imports are clean —
`Json`, `Xml`, `FileSystem`, `Database` all import only kernel/base yet stay in
domain. The move test is **framework-every-domain-reuses**, not clean-imports.

---

## 1. Current base structure (baseline)

```
package/base/
  main/ProjecturedBase.jl            module root: kernel aliases + include order
  main/backend/DefaultBackend.jl     reflection-based default_backend preamble
  main/document/                     Layer 1
    Collection.jl  + collection/{CellVector,CellMatrix,CellTable,ListNode}.jl
    Primitive.jl   DocumentCore.jl   Dragging.jl
    Domain.jl      BoundedSync.jl    DocumentReflection.jl
  main/projection/                   Layer 2
    generic/{Identity,Reversing,Constant,Focusing}.jl
    higherorder/{Chaining,TypeDispatching,Recursive,Switching,
                 PredicateDispatching,ReferenceDispatching,Nesting,
                 WindowInputUnwrapping}.jl
    Sorting.jl Filtering.jl Searching.jl Copying.jl
    ReaderDefaults.jl DraggingProjection.jl
    HigherOrderCompound.jl GenericCompound.jl
  main/serialization/BinarySerialization.jl   Layer 3
  test/ …                            (no base/example — see architecture-rules)
  doc/{architecture,collection,bounded-sync}.md
```

Layers today: `document → projection → serialization` (guard-enforced).

Two structural smells:
- **document/ conflates nodes with machinery.** Collection/Primitive/DocumentCore/
  Dragging are document *nodes*; Domain (`@domain` macro + completion), BoundedSync
  (a `sync_document!` walk policy) and DocumentReflection (object→tree reflection)
  are *frameworks over* documents, not documents.
- **projection/ grouping is non-uniform.** `generic/` and `higherorder/` are
  kind-folders, but Sorting/Filtering/Searching/Copying/ReaderDefaults/
  DraggingProjection and the two `*Compound.jl` aggregators sit loose at the root,
  and the compounds are named by *kind* (`GenericCompound`) not feature.

---

## 2. What should move from `domain` → `base`

Import surface of every plausible candidate was audited. Result:

### Move now — clean framework, domain-neutral (mirrors Dragging exactly)

| File | → New home | Why |
|---|---|---|
| `versioning/Versioning.jl` | `base/main/document/Versioning.jl` | Domain-neutral overlay document (`VersionedObject`/`ObjectVersion`/`VersionProperties` + criteria). Imports only `Cell/Document/@document/CellVector/Reference`. Plan `object-versioning.md`: *"no domain depends on versioning; it sits above every domain as an optional wrapper."* |
| `versioning/VersioningToAny.jl` | `base/main/projection/VersioningToAny.jl` | Version-elimination projection. Imports **only** kernel + base + its own `VersioningModule` — **no visual**. Input `VersionedObject` (base), output generic ⇒ projection-placement home = base. |

This is the same node+eliminator split already precedented by
`Dragging.jl` (base/document) + `DraggingProjection.jl` (base/projection).
Note: the analogous **clipboard** pair lives in *visual*, not base, because
`OsClipboard`/display-collection couple it to visual — versioning has no such
coupling in eliminated mode, so it can sink one package lower.

### Move only after a seam refactor — earmarked for base but currently domain-coupled

`base/doc/architecture.md` already lists `NaturalFormat.jl` and `DocumentFile.jl`
as *"planned additions"* to `serialization/`. But **as written they hard-code
Json/Xml/Sql/Julia** (`_domain_to_syntax(::JsonDocument)`, `jsonparse`,
`JsonInsertion()` seeds, …). Moving them verbatim would make `base` import
`domain` — an illegal upward edge (`AR-FRAMEWORKS-SINK`, layering guard).

Prerequisite refactor (invert the dependency into the seam pattern):
- **base/serialization** keeps the *framework*: the extension→handler registry
  and the generics `export_document`/`import_document`/`save_document`/
  `load_document` + `document_file` entry point, as open generics.
- **each domain slice** registers its own format in a file it already has —
  `_natural_extension(::JsonDocument)`, its parser, its `JsonInsertion` seed —
  exactly as operation traversal / reader-defaults / insertion already do.

Only then do the two framework skeletons belong in `base/serialization/`.

### Do NOT move to base — these sink to *visual*, not base (they render)

| File(s) | Correct home | Why not base |
|---|---|---|
| `component/Component.jl` (+ future `ComponentToWidget`) | new `visual/component/` slice | A component is a widget-composition concept ("projects to a widget tree"); `component-document.md` itself places it between Widget and Workbench. Document imports are clean, but the feature renders ⇒ visual. |
| `gesturemap/{GestureMap,GestureMapToSyntax,GestureHelpDecorator}.jl` | `visual/` (a `gesturehelp/` slice) | Domain-neutral *help* feature, but `GestureMapToSyntax` → Syntax and `GestureHelpDecorator` → `ScreenDocument` window ops ⇒ visual. |

Splitting a one-document slice's doc (clean imports) from its only projection
(visual) across packages is wrong — the *slice* is a visual concept.

### Do NOT move — feature domains / domain-owned seams (stay in domain)

- `filesystem/`, `database/DatabaseInstance.jl`, `database/Database.jl` — concrete
  feature domains (own document types, not a framework every domain reuses).
- `database/DatabaseAdapters.jl` — zero-dependency, but it is the **domain-owned**
  `make_database_adapter` seam (architecture.md: factory seams owned by *kernel or
  domain*; `odbc → domain's sql surface`). A "database adapter" is a database-domain
  concept; sinking it to base would pull a domain concept into the neutral vocabulary.
- `insertion/InsertionToSyntax.jl`, `insertion/NaturalProjection.jl` — cross-domain
  aggregators that enumerate every domain; pinned to domain by their imports. (Their
  *generic* skeleton — the shared insertion leaf + `*Nothing` placeholder, the
  to-syntax dispatch table — could later sink to `visual/syntax` with domains
  registering delegates via the seam, but that is a separate, delicate refactor.)

---

## 3. Clean-slate rearrangement (no back-compat) — concept-folder DAG

**Decision (2026-07-28, revised):** base drops the `document -> projection ->
serialization` layer stack and is organized as an **acyclic DAG of concept
folders**, each cohesive and holding whatever kinds that concept needs (its
documents AND its projections AND its ops). This is "base sliced like `domain`."
The carve-out that started with dragging/versioning generalizes: *every* base
concept gets its own folder; a document and the projection that eliminates/reads
it live together, not split across a document layer and a projection layer.

Four findings settled this shape (see the numbered notes below):

1. **BoundedSync is NOT redundant with the kernel, and is NOT generic
   "framework".** The bounded-walk *mechanism* (`sync_document!(shadow, source,
   policy, depth)` + `unsynced_placeholder`/`should_descend_sync`/
   `sync_element_limit`) already lives in the **kernel**, `document/DocumentSync.jl`
   (sealed). Base `BoundedSync.jl` is the *concrete* half that can't live in the
   kernel (zero concrete documents): the `UnsyncedDocument` marker **document**
   (`@document`) + the `SyncPolicy`/`DepthPolicy` policies + `unsynced_marker`/
   `request_sync!`, implementing that seam. Its only users are
   `DocumentReflection.jl` (whose `ReflectedNode` uses `UnsyncedDocument` as its
   collapse marker) and visual's `ReflectionToWidget.jl`. So BoundedSync +
   DocumentReflection are one feature -> a `reflection/` folder (documents in base;
   the `ReflectionToWidget` projection stays in visual across the seam).
2. **`@domain` + its placeholder documents get a `domain/` folder** —
   `DocumentCore.jl` (`DocumentBase`/`DocumentNothing`/`DocumentInsertion`/
   `DocumentReference`) + `Domain.jl` (the `@domain` macro that generates a
   domain's root/Nothing/Insertion kit + Insert gesture + traits, and the
   reflection-based insertion completion). Tightly coupled: the macro's per-domain
   `*Nothing`/`*Insertion` mirror `DocumentNothing`/`DocumentInsertion`.
3. **Collection gets a `collection/` folder** holding its documents AND its
   collection-shaped projections: `CellVector`/`CellMatrix`/`CellTable`/`ListNode`
   + `Sorting` + `Filtering`. `Searching` and `Copying` do **not** go here: both
   *consume* any input (Searching is a pre-order walk over any document; Copying
   deep-copies any document via `ListNode`/`CellVector`/`Vector{Cell}`/`Any`
   methods), so they are generic `projection/` algebra.
4. **Natural format is its own concept, not serialization** — separate from
   `serialization/` (binary, exact/lossless Julia `Serialization`). Natural format
   is human-readable import/export (parse-text <-> print-via-ToSyntax->ToString).
   It and `DocumentFile` (the extension-dispatched entry point that bridges *both*
   serializers) merge into **one `fileformat/` folder** — the file entry point
   (`DocumentFile`) plus the format (`NaturalFormat`) in one standard compound noun.

### Target layout

```
package/base/main/
  ProjecturedBase.jl            reads as the concept-folder DAG (include order)
  backend/DefaultBackend.jl     default_backend preamble (unchanged)

  # ---- vocabulary (documents every slice/domain reuses) ----
  domain/         DocumentCore(Base/Nothing/Insertion/Reference) + Domain(@domain + completion)
  collection/     CellVector,CellMatrix,CellTable,ListNode  +  Sorting,Filtering
  primitive/      Primitive(Bool/Number/String/Insertion + Replace*RangeOperation) + ReaderDefaults

  # ---- domain-free projection algebra (no documents) ----
  projection/     generic/(Identity,Reversing,Constant,Focusing)
                  higherorder/(Chaining,TypeDispatching,Recursive,Switching,
                               PredicateDispatching,ReferenceDispatching,Nesting,
                               WindowInputUnwrapping)
                  compound/(ApplyAt,SortingAt)
                  Searching.jl, Copying.jl   (consume any input -> generic algebra)

  # ---- optional feature slices (document + projection together) ----
  dragging/       Dragging(DraggingState)                 + DraggingProjection
  versioning/     Versioning(VersionedObject/ObjectVersion/…) + VersioningToAny   <- from domain
  reflection/     BoundedSync(UnsyncedDocument + SyncPolicy/DepthPolicy) + DocumentReflection(ReflectedNode)
                  # projection ReflectionToWidget stays in visual, across the seam

  # ---- persistence ----
  serialization/  BinarySerialization                  (exact/lossless binary)
  fileformat/     NaturalFormat + DocumentFile         (human-readable file formats + the
                  extension-dispatched file entry point; framework skeleton, post §2)
```

Two pairings worth noting: `primitive/` co-locates `Primitive` with
`ReaderDefaults` because ReaderDefaults *is* the Primitive-op half of the default
`read_intent` (`ReplaceStringRangeOperation`/`ReplaceNumberRangeOperation`, both
owned by Primitive). `reflection/` co-locates the marker document, the policies,
and the reflector that consume each other.

### Direction and enforcement

- **Acyclic concept DAG.** `domain/` is the root (everyone uses `DocumentNothing`);
  `collection/`+`primitive/` are vocabulary; the `projection/` algebra builds on
  them; the feature slices (`dragging/`/`versioning/`/`reflection/`) build on the
  algebra + vocabulary; the persistence folders build on `domain/` (+ `naturalformat`
  on the per-domain to-syntax seams). No cycles; a lower concept never names a
  higher one.
- **Guard consequence:** base stops being an ordered `LAYERS` list and becomes an
  **acyclic slice DAG**, exactly the mode the shared `check_layering` already runs
  for `visual`/`domain`. `base/doc/architecture.md`'s "3 layers" section is
  rewritten to the concept-folder DAG.

### Settled naming choices

- `domain/` for finding #2 (the `@domain` macro + placeholder documents) — always
  read package-qualified (`package/base/main/domain/`), so the mild clash with the
  domain *package* is acceptable.
- `Searching` -> `projection/` algebra (consumes any input, not collection-shaped).
- Merged natural-format + file-entry folder named `fileformat/`.

All folder names are now settled; the target layout above is final.

---

## Implementation status

Branch `base-concept-folders` (worktree `projectured-julia-base-restructure`).

- [x] **Step 1 — in-base concept-folder reshuffle.** `git mv` of every base
  source file into `domain/ collection/ primitive/ projection/(+compound/)
  dragging/ reflection/ serialization/`; module names preserved. `Collection.jl`
  sub-includes flattened; `ProjecturedBase.jl` include list + docstring rewritten
  to the concept-folder DAG; `test_base_layering()` switched to slice-DAG mode
  (dropped the `layers=` kwarg). Deferred (module renames, out of scope here):
  `GenericCompound`/`HigherOrderCompound` keep their names inside `compound/`
  rather than becoming `ApplyAt`/`SortingAt`.
- [ ] **Step 2 — versioning move** `domain/versioning/` → base `versioning/`
  (document + `VersioningToAny`), with its tests. Cross-package; example stays in
  domain/example (base has no example package).
- [ ] **Step 3 — `fileformat/` seam refactor** (separate plan): invert
  `NaturalFormat`/`DocumentFile`'s hard-coded Json/Xml/Sql/Julia into the seam
  pattern, then move the framework skeleton to base `fileformat/`.
- [ ] Rewrite `base/doc/architecture.md`'s "3 layers" section to the DAG.

## Follow-ups this planning surfaced

- `object-versioning.md` and `component-document.md` (both `plan/pending/`) still
  place their code in `domain`; if the moves above are adopted, those plans need a
  home update (versioning → base, component → visual).
- The natural-format seam refactor is a prerequisite for its own base move and is
  worth its own plan.
