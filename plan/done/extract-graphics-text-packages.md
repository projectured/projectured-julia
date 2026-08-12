# Extract `ProjecturedGraphics` and `ProjecturedText` packages

> **Status (2026-08-12): DONE.** `package/graphics/main/Project.toml` names
> `ProjecturedGraphics` and `package/text/main/Project.toml` names
> `ProjecturedText`. The domain package split ([source-tree-reorganization.md](../done/source-tree-reorganization.md),
> now in `plan/done/`) created both, and went further than this plan
> proposed: the style vocabulary (`Color`/`Font`/`Geometry`/`StyleText`/
> `StyleStroke`/`Image`) landed in its own `package/style/`, not folded into
> Graphics; the PDF and Console backends became their own packages
> (`package/pdf/`, `package/console/`), not moved into Graphics/Text; and the
> "everything else" domain package (Syntax/JSON/XML/SQL/Widget/Graph/…) is
> not one `ProjecturedDomain` but about twenty separate packages, each
> depending on `ProjecturedText`/`ProjecturedGraphics` directly. One item is
> not done as specified: there is no dedicated `ProjecturedGraphicsTest` /
> `ProjecturedTextTest` package (`package/graphics/` and `package/text/` hold
> only `main/` and `doc/`, no `test/`); graphics/text code is exercised
> through the many per-domain test packages that depend on it instead.

## Goal

Split the two lowest visual layers out of `ProjecturedDomain` into their own packages so
they can be **built and tested in isolation** (each gets its own test package, below),
and so the dependency story is honest about the rendering stack. **No new external
dependencies** — Graphics/Text/Color/Font/Geometry and the Console/PDF backends are all
pure Julia (Console/PDF were already verified dependency-free).

## Layering (verified from `ProjecturedDomain.jl` include order + module imports)

```
kernel  (ProjecturedKernel)
  └─ ProjecturedGraphics    ← base visual + style vocabulary + Graphics canvas + PDF backend
       └─ ProjecturedText   ← Text document + Console backend + text projections (depends on Graphics)
            └─ ProjecturedDomain   ← everything else (Syntax/JSON/XML/SQL/Widget/Graph/… + their projections)
                 └─ Projectured (umbrella)
```

Evidence:
- `GraphicsModule` imports only kernel modules (`Reactive`/`Document`/`Collection`/
  `Reference`) + `FontModule` — it is foundational, no domain deps.
- `TextModule` imports kernel modules + `Font`/`Color`/`StyleText`/`Geometry` — and
  **not** `GraphicsModule`. So at the *document* level Text is independent of Graphics;
  the Text→Graphics coupling is only the `TextToGraphics` **projection**. This is why
  `Text` can sit in a package that *depends on* `ProjecturedGraphics`.
- Reverse-dep breadth in `domain/src`: `Text`(39), `Color`(34), `Font`(31),
  `StyleText`(17) are used pervasively; `Geometry`(2), `Image`(2), `Graphics`(7),
  `StyleStroke`(1) narrowly. Pervasive use is fine because the rest of `domain` will
  *depend on* these two new packages.

## `ProjecturedGraphics` *(→ kernel)*

The base visual/style layer + the dependency-free PDF backend + graphics projections.

- **Document modules:** `Graphics` (`GraphicsModule`), plus the shared visual vocabulary
  it and Text both need: `Geometry`, `Color`, `Font`, `StyleText`, `StyleStroke`, and
  `Image` (`ImageModule` — `Pdf` needs `ImageFile`). Putting the whole style/geometry
  vocabulary here (rather than leaving it in `domain`) is what avoids a cycle: Text and
  the rest of domain get `Color`/`Font`/`Geometry` transitively.
- **Backend (must move here):** relocate `domain/src/backend/Pdf.jl` into this package
  — the PDF backend renders `GraphicsCanvas`, so it belongs with Graphics. It leaves
  `ProjecturedDomain` entirely. **Actual outcome:** the PDF backend became its own
  package instead, `package/pdf/main/Pdf.jl` (`ProjecturedPdf`), depending on
  `ProjecturedGraphics` rather than living inside it.
- **Projections:** graphics-only ones, e.g. `GraphicsCaching` (Graphics→Graphics).
  (Cross-cutting `*ToGraphics` projections whose *source* lives in domain —
  `WidgetToGraphics`, `LayoutToGraphics`, `GraphLayoutToGraphics` — stay in `domain`,
  which depends on this package.)
- **External deps:** none.

## `ProjecturedText` *(→ ProjecturedGraphics, kernel)*

