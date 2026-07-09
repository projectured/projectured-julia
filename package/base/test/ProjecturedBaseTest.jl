"""
    ProjecturedBaseTest

Test package for `ProjecturedBase` — second tier of the test-package DAG that
parallels the main DAG (kernel ← base ← visual ← domain ← umbrella; see
plan/pending/test-package-split.md). It hosts:

- the base package's own tests (`test_collection`, `test_copying_projection`),
  aggregated by `test_base()`;
- the static layering guard for base (`test_base_layering`, via
  `ProjecturedKernelTest.check_layering`);
- the **generic document-walk selection enumerators**: the CellVector-aware
  `_walk_document` and the ground-truth enumerators
  `collect_position_selections` / `collect_tree_selections` consumed by the
  navigation presets in `ProjecturedVisualTest` (over the generic
  `explore_selections` driver in `ProjecturedKernelTest`). Higher test
  packages extend `_text_leaf_length` (visual: `TextString` leaves) and add
  projection-aware enumerators (domain: JSON trees).

Like the umbrella, this is a **function library**: `using ProjecturedBaseTest`
from the repo-root environment, then call `test_base()` or any individual
`test_*` function.
"""
module ProjecturedBaseTest

using Test
import ProjecturedBase
using ProjecturedKernelTest
using ProjecturedBase.CellModule
using ProjecturedBase.DocumentModule
using ProjecturedBase.ReferenceModule
using ProjecturedBase.PrinterContextModule: PrinterContext
using ProjecturedBase.IdentityProjectionModule: IdentityProjection
using ProjecturedBase.ProjectionApiModule: print_document, read_intent
using ProjecturedBase.CollectionModule
using ProjecturedBase.PrimitiveModule
using ProjecturedBase.CopyingProjectionModule
using ProjecturedBase.FocusingProjectionModule: FocusingProjection, ReplaceFocusPartOperation
using ProjecturedBase.KeyboardModule: KeyDown
using ProjecturedBase.ModifiersModule: Modifiers

include("document/CollectionTest.jl")
include("document/SelectionEnumeration.jl")
include("projection/CopyingProjectionTest.jl")
include("projection/FocusingTest.jl")

"""
    test_base_layering()

Static layered-architecture guard for `ProjecturedBase` (see
`ProjecturedKernelTest.check_layering`).
"""
function test_base_layering()
    # `pkgdir` rejects the flat entryfile-at-root layout (main/ProjecturedBase.jl
    # is not under a src/), so derive the package root from `pathof`.
    main = normpath(dirname(pathof(ProjecturedBase)))
    check_layering(main, joinpath(main, "ProjecturedBase.jl");
                   name = "base",
                   layers = ["document", "projection", "serialization"])
end

"""
    test_base()

Run the whole base suite: the static layering guard and every base unit test.
"""
function test_base()
    @testset "ProjecturedBase" begin
        test_base_layering()
        test_collection()
        test_copying_projection()
        test_focusing()
    end
end

export test_base, test_base_layering
export test_collection, test_copying_projection, test_focusing
export _text_leaf_length, _walk_document, collect_position_selections, collect_tree_selections

end # module ProjecturedBaseTest
