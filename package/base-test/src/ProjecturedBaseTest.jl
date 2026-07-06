"""
    ProjecturedBaseTest

Test package for `ProjecturedBase` — second tier of the test-package DAG that
parallels the runtime DAG (kernel ← base ← visual ← domain ← umbrella; see
plan/pending/test-package-split.md). It hosts:

- the base package's own tests (`test_collection`, `test_copying_projection`),
  aggregated by `test_base()`;
- the static layering guard for base (`test_base_layering`, via
  `ProjecturedKernelTest.check_layering`);
- the **generic document-walk selection enumerators**: the CellVector-aware
  `_walk_document` and the base methods of the `collect_text_selections` /
  `collect_tree_selections` generics declared in `ProjecturedKernelTest`.
  Higher test packages extend `_text_leaf_length` (visual: `TextString`
  leaves) and add projection-aware enumerators (domain: JSON trees).

Like the umbrella, this is a **function library**: `using ProjecturedBaseTest`
from the repo-root environment, then call `test_base()` or any individual
`test_*` function.
"""
module ProjecturedBaseTest

using Test
import ProjecturedBase
using ProjecturedKernelTest
import ProjecturedKernelTest: collect_text_selections, collect_tree_selections
using ProjecturedBase.CellModule
using ProjecturedBase.DocumentModule
using ProjecturedBase.ReferenceModule
using ProjecturedBase.PrinterContextModule: PrinterContext
using ProjecturedBase.IdentityProjectionModule: IdentityProjection
using ProjecturedBase.ProjectionApiModule: print_document, read_intent
using ProjecturedBase.CollectionModule
using ProjecturedBase.PrimitiveModule
using ProjecturedBase.CopyingProjectionModule

include("document/CollectionTest.jl")
include("document/SelectionEnumeration.jl")
include("projection/CopyingProjectionTest.jl")

"""
    test_base_layering()

Static layered-architecture guard for `ProjecturedBase` (see
`ProjecturedKernelTest.check_layering`).
"""
function test_base_layering()
    src = normpath(joinpath(pkgdir(ProjecturedBase), "src"))
    check_layering(src, joinpath(src, "ProjecturedBase.jl");
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
    end
end

export test_base, test_base_layering
export test_collection, test_copying_projection
export _text_leaf_length, _walk_document, collect_text_selections, collect_tree_selections

end # module ProjecturedBaseTest
