# The domain packages

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](system-anatomy.md), [package-rules.md](../rule/package-rules.md), [domain-anatomy.md](domain-anatomy.md)

This document lists the twenty packages that hold the source domains of ProjecturEd, says how they depend on each other, and where the document of each one is. [domain-anatomy.md](domain-anatomy.md) describes the parts that every domain has, and [new-domain-guide.md](../guide/new-domain-guide.md) is the procedure to add one.

## The domain documents

Each domain has one design document in the folder of its slice. Read [domain-anatomy.md](domain-anatomy.md) first: each domain document describes only how its domain differs from that shape.

| Domain | Document |
| --- | --- |
| JSON | [json.md](../package/json/json.md) |
| YAML | [yaml.md](../package/yaml/yaml.md) |
| XML | [xml.md](../package/xml/xml.md) |
| Markdown | [markdown.md](../package/markdown/markdown.md) |
| reStructuredText | [rst.md](../package/rst/rst.md) |
| Book | [book.md](../package/book/book.md) |
| Math notation | [math.md](../package/math/math.md) |
| Julia code | [julia.md](../package/julia/julia.md) |
| Formula | [formula.md](../package/formula/formula.md) |
| SQL | [sql.md](../package/sql/sql.md) |
| Database and catalog | [database.md](../package/database/database.md), for `ProjecturedDatabase`, `ProjecturedDbCatalog` and the opt-in `ProjecturedOdbc` |
| File system | [filesystem.md](../package/filesystem/filesystem.md) |
| Graph | [graph.md](../package/graph/graph.md), with [graph-layout.md](../package/graph/graph-layout.md) for the layout engines |
| Chart | [chart.md](../package/chart/chart.md) |
| Sequence chart | [sequencechart.md](../package/sequencechart/sequencechart.md) |
| State machine | [fsm.md](../package/fsm/fsm.md) |
| Process | [process.md](../package/process/process.md) |
| Conversation | [conversation.md](../package/conversation/conversation.md), with [transcript.md](../package/conversation/transcript.md) for the widget view |
| Assistant | [assistant.md](../package/assistant/assistant.md) |

## What a domain package is

One package holds one domain. A domain is a kind of content a person edits, such as JSON, SQL, a state machine or a chart. The package holds everything that is true of that content and nothing else:

- the **documents**, the types the content is made of;
- the **parser**, if the domain has a text form;
- the **projections** that render and edit it: `*ToSyntax` for a notation, `*ToWidget` or `*ToGraphics` for something drawn directly;
- the **file type**, if the domain reads and writes a file extension.

Each domain is a triad of sibling packages: `package/Projectured<Name>/`, `package/Projectured<Name>Example/` and `package/Projectured<Name>Test/`, each with its own `Project.toml`. The code is in `source/<name>/`, the examples in `example/<name>/`, and the tests in `test/<name>/`. A domain package depends on `ProjecturedKernel`, on the substrate packages that it imports, and on the domains that it embeds. [package-rules.md](../rule/package-rules.md) has the table of the substrate.

## The dependency table

Fifteen domains depend on no other domain. Four build on one layer of domains, and the assistant builds on the conversation domain.

| Package | Code | Depends on |
| --- | --- | --- |
| `ProjecturedJson` | `source/json/` | — |
| `ProjecturedYaml` | `source/yaml/` | — |
| `ProjecturedXml` | `source/xml/` | — |
| `ProjecturedMarkdown` | `source/markdown/` | — |
| `ProjecturedRst` | `source/rst/` | — |
| `ProjecturedBook` | `source/book/` | — |
| `ProjecturedMath` | `source/math/` | — |
| `ProjecturedJulia` | `source/julia/` | — |
| `ProjecturedSql` | `source/sql/` | — |
| `ProjecturedDatabase` | `source/database/` | — |
| `ProjecturedFileSystem` | `source/filesystem/` | — |
| `ProjecturedGraph` | `source/graph/` | — |
| `ProjecturedChart` | `source/chart/` | — |
| `ProjecturedSequenceChart` | `source/sequencechart/` | — |
| `ProjecturedConversation` | `source/conversation/` | — |
| `ProjecturedDbCatalog` | `source/dbcatalog/` | Sql |
| `ProjecturedFormula` | `source/formula/` | Julia, Math |
| `ProjecturedFsm` | `source/fsm/` | Julia, Graph |
| `ProjecturedProcess` | `source/process/` | Julia, Graph |
| `ProjecturedAssistant` | `source/assistant/` | Conversation |

