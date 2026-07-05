"""
    ProjecturedVisual

The rendering substrate — layered between `ProjecturedBase` and
`ProjecturedDomain` (kernel ← base ← visual ← domain). Owns everything about
*how documents become visible*: style atoms, the screen/window model, the
render-target documents (Graphics, Layout, Text, Widget, Syntax) with their
projections, and the dependency-free backends (Console, Pdf).

## Slice order (per plan/pending/domain-layered-architecture.md)

Each slice imports only slices to its left:

```
style → screen → graphics → layout → text → widget → syntax → backend
```

Machine-verified in the plan with one refactor (V1): LayoutToGraphics's
Widget focus-path helpers move down into `layout/` as open generics; widget/
adds its methods beside its types. After V1 the ordering has zero
violations.

## Slice inventory (target — populated across Q1)

- **style/** — Color, Font, Geometry, Image, StyleText, StyleStroke: pure
  value types every visual thing shares. **Landing in the first Q1
  sub-commit.**
- **screen/** — ScreenDocument (windows + window events/ops, arrives from
  base at Q1) + WindowManaging + ScreenToScreen: the window model.
- **graphics/** — Graphics + GraphicsCaching: the retained drawing target.
- **layout/** — Layout + ConstraintSolver + LayoutToGraphics +
  CollectionToLayout + the V1 focus-path generics: spatial arrangement.
- **text/** — Text + its projections/decorators + PrimitiveToText +
  ReferenceToText.
- **widget/** — Widget + its projections + ObjectToWidget + hover/config/popup
  decorators.
- **syntax/** — Syntax + its bridges (ObjectToSyntax, CollectionToSyntax,
  PrimitiveToSyntax) + SyntaxToText + SyntaxToWidget + InsertionToSyntax +
  NaturalProjection.
- **backend/** — Console.jl, Pdf.jl (the dependency-free concrete backends).

Kernel/base aliases below let files inside this package keep their relative
`..XxxModule` references unchanged.
"""
module ProjecturedVisual

using ProjecturedKernel
using ProjecturedBase

# ── Kernel + base submodule aliases (populate as slices land) ─────────────
const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
# Legacy name: kernel plan P2 merged DocumentApiModule into DocumentModule.
const DocumentApiModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const GestureModule = ProjecturedKernel.GestureModule
const BackendModule = ProjecturedKernel.BackendModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const IntentModule = ProjecturedKernel.IntentModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const CollectionModule = ProjecturedBase.CollectionModule
const PrimitiveModule = ProjecturedBase.PrimitiveModule
const ScreenDocumentModule = ProjecturedBase.ScreenDocumentModule

# ── Slice 1 — style (pure value types every visual thing shares) ─────────
# Load order: Color and Font first (no forward references); Geometry, Image,
# StyleStroke, StyleText follow. StyleText imports Font + Color; StyleStroke
# imports Color.
include("style/Color.jl")
include("style/Font.jl")
include("style/Geometry.jl")
include("style/Image.jl")
include("style/StyleStroke.jl")
include("style/StyleText.jl")

# Slices 2-8 land in subsequent Q1 sub-commits.

end # module ProjecturedVisual
