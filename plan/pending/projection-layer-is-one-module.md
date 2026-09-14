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

## Stage 1 — the contract becomes a fragment

- [ ] Write `ProjectionModule.jl`: the contract docstring, the header, the
  fragment table, the includes.
- [ ] `ProjectionApi.jl` → `ProjectionInterface.jl`. Remove the `module` line,
  the `export` line and the closing `end`. Move the docstring to the head.
- [ ] Split `Projection.jl` into `ProjectionDefaults.jl` and
  `ProjectionMacro.jl`. The `import ..ProjectionApiModule: print_document, …`
  disappears: a default now extends a generic in its own namespace.
- [ ] Reorder `ProjectionLayer.jl`.
- [ ] Sweep the consumers. 156 mentions of `ProjectionApiModule` in `source/`,
  `test/`, `example/` and `package/`, and 38 documents.

| case | count | change |
| --- | ---: | --- |
| uses the contract and `ProjectionModule` | 24 | delete the `using` line |
| uses the contract alone | 20 | rename the `using` |
| an extension import | 40 | rename the module in the `import` |
| a package root binds the name | 19 | delete the `const` line |
| a qualified call `ProjectionApiModule.print_document` | 8 files | rename the qualifier |

## Stage 2 — the reference step and the template engine move in

- [ ] `ProjectionReferenceStep.jl` and `ProjectionTemplate.jl` become fragments.
  Their headers fold into `ProjectionModule.jl`.
- [ ] `DomainModule` takes
  `import ..ProjectionModule: normalize_named_node_reference`.
- [ ] Delete the `using ..ProjectionReferenceStepModule` and
  `using ..ProjectionTemplateModule` lines from the 18 modules that already name
  another projection module.
- [ ] The 8 files with a qualified `ProjectionApiModule.print_document` inside a
  macro expansion take the new qualifier.

## Stage 3 — the DSL words leave the export list

Today `@projection_template` escapes the builder wholesale — `$(esc(builder))` —
so `bound`, `project`, `collection`, `tokens` and `sections` resolve in the
caller's module and must be exported.

- [ ] The macro walks the builder and rewrites those five call heads to
  `ProjectionModule.bound(…)` and so on. It already does this for
  `print_document`, and the comment there gives the reason: an unqualified name
  resolved in the caller's module silently defined a dead local one.
- [ ] Delete the five from the export list. 28 exports become 23.
- [ ] Prove it by breaking it: a template body in a module that does not name
  `ProjectionModule` must still build.

Stage 3 is last because it is the only stage that changes a macro, and because
after stages 1 and 2 the words are the last namespace cost left.

## Stage 4 — open: the remaining three

`PrinterContextModule`, `ChildrenContainerModule` and
`ProjectionGestureBindingsModule` would make the layer one module, which is what
eleven of the seventeen kernel layers already are.

The measurement says it is nearly free: `PrinterContext` and `GestureBindings`
are **never** used without the contract, and `ChildrenContainer` is used alone by
one file. But this plan does not decide it. Decide it after stage 3, when the
merged module's real size is on the table.

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
