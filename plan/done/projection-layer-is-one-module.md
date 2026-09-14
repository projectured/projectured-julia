# The projection layer is one module

## The problem

The projection layer declares **seven modules**. No other kernel layer declares
more than three, and eleven of the seventeen declare one.

| layer | modules |
| --- | ---: |
| projection | **7** |
| cell | 3 |
| agent, editor, event, operation | 2 |
| the other eleven | 1 |

One of the seven is a contract of open generics in a module of its own. Six
other layers put the same thing in a **fragment**:

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

The cost lands in every slice's header. A domain that writes one projection
names four modules to do it.

## The model

`DocumentModule` is one module holding the contract, the defaults, the
`@document` codegen, the copy, the sync, the walk, the search and the protocol
macros — nine fragments. A merged `ProjectionModule` is the same shape.

| module | fragments | exports | names |
| --- | ---: | ---: | ---: |
| `DocumentModule` | 9 | 34 | 228 |
| `ReferenceModule` | — | 72 | **464** |
| **merged `ProjectionModule`** | **5** | 28, then **23** | 252 |

It sits between the two modules nobody finds unusable.

## The evidence

**Five of the seven modules are never used without the contract.** Measured
over `source/`, `test/`, `example/` and `package/`, outside the layer itself:

| module | files that use it and no other projection module |
| --- | ---: |
| `ProjectionApiModule` | 8 |
| `ProjectionReferenceStepModule` | 2 |
| `ChildrenContainerModule` | 1 |
| `ProjectionModule` | 0 |
| `ProjectionTemplateModule` | 0 |
| `PrinterContextModule` | 0 |
| `ProjectionGestureBindingsModule` | 0 |

**The reference step costs exactly one module.** Nineteen modules name it.
Eighteen already name another projection module, so for them the merge deletes
a line. The exception is `DomainModule`, which uses one name,
`normalize_named_node_reference`. It takes a named import instead, which is the
form the shared policy already prefers two to one.

**The template DSL words are used only inside `@projection_template`.** I
checked every call of `bound`, `project`, `collection`, `tokens` and `sections`
across `source/`: 14 files, every one a template file. The one hit outside is
`Pkg.project()` in `Builder.jl`, a different function.

| word | calls | files |
| --- | ---: | ---: |
| `project` | 119 | 11 |
| `bound` | 90 | 14 |
| `collection` | 88 | 12 |
| `tokens` | 3 | 1 |
| `sections` | 2 | 1 |

`tokens` and `sections` hold five call sites between them and occupy a name in
every slice that names the template module.

**Four files already bind those words as locals**, which shows they are words
ordinary code wants:

| file | line |
| --- | --- |
| `source/pane/PaneSurgery.jl:121` | `collection = getproperty(owner, field)` |
| `source/widget/WidgetDocument.jl:2293` | `bound = content isa Action ? content : nothing` |
| `source/kernel/tool/Documentation.jl:539` | `sections = _GuideSection[]` |
| `source/sql/SqlParser.jl:114` | `tokens = SqlToken[]` |

A local shadows harmlessly. A top-level definition would not: after `using X`,
an unqualified definition of a name `X` exports defines a **new function**,
silently, measured on Julia 1.13.

**No cycle blocks the merge.** `ProjectionTemplate.jl` never names
`read_projection_gesture` or `ProjectionGestureBindingsModule`, so
`GestureBindings` can load after the merged module, which it must, because it
takes the abstract type `Projection`.

## The alternative, and why it loses

The other way to make the tree consistent is to give every contract its own
module. Count how often each is imported by name to extend it:

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
public surface to serve fourteen import lines.

**The separation is not what makes the seam work.** The seam is the import list.
`import ..DocumentModule: is_element_collection` is already the normal form in
six layers. After the merge the line reads
`import ..ProjectionModule: print_document, …` and behaves the same.

## The target shape

```
source/kernel/projection/
  ProjectionLayer.jl          the layer's ordered include list
  PrinterContext.jl           PrinterContextModule
  ChildrenContainer.jl        ChildrenContainerModule
  ProjectionModule.jl         the head
    ProjectionReferenceStep.jl    the reference step whose payload is a projection
    ProjectionInterface.jl        the `Projection` type and the open generics
    ProjectionDefaults.jl         the fallback method of each generic
    ProjectionMacro.jl            `@projection`
    ProjectionTemplate.jl         `@projection_template` and the engine
  GestureBindings.jl          ProjectionGestureBindingsModule
```

Seven modules become four. The include order of the layer:

```
PrinterContext → ChildrenContainer → ProjectionModule → GestureBindings
```

Every edge checked. `PrinterContext` needs Cell, Document, Reference and Clock,
none of them in the layer. `ChildrenContainer` needs nothing.
`ProjectionModule` needs both. `GestureBindings` needs `Projection`.

## Stage 1 — the contract becomes a fragment (done)

- [x] Write `ProjectionModule.jl`: the contract docstring, the header, the
  fragment table, the includes.
