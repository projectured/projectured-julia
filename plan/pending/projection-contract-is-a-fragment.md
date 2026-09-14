# The projection contract is a fragment, not a module

## The problem

Seven layers of the kernel declare a contract of open generics. Six put that
contract in a **fragment** of the layer's module. The projection layer puts it
in a **module of its own**.

| layer | contract file | a module? |
| --- | --- | --- |
| backend | `BackendInterface.jl` | no |
| cell | `CellInterface.jl` | no |
| document | `DocumentInterface.jl` | no |
| iomap | `IoMapInterface.jl` | no |
| reference | `ReferenceInterface.jl` | no |
| selection | `SelectionInterface.jl` | no |
| projection | `ProjectionApi.jl` | **yes** |

It breaks the convention twice: a module where the others use a fragment, and
the word `Api` where the others say `Interface`.
[code-quality-rules.md](../../documentation/rule/code-quality-rules.md) states
the convention as a rule — "A contract fragment holds no body" — and names
`DocumentInterface.jl` as the model. The projection layer does not follow the
rule that the document states.

## The alternative, and why it loses

The other way to make the tree consistent is to give every contract its own
module. Count how often each contract is imported by name to extend it:

| contract | `import ..XModule: …` lines |
| --- | ---: |
| `ProjectionApiModule` | 40 |
| `CellModule` | 9 |
| `DocumentModule` | 2 |
| `SelectionModule` | 2 |
| `ReferenceModule` | 1 |
| `IoMapModule` | 0 |
| `BackendModule` | 0 |

Projection's contract is extended by every projection in every slice. Two of the
others are never extended at all. Six new modules would add six names to the
public surface and six answers to "which module does this file go in", to serve
fourteen import lines. The evidence points the other way: projection joins the
six.

## What the separation does not buy

**It is not what makes the extension seam work.** The seam is the import list,
not the module. `import ..DocumentModule: is_element_collection` is already the
normal form in six layers, nine times over for `CellModule`. After the merge the
line reads `import ..ProjectionModule: print_document, …` and behaves the same.

**The merged namespace is small.** The contract exports 8 names and
`ProjectionModule` exports 2. Merged: **10 exports, 44 names**. Compare
`SelectionModule` at 11 and 62, `DocumentModule` at 34 and 228, and
`ReferenceModule` at **72 and 464**. The merged module is the smallest of the
four.

## The target shape

`ProjectionModule` follows `DocumentModule`: a head file and three fragments.

```
source/kernel/projection/
  ProjectionLayer.jl              the layer's ordered include list
  ProjectionReferenceStep.jl      ProjectionReferenceStepModule   (unchanged)
  PrinterContext.jl               PrinterContextModule            (unchanged)
  ChildrenContainer.jl            ChildrenContainerModule         (unchanged)
  ProjectionModule.jl             the head
    ProjectionInterface.jl        the `Projection` type and the open generics
    ProjectionDefaults.jl         the fallback method of each generic
    ProjectionMacro.jl            `@projection`
  GestureBindings.jl              ProjectionGestureBindingsModule (unchanged)
  ProjectionTemplate.jl           ProjectionTemplateModule        (unchanged)
```

Seven modules become six.

`ProjectionInterface.jl` is `ProjectionApi.jl` with the `module` line, the
`export` line and the closing `end` removed, and a `# Fragment of
\`ProjectionModule\` — …` header added. Its 57-line contract docstring moves to
the head, where it documents the module, as `DocumentModule.jl` does.

`ProjectionDefaults.jl` and `ProjectionMacro.jl` are `Projection.jl` split at
the macro. The `import ..ProjectionApiModule: print_document, …` line
disappears: a default now extends a generic in its own namespace.

## The include reorder

The contract loads second in the layer today and `Projection.jl` loads sixth,
with three modules between them. One of those three needs the contract:
`GestureBindings.jl` takes the abstract type `Projection`. So the merged module
must load before it.

```
ProjectionReferenceStep → PrinterContext → ChildrenContainer
    → ProjectionModule → GestureBindings → ProjectionTemplate
```

Every edge checked: `Projection.jl` needs `PrinterContextModule` and nothing
from `ChildrenContainer` or `GestureBindings`, so it can move up.
`ProjectionTemplate.jl` needs `ChildrenContainer`, `ProjectionReferenceStep` and
`PrinterContext`, all of which stay below it.

## What changes outside the layer

156 mentions of `ProjectionApiModule` in `source/`, `test/`, `example/` and
`package/`, and 38 documents.

| case | count | change |
| --- | ---: | --- |
| A file uses the contract and `ProjectionModule` | 24 | delete the `using ..ProjectionApiModule` line |
| A file uses the contract alone | 20 | rename the `using` to `..ProjectionModule` |
| An extension import | 40 | rename the module in `import ..X: print_document, …` |
| A package root binds the name explicitly | 19 | delete the `const ProjectionApiModule = …` line |
| A qualified call `ProjectionApiModule.print_document` | 8 files | rename the qualifier |

The eight qualified files matter most. `ProjectionTemplate.jl` and
`RstToSyntax.jl` emit `ProjectionApiModule.print_document(…)` **from inside a
macro expansion**, which is the safe way for generated code to extend a generic.
Those must be right or a method lands in the wrong module and defines a new
function silently.

## The steps

1. Write `ProjectionModule.jl`: the contract docstring, the header, the fragment
   table, the three includes.
2. Turn `ProjectionApi.jl` into `ProjectionInterface.jl`. Remove the `module`
   line, the `export` line and the closing `end`. Move the docstring to the head.
3. Split `Projection.jl` into `ProjectionDefaults.jl` and `ProjectionMacro.jl`.
   Remove the module line, the header and the `import ..ProjectionApiModule`.
4. Reorder `ProjectionLayer.jl`.
5. Load the kernel. `test_kernel()` must report 1638/3/3/1644, the measured
   baseline.
6. Sweep the five consumer cases in the table above.
7. `test_export_collisions()` over the whole stack, and a full `test_all()`
   compared against the baseline, because 39 slices are touched.
8. Update the module inventory in
   [system-anatomy.md](../../documentation/design/system-anatomy.md) and the 38
   documents that name `ProjectionApiModule`.

## The risk

**A rename of a module that 39 slices extend.** The compiler does not catch the
failure mode. After `using X`, an unqualified `f(…) = …` for a name that `X`
exports defines a **new function**, silently, measured on Julia 1.13. A missed
import line therefore does not fail to load: it loads, and the projection stops
being called. `shadowed_extension_violations` in
[test/suite/naming.jl](../../test/suite/naming.jl) is the guard that reports it,
and `relative_import_errors` in
[CheckLayering.jl](../../test/kernel/layering/CheckLayering.jl) checks every
file's import shape. Run both before the suites.

**Sweep with the parser, not with `sed`.** `workspace/bin/julia-rename.jl` walks
the tree Julia's own parser builds. Its two blind spots are a string and a
module-qualified call, and this sweep has eight files full of module-qualified
calls, so it needs a second pass over those by hand.

## What this plan does not touch

`ProjectionReferenceStepModule` stays a module. It is a reference step whose
payload happens to be a projection; it needs only Document and Reference, it
loads first in the layer, and two files use it and nothing else.

`ProjectionTemplateModule` stays a module. Whether the template engine belongs
inside `ProjectionModule` is a separate question, to be answered on its own
evidence: it holds 193 names against the merged module's 44.