Each edge exists because one domain holds or makes the documents of another. A state machine guard is a Julia expression, and its diagram is a graph. A catalog prints as SQL statements. The code of a formula is a Julia tree or a math tree. A conversation part parses to JSON, Julia or XML through the natural registry, so the conversation package needs no dependency on those domains.

## What is NOT a domain package

Three kinds of thing look like a domain and are not. Each lives in a substrate package, below every domain:

- **A framework several domains share.** The insert-by-typing leaf and the `*Nothing` placeholder (`ProjecturedSyntax`), the plot arithmetic and the colour and marker cycles (`ProjecturedPlot`). Two domains needing the same thing is what makes it a framework.
- **A domain-neutral editor feature.** The gesture help map and the command palette (`ProjecturedGestureHelp`), the gesture log (`ProjecturedGestureLog`), the fault barrier and its log panel (`ProjecturedFault`). They render a *projection*, not a content kind.
- **The render-anything projection.** `NaturalToGraphics` (`ProjecturedNatural`) draws any document, so it can not name any domain. Each domain registers its own row; see [natural.md](../package/natural/natural.md).

## The root module

A domain package's root module binds the submodules of the packages below it with one loop rather than a written alias table, so a source file names a module exactly as the module names itself. This is the root of `ProjecturedFsm`, shortened:

```julia
module ProjecturedFsm

using ProjecturedCollection, ProjecturedDomain, ProjecturedFileFormat
using ProjecturedNatural, ProjecturedGraph, ProjecturedJulia, ProjecturedKernel
using ProjecturedProjection, ProjecturedStyle, ProjecturedSyntax, ProjecturedText

for _src in (ProjecturedCollection, ProjecturedDomain, ProjecturedFileFormat, ProjecturedGraph,
             ProjecturedNatural, ProjecturedJulia, ProjecturedKernel, ProjecturedProjection,
             ProjecturedStyle, ProjecturedSyntax, ProjecturedText)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/fsm/FsmModule.jl")
…
end
```

The loop binds every submodule that a package defines, and every submodule that it re-aliases from a package below it. Because the aliases are written by a loop rather than as `const` lines, the static layering guard can not read them off the file: the test package measures the set from the loaded package and passes it as `extra_aliases`.

## Adding a domain

[new-domain-guide.md](../guide/new-domain-guide.md) walks through one example from the first document type to the test. In short:

1. Create the three packages `package/Projectured<Name>/`, `…Example/` and `…Test/`, each with a `Project.toml` and a root module as above. Put the code in `source/<name>/`.
2. Write the documents, the parser and the projections; [domain-anatomy.md](domain-anatomy.md) lists the parts.
3. In the `__init__` of the module, register the natural notation with `register_natural_domain!`, and the file type with `register_file_document_type!`.
4. Add the package to the `import` list and the `_SOURCES` tuple of `Projectured`, in `source/projectured/Projectured.jl`. That tuple is the one place the full set is written down.
5. Add the test package to `ProjecturedTest`.
6. Add the three packages to `[deps]` and `[sources]` of `environment/all/Project.toml`, then run `Pkg.resolve()`.

## Where a cross-domain thing goes

An example or a test whose fixture names several domains does not belong to any of them. It goes to the umbrella: `ProjecturedExample` or `ProjecturedTest`. That is why the registry of examples, the gallery, the file editor, and suites like `ConstructTest` (JSON, YAML and XML) live there rather than in a domain.