- [x] `ProjectionApi.jl` → `ProjectionInterface.jl`. Remove the `module` line,
  the `export` line and the closing `end`. Move the docstring to the head.
- [x] Split `Projection.jl` into `ProjectionDefaults.jl` and
  `ProjectionMacro.jl`. The `import ..ProjectionApiModule: print_document, …`
  disappears: a default now extends a generic in its own namespace.
- [x] Reorder `ProjectionLayer.jl`.
- [x] Sweep the consumers. 156 mentions of `ProjectionApiModule` in `source/`,
  `test/`, `example/` and `package/`, and 38 documents.

| case | count | change |
| --- | ---: | --- |
| uses the contract and `ProjectionModule` | 24 | delete the `using` line |
| uses the contract alone | 20 | rename the `using` |
| an extension import | 40 | rename the module in the `import` |
| a package root binds the name | 19 | delete the `const` line |
| a qualified call `ProjectionApiModule.print_document` | 8 files | rename the qualifier |


**What stage 1 measured.** Every number matches the baseline taken on `main` the
same way.

| check | result |
| --- | --- |
| `test_kernel()` | 1638 / 3 / 3 / 1644 — identical |
| `test_substrate()` | 60167 / 4 / 2 / 1 / 60174 — identical |
| `test_rst()` | 79 / 3 / 2 / 84 — identical |
| `test_json()` | 170 / 170 |
| `test_syntax()`, `test_text()` | all pass |
| the naming guard over the whole tree | clean |
| `using Projectured` | loads, no warning |
| `test_export_collisions()` | 1 / 1, checker 5 / 5 |
| mentions of `ProjectionApiModule` left in code | 0 |

**A trap the plan did not name.** Nineteen package roots bind the kernel's
modules with an explicit `const` list rather than the alias loop. The line
`const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule` is an alias
to **rename**, not to delete. Deleting it left ten roots with nothing bound to
`ProjectionModule`, and three packages failed to precompile with
`UndefVarError: ProjectionModule not defined`. Stage 2 must rename an alias, not
drop one, and must run this check over every package:

> for each package root, if any source file it includes says
> `using ..ProjectionModule`, the root must bind that name by a `const` or by
> the alias loop.

`ProjecturedKernel` is the one legitimate hit: there `ProjectionModule` is a
real submodule and needs no alias.

## Stage 2 — the reference step and the template engine move in (done)

- [x] `ProjectionReferenceStep.jl` and `ProjectionTemplate.jl` become fragments.
  Their headers fold into `ProjectionModule.jl`.
- [x] ~~`DomainModule` takes a named import.~~ **Wrong.** `DomainModule` only
  *calls* `normalize_named_node_reference`; it extends nothing.
  `PAR-QUALIFIED-EXTENSION` says a name a file only calls arrives through a bare
  `using`. It takes `using ..ProjectionModule`.
- [x] Delete the `using ..ProjectionReferenceStepModule` and
  `using ..ProjectionTemplateModule` lines from the 18 modules that already name
  another projection module.
- [x] The 8 files with a qualified `ProjectionApiModule.print_document` inside a
  macro expansion take the new qualifier.


**What stage 2 measured.** Again every number matches the baseline.

| check | result |
| --- | --- |
| `test_kernel()` | 1638 / 3 / 3 / 1644 — identical |
| `test_substrate()` | 60167 / 4 / 2 / 1 / 60174 — identical |
| `test_rst()` | 79 / 3 / 2 / 84 — identical |
| `test_json()` | 170 / 170 |
| the naming guard | clean |
| `using Projectured` | loads, no warning |
| `test_export_collisions()` | 1 / 1, checker 5 / 5 |

`ProjectionModule` now exports **28** names and holds **240**. `DocumentModule`
holds 228 and `ReferenceModule` 464, so it lands between the two, as predicted.

**A form the sweep's regular expressions did not see.**
`ProjectionReferenceStep.jl` builds two method-definition names with
`GlobalRef(ProjectionReferenceStepModule, :ProjectionReferenceStep)`. A
`GlobalRef` names the module with a comma, not a dot, so neither the
qualified-call pattern nor the import pattern matched. Grep for the bare module
name after every sweep, not only for its `using`, `import` and `Mod.` forms.

## Stage 3 — the DSL words leave the export list (done)

Today `@projection_template` escapes the builder wholesale — `$(esc(builder))` —
so `bound`, `project`, `collection`, `tokens` and `sections` resolve in the
caller's module and must be exported.

- [x] The macro walks the builder and rewrites those five call heads to
  `ProjectionModule.bound(…)` and so on. It already does this for
  `print_document`, and the comment there gives the reason: an unqualified name
  resolved in the caller's module silently defined a dead local one.
- [x] Delete them from the export list. **Ten names, not five**: the five
  marker types `Bound`, `Project`, `Collection`, `Tokens` and `Sections` have
  no code user outside the projection layer either — every hit was prose in a
  comment. 28 exports become 19.
- [x] Proved: `isdefined(JsonModule, :bound)` and the other nine are all
  `false`, in `JsonModule` and in `RstModule`, and every template still builds.

