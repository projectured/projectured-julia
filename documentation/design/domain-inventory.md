# The domain packages

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](system-anatomy.md), [package-rules.md](../rule/package-rules.md), [domain-anatomy.md](domain-anatomy.md)

This document lists the eighteen packages that hold the source domains of ProjecturEd, says how they depend on each other, and where the document of each one is. [domain-anatomy.md](domain-anatomy.md) describes the parts that every domain has, and [new-domain-guide.md](../guide/new-domain-guide.md) is the procedure to add one.

## The domain documents

Each domain has one design document in the folder of its slice. Read [domain-anatomy.md](domain-anatomy.md) first: each domain document describes only how its domain differs from that shape.

| Domain | Document |
| --- | --- |
| JSON | [json.md](../package/domain/json/json.md) |
| YAML | [yaml.md](../package/domain/yaml/yaml.md) |
| XML | [xml.md](../package/domain/xml/xml.md) |
| Markdown | [markdown.md](../package/domain/markdown/markdown.md) |
| reStructuredText | [rst.md](../package/domain/rst/rst.md) |
| Book | [book.md](../package/domain/book/book.md) |
| Math notation | [math.md](../package/domain/math/math.md) |
| Julia code | [julia.md](../package/domain/julia/julia.md) |
| Formula | [formula.md](../package/domain/formula/formula.md) |
| SQL | [sql.md](../package/domain/sql/sql.md) |
| Database and catalog | [database.md](../package/domain/database/database.md), for `ProjecturedDatabase` and `ProjecturedDBCatalog`, and [odbc.md](../package/adapter/odbc/odbc.md), for the opt-in `ProjecturedODBC` |
| File system | [filesystem.md](../package/platform/filesystem/filesystem.md) |
| Graph | [graph.md](../package/domain/graph/graph.md), with [graph-layout.md](../package/domain/graph/graph-layout.md) for the layout engines |
| Chart | [chart.md](../package/domain/chart/chart.md) |
| Sequence chart | [sequencechart.md](../package/domain/sequencechart/sequencechart.md) |
| State machine | [fsm.md](../package/domain/fsm/fsm.md) |
| Process | [process.md](../package/domain/process/process.md) |
| Pivot | [pivot.md](../package/domain/pivot/pivot.md) |
| Conversation | [conversation.md](../package/platform/conversation/conversation.md), with [transcript.md](../package/platform/conversation/transcript.md) for the widget view |
| Assistant | [assistant.md](../package/platform/assistant/assistant.md) |

## What a domain package is

One package holds one domain. A domain is a kind of content a person edits, such as JSON, SQL, a state machine or a chart. The package holds everything that is true of that content and nothing else:

- the **documents**, the types the content is made of;
- the **parser**, if the domain has a text form;
- the **projections** that render and edit it: `*ToSyntax` for a notation, `*ToWidget` or `*ToGraphics` for something drawn directly;
- the **file type**, if the domain reads and writes a file extension.

Each domain is a triad of sibling packages: `package/Projectured<Name>/`, `package/Projectured<Name>Example/` and `package/Projectured<Name>Test/`, each with its own `Project.toml`. The code is in `source/<name>/`, the examples in `example/<name>/`, and the tests in `test/<name>/`. A domain package depends on `ProjecturedKernel`, on `ProjecturedPlatform`, and on the domains that it embeds. [package-rules.md](../rule/package-rules.md) has the table of the platform.

## The dependency table

Thirteen domains depend on no other domain. Five build on one layer of domains.

| Package | Code | Depends on |
| --- | --- | --- |
| `ProjecturedJSON` | `source/domain/json/` | — |
| `ProjecturedYAML` | `source/domain/yaml/` | — |
| `ProjecturedXML` | `source/domain/xml/` | — |
| `ProjecturedMarkdown` | `source/domain/markdown/` | — |
| `ProjecturedRST` | `source/domain/rst/` | — |
| `ProjecturedBook` | `source/domain/book/` | — |
| `ProjecturedMath` | `source/domain/math/` | — |
| `ProjecturedJulia` | `source/domain/julia/` | — |
| `ProjecturedSQL` | `source/domain/sql/` | — |
| `ProjecturedDatabase` | `source/domain/database/` | — |
| `ProjecturedGraph` | `source/domain/graph/` | — |
| `ProjecturedChart` | `source/domain/chart/` | — |
| `ProjecturedSequenceChart` | `source/domain/sequencechart/` | — |
| `ProjecturedDBCatalog` | `source/domain/dbcatalog/` | Sql |
| `ProjecturedFormula` | `source/domain/formula/` | Julia, Math |
| `ProjecturedFSM` | `source/domain/fsm/` | Julia, Graph |
| `ProjecturedProcess` | `source/domain/process/` | Julia, Graph |
| `ProjecturedPivot` | `source/domain/pivot/` | Chart |