The Text document + the dependency-free Console backend + the text-centric projections.

- **Document module:** `Text` (`TextModule`).
- **Backend (must move here):** relocate `domain/src/backend/Console.jl` into this
  package — the Console backend renders `TextDocument`, so it belongs with Text. It
  leaves `ProjecturedDomain` entirely. **Actual outcome:** the Console backend became
  its own package instead, `package/console/main/Console.jl` (`ProjecturedConsole`),
  depending on `ProjecturedText` rather than living inside it.
- **Projections (text-centric, depend only on text + graphics + kernel):**
  `TextToGraphics` (Text→Graphics — the reason Text depends on Graphics),
  `TextToString`, `WordWrapping`, `TextFirstLine`, `TextFiltering`, `TextHighlighting`,
  `LineNumbering`, `PrimitiveToText`, `ReferenceToText`. (`TextToWidget` stays in
  `domain` — its target `Widget` is a domain document.)
- **External deps:** none.

## What stays in `ProjecturedDomain`

Everything else, now depending on `ProjecturedText` (→ `ProjecturedGraphics`):
Syntax/JSON/XML/SQL/Widget/Graph/Layout/Math/Formula/… and the **cross-cutting
projections** whose non-text/non-graphics side is a domain document: `SyntaxToText`,
`WidgetToGraphics`, `LayoutToGraphics`, `GraphLayoutToGraphics`, `TextToWidget`,
`SyntaxToWidget`, etc. These resolve fine because `domain` depends on both new packages.

**Actual outcome:** `package/domain/` did not become that holding package. It shrank
to the generic `@domain` macro plus the empty/insertion/reference document machinery
(`package/domain/main/Project.toml` depends on `ProjecturedKernel` only). Syntax, JSON,
XML, SQL, Widget, Graph, Layout, Math, Formula and the rest are each their own package
under `package/`, and each depends on `ProjecturedText`/`ProjecturedGraphics` directly —
dozens of `Project.toml` files list the edge (`grep -rl ProjecturedText package/*/*/Project.toml`).

Note: **`domain/src/backend/` empties** — both `Console.jl` and `Pdf.jl` move out (to
`ProjecturedText` and `ProjecturedGraphics` respectively). `ProjecturedDomain` keeps no
backends. **Actual outcome:** `package/domain/src/` no longer exists at all (the whole
package/ tree flattened its `src/` level to `main/`); both backends became their own
packages (`package/console/`, `package/pdf/`), not part of Text or Graphics.

## Separate test packages (one per package)

Each new package gets its own test package so it can be exercised and flagged green
independently of the monolithic `test`:

- **`ProjecturedGraphicsTest`** *(→ ProjecturedGraphics)* — moves the graphics/PDF tests
  out of `test`: `document/GraphicsTest.jl`, `document/GraphicsLayoutTest.jl`,
  `backend/PdfTest.jl`. (Rendering tests that need a real GPU/window backend —
  `backend/DirtyRectTest.jl`, `projection/GraphicsToFileTest.jl` — pull in `ProjecturedSdl`;
  decide per test whether it belongs here with an `Sdl` dep or stays in the integration
  `test` package.)
- **`ProjecturedTextTest`** *(→ ProjecturedText)* — moves the text tests:
  `document/TextTest.jl`, `backend/ConsoleBackendTest.jl`, `editor/TextNavigationTest.jl`,
  `projection/{TextToGraphics,TextFiltering,TextHighlighting,WordWrapping,PrimitiveToText}Test.jl`.

The existing `ProjecturedTest` shrinks accordingly (loses the graphics/text-only tests;
keeps integration/cross-domain tests). This establishes the pattern of **per-package
test packages**; it can be extended to other packages later.

**Actual outcome: not done this way.** `package/graphics/` and `package/text/` hold
only `main/` and `doc/` — no `test/` folder, so `ProjecturedGraphicsTest` and
`ProjecturedTextTest` do not exist. There is also no single monolithic `ProjecturedTest`
left to shrink; the old `test` package was itself split along with everything else.
Graphics and Text code is exercised indirectly through the `test/` package of every
domain that depends on it (`package/json/test`, `package/xml/test`, `package/syntax/test`,
and so on), plus `package/console/main` and `package/pdf/main`'s own consumers. The
per-package-test-package pattern this section proposed did land for many other
packages, just not literally for graphics/text.

## "No new dependencies" — confirmed