Stage 3 is last because it is the only stage that changes a macro, and because
after stages 1 and 2 the words are the last namespace cost left.


**Three macros, not one.** `@projection_template` was not the only escape hatch:
`RstToSyntax.jl` defines `@rst_flat` and `@rst_indented`, 32 uses between them,
and their builders write `collection(:lines)` like any other. Each of the three
calls `make_template_builder` on its body now.

**The resolver is one exported name in place of ten.**
`make_template_builder(expr)` walks the body and binds each marker-word **call
head** to this module's function. A local of the same name, a field access and a
word in a string are left alone.

**What stage 3 measured.**

| check | result |
| --- | --- |
| `test_kernel()` | 1638 / 3 / 3 / 1644 — identical |
| `test_substrate()` | 60167 / 4 / 2 / 1 / 60174 — identical |
| `test_rst()` | 79 / 3 / 2 / 84 — identical |
| `test_json()` | 170 / 170 |
| the naming guard | clean |
| `using Projectured` | loads, no warning |
| `test_export_collisions()` | 1 / 1, checker 5 / 5 |
| `ProjectionModule` exports | 28 → **19** |

## Stage 4 — the remaining three (done)

`PrinterContextModule`, `ChildrenContainerModule` and
`ProjectionGestureBindingsModule` folded in. The layer is one module, which is
what eleven of the seventeen kernel layers already are.

The measurement said it would be nearly free, and it was: `PrinterContext` and
`GestureBindings` are never used without the contract, and `ChildrenContainer`
is used alone by one file. Nothing inside the module needs the gesture bindings,
so the include order was free; `ClockModule` was the only new dependency, and it
came with `PrinterContext`.

- [x] The three become fragments. `ProjectionLayer.jl` is one include.
- [x] 32 bare usings deleted, 6 imports renamed, 19 package-root aliases
  renamed, 3 absolute paths renamed.

**The final size.** `ProjectionModule` exports **30** names over 8 fragments and
holds 281. `DocumentModule` exports 34 and holds 228; `ReferenceModule` exports
72 and holds 464. The one module of the projection layer exports fewer names
than the document layer's.

**What stage 4 measured.**

| check | result |
| --- | --- |
| `test_kernel()` | 1638 / 3 / 3 / 1644 — identical |
| `test_substrate()` | 60167 / 4 / 2 / 1 / 60174 — identical |
| `test_rst()` | 79 / 3 / 2 / 84 — identical |
| `test_json()` | 170 / 170 |
| the naming guard | clean |
| `using Projectured` | loads, no warning |
| `test_export_collisions()` | 1 / 1, checker 5 / 5 |

## The result

Seven modules became one.

```
source/kernel/projection/
  ProjectionLayer.jl          one include
  ProjectionModule.jl         30 exports, 281 names
    ChildrenContainer.jl
    PrinterContext.jl
    ProjectionReferenceStep.jl
    ProjectionInterface.jl
    ProjectionDefaults.jl
    ProjectionMacro.jl
    GestureBindings.jl
    ProjectionTemplate.jl
```

## The risk

**A rename of a module that 39 slices extend.** The compiler does not catch the
failure mode. A missed import line does not fail to load: it loads, defines a
new function, and the projection stops being called.
`shadowed_extension_violations` in [test/suite/naming.jl](../../test/suite/naming.jl)
and `relative_import_errors` in
[CheckLayering.jl](../../test/kernel/layering/CheckLayering.jl) are the guards
that report it. Run both before the suites, at every stage.

**A static scan cannot tell you what a macro injects.** `@projection` injects
`<: Projection` into the caller's scope, so a slice needs the contract even when
its source never writes the word. I measured json as needing nothing from
`ProjectionApiModule`, removed the line, and the package failed to precompile
with `UndefVarError: Projection`. Prove every deletion with the loader.

**Sweep with the parser, not with `sed`.** `workspace/bin/julia-rename.jl` walks
the tree Julia's own parser builds. Its two blind spots are a string and a
module-qualified call, and this sweep has eight files full of module-qualified
calls, so those need a second pass by hand.

## The check at every stage

1. The kernel loads.
2. `test_kernel()` reports 1638/3/3/1644, the measured baseline.
3. `shadowed_extension_violations` and `relative_import_errors` report nothing
   new.
4. `test_export_collisions()` over the whole stack.
5. After stage 2 and stage 3, a full `test_all()` against the baseline, because
   39 slices are touched.

## What a slice header looks like at the end

The json slice, today and after:

```diff
 using ..DomainModule
-using ..EventPatternModule          # dead today; proved by the loader
 using ..GestureBindingModule
 …
 using ..ProjectionAlgebraModule
-using ..ProjectionApiModule
 using ..ProjectionModule
-using ..ProjectionReferenceStepModule
-using ..ProjectionTemplateModule
 using ..ReferenceModule
```

Twenty usings become sixteen. One line carries `Projection`, `@projection`,
`@projection_template`, `normalize_named_node_reference`, and the DSL words the
macro resolves.