Each edge exists because one domain holds or makes the documents of another. A state machine guard is a Julia expression, and its diagram is a graph. A catalog prints as SQL statements. The code of a formula is a Julia tree or a math tree. A cell of a pivot holds a chart. The file system, the conversation and the assistant look like domains but are slices of `ProjecturedPlatform`; a conversation part parses to JSON, Julia or XML through the natural registry, so the conversation slice needs no dependency on those domains.

## What is NOT a domain package

Three kinds of thing look like a domain and are not. Each lives in a slice of `ProjecturedPlatform`, below every domain:

- **A framework several domains share.** The insert-by-typing leaf and the `*Nothing` placeholder (the syntax slice), the plot arithmetic and the colour and marker cycles (the plot slice). Two domains needing the same thing is what makes it a framework.
- **A domain-neutral editor feature.** The gesture help map and the command palette (the gesturehelp slice), the gesture log (the gesturelog slice), the fault barrier and its log panel (the fault slice). They render a *projection*, not a content kind.
- **The render-anything projection.** `NaturalToGraphics` (the natural slice) draws any document, so it can not name any domain. Each domain registers its own row; see [natural.md](../package/platform/natural/natural.md).

## The root module

A domain package's root module binds the submodules of the packages below it with one loop rather than a written alias table, so a source file names a module exactly as the module names itself. This is the root of `ProjecturedFSM`, shortened:

```julia
module ProjecturedFSM

using ProjecturedGraph
using ProjecturedJulia
using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedGraph, ProjecturedJulia, ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/domain/fsm/FsmModule.jl")

# The names of the domain at the level of the package, so that `using ProjecturedFSM`
# gives them, as `using ProjecturedPlatform` gives the names of the platform.
using .FsmModule
for _n in names(FsmModule)
    _n === :FsmModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

end # module ProjecturedFSM
```

The loop binds every submodule that a package defines, and every submodule that it re-aliases from a package below it. Because the aliases are written by a loop rather than as `const` lines, the static layering guard can not read them off the file: the test package measures the set from the loaded package and passes it as `extra_aliases`.

The second loop exports the names of the domain module from the package. The umbrella exports only the names of the kernel and the platform, so a user who writes `FsmDiagram` loads `ProjecturedFSM`.

## Adding a domain

[new-domain-guide.md](../guide/new-domain-guide.md) walks through one example from the first document type to the test. In short:

1. Create the three packages `package/Projectured<Name>/`, `…Example/` and `…Test/`, each with a `Project.toml` and a root module as above. Put the code in `source/<name>/`.
2. Write the documents, the parser and the projections; [domain-anatomy.md](domain-anatomy.md) lists the parts.
3. In the `__init__` of the module, register the natural notation with `register_natural_domain!`, and the file type with `register_file_document_type!`.
4. Add the package to the two lists of the full set, which `test_repository()` and `test_builder()` keep equal:
   - `ProjecturedAll`: the `[deps]` and `[sources]` of its `Project.toml`, the `import` list of its root module, and the `_SOURCES` tuple in `source/all/ProjecturedAll.jl`;
   - the binary: `PROJECTURED_APPLICATION_IMPORTS` in `source/tool/builder/ProjecturedProgram.jl`.
5. Declare the table `[auto-integration]` in the domain's `Project.toml`, with the trigger `Projectured` and the default `auto`, so AutoIntegration loads the domain when a session loads `Projectured`; see [autointegration.md](../package/autointegration/autointegration.md).
6. Add the test package to `ProjecturedTest`.
7. Add the three packages to `[deps]` and `[sources]` of `environment/all/Project.toml`, then run `Pkg.resolve()`.

## Where a cross-domain thing goes

An example or a test whose fixture names several domains does not belong to any of them. It goes to the umbrella: `ProjecturedExample` or `ProjecturedTest`. That is why the registry of examples, the gallery, the file editor, and suites like `ConstructTest` (JSON, YAML and XML) live there rather than in a domain.
