# Extract `ProjecturedGraphics` and `ProjecturedText` packages

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
  `ProjecturedDomain` entirely.
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
  leaves `ProjecturedDomain` entirely.
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

Note: **`domain/src/backend/` empties** — both `Console.jl` and `Pdf.jl` move out (to
`ProjecturedText` and `ProjecturedGraphics` respectively). `ProjecturedDomain` keeps no
backends.

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

## "No new dependencies" — confirmed

`ProjecturedGraphics` and `ProjecturedText` introduce **zero** external deps. The only
new edges are internal: `ProjecturedText → ProjecturedGraphics`, and
`ProjecturedDomain → ProjecturedText`. Console/PDF remain dependency-free (verified).

## Open questions

- **Color** is imported by `Text` (and 34 files) but `GraphicsModule` itself doesn't
  import it; it's grouped into `ProjecturedGraphics` as part of the base visual
  vocabulary. Confirm that placement (alternative: put `Color` in `ProjecturedText`, but
  then graphics-side users of color would need text — worse).
- Exact home for a few projections on the boundary (e.g. `SelectionInverting`,
  `TextToString` consumers) — settle when moving each file.
- Whether `ProjecturedSdl`/`ProjecturedWeb` should narrow their dep from
  `ProjecturedDomain` to `ProjecturedGraphics` (they mostly render `GraphicsCanvas`).
  Optional follow-up, not required by this split.

## Relationship to the other plans

Independent of the [source-tree reorganization](source-tree-reorganization.md) (which
just moves dirs) and the [video extraction](extract-video-package.md). After all land,
the package set grows by four (`graphics`, `text`, + their two test packages), all under
`package/`. Order suggestion: do this extraction *before* the directory reorg, or fold
the new dirs into the reorg's `package/` move.

## Status

- [ ] Create `ProjecturedGraphics` (vocabulary + Graphics + Pdf + graphics projections)
- [ ] Create `ProjecturedText` (Text + Console + text projections; dep on Graphics)
- [ ] Repoint `ProjecturedDomain` to depend on `ProjecturedText`; move cross projections' homes as needed
- [ ] Create `ProjecturedGraphicsTest` + `ProjecturedTextTest`; shrink `ProjecturedTest`
- [ ] Verify each package + test package loads and is green in isolation; `Pkg.resolve()`