`ProjecturedGraphics` and `ProjecturedText` introduce **zero** external deps. The only
new edges are internal: `ProjecturedText → ProjecturedGraphics`, and
`ProjecturedDomain → ProjecturedText`. Console/PDF remain dependency-free (verified).

## Open questions

- **Color** is imported by `Text` (and 34 files) but `GraphicsModule` itself doesn't
  import it; it's grouped into `ProjecturedGraphics` as part of the base visual
  vocabulary. Confirm that placement (alternative: put `Color` in `ProjecturedText`, but
  then graphics-side users of color would need text — worse). **Resolved differently:**
  `Color` landed in a new `package/style/` package together with `Font`/`Geometry`/
  `StyleText`/`StyleStroke`/`Image`, and both `ProjecturedGraphics` and `ProjecturedText`
  depend on `ProjecturedStyle`.
- Exact home for a few projections on the boundary (e.g. `SelectionInverting`,
  `TextToString` consumers) — settle when moving each file.
- Whether `ProjecturedSdl`/`ProjecturedWeb` should narrow their dep from
  `ProjecturedDomain` to `ProjecturedGraphics` (they mostly render `GraphicsCanvas`).
  Optional follow-up, not required by this split.

## Relationship to the other plans

Independent of the [source-tree reorganization](../done/source-tree-reorganization.md)
(which just moves dirs) and the [video extraction](../done/extract-video-package.md).
Both of those plans are now in `plan/done/`. After all land, the package set grows by
four (`graphics`, `text`, + their two test packages), all under `package/`. Order
suggestion: do this extraction *before* the directory reorg, or fold the new dirs into
the reorg's `package/` move. **Actual outcome:** the package set grew by far more than
four — `graphics`, `text`, `style`, `console`, `pdf`, and about fifteen other packages
that used to be the single `domain`, each landed as their own package. This plan asked
for a dedicated `test/` folder on `graphics` and `text`; neither package got one.

## Status

Audit 2026-08-12: verified against the current `package/` layout (63 packages).

- [x] ✅ DONE (2026-08-12) — Create `ProjecturedGraphics` — `package/graphics/main/Project.toml`
      names `ProjecturedGraphics`; holds `Graphics.jl`, `GraphicsCaching.jl`,
      `PointReferenceStep.jl`. The style vocabulary (`Color`/`Font`/`Geometry`/
      `StyleText`/`StyleStroke`/`Image`) went to a separate `package/style/` instead of
      into Graphics; `ProjecturedGraphics` depends on `ProjecturedStyle`. `Pdf.jl`
      became its own package, `package/pdf/main/` (`ProjecturedPdf`), depending on
      `ProjecturedGraphics` rather than living inside it.
- [x] ✅ DONE (2026-08-12) — Create `ProjecturedText` — `package/text/main/Project.toml`
      names `ProjecturedText`, depends on `ProjecturedGraphics`. Holds `Text.jl`,
      `TextToGraphics.jl`, `TextFiltering.jl`, `TextHighlighting.jl`, and the other
      text-centric projections. `Console.jl` became its own package,
      `package/console/main/` (`ProjecturedConsole`), depending on `ProjecturedText`
      rather than living inside it.
- [x] ✅ DONE (2026-08-12), differently than proposed — Repoint the old
      `ProjecturedDomain` to depend on `ProjecturedText`. `package/domain/main/`
      shrank to only the generic `@domain` machinery and depends on `ProjecturedKernel`
      only; the twenty former domains (Syntax/JSON/XML/SQL/Widget/Graph/…) are now
      separate packages that depend on `ProjecturedText`/`ProjecturedGraphics`
      directly — confirmed by `grep -rl ProjecturedText package/*/*/Project.toml`
      listing dozens of packages.
- [ ] ⏳ OPEN — Create `ProjecturedGraphicsTest` + `ProjecturedTextTest`; shrink
      `ProjecturedTest` — `package/graphics/` and `package/text/` hold only `main/`
      and `doc/`, no `test/`. There is no single `ProjecturedTest` left either; the
      old monolithic test package was itself split alongside everything else.
      Graphics/Text code is exercised through each depending domain's own `test/`.
- [x] ✅ DONE (2026-08-12) — Verify each package loads and is green in isolation —
      both packages carry their own `Project.toml` with `[sources]` path deps and
      load as part of every domain package that depends on them (`test_json()`,
      `test_syntax()`, and so on all exercise `ProjecturedGraphics`/`ProjecturedText`
      transitively). Not verified as a standalone `Pkg.resolve()` with no dependents,
      since the dedicated test packages above were never built.
