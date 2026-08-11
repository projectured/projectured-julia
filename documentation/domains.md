# The domain packages

Contributor guide to the twenty packages that hold ProjecturEd's concrete
source domains: what a domain package contains, how they depend on each other,
and how to add one. For the whole-system picture see
[architecture.md](architecture.md).

## Per-domain guides

A domain with a reference guide keeps it in its own package:

- [json.md](../package/json/doc/json.md) — the JSON domain
- [xml.md](../package/xml/doc/xml.md) — the XML domain
- [rst.md](../package/rst/doc/rst.md) — the reStructuredText domain
- [math.md](../package/math/doc/math.md) — the mathematical notation domain
- [chart.md](../package/chart/doc/chart.md) — the chart domain
- [sequencechart.md](../package/sequencechart/doc/sequencechart.md) — the sequence chart domain
- [fsm.md](../package/fsm/doc/fsm.md) — the state machine domain
- [process.md](../package/process/doc/process.md) — the process domain
- [workbench.md](../package/workbench/doc/workbench.md) — the workbench application

## What a domain package is

One package holds one domain. A domain is a kind of content a person edits —
JSON, SQL, a state machine, a chart — and the package holds everything that is
true of that content and nothing else:

- the **documents**, the types the content is made of;
- the **parser**, if the domain has a text form;
- the **projections** that render and edit it: `*ToSyntax` for a notation,
  `*ToWidget` or `*ToGraphics` for something drawn directly;
- the **file wrapper**, if the domain reads and writes a file extension.

Each package is a triad — `package/<name>/{main, test, example}` — plus a
`doc/` where a guide exists. Every package depends on `ProjecturedKernel`, on
the substrate packages it actually imports, and on whichever domains it
embeds. [packages.md](packages.md) has the substrate table.

## The dependency table

Fourteen domains need nothing but the engine. Five build on one layer of
domains. The workbench sits on top.

| Package | Directory | Depends on |
| --- | --- | --- |
| `ProjecturedJson` | `package/json/` | — |
| `ProjecturedYaml` | `package/yaml/` | — |
| `ProjecturedXml` | `package/xml/` | — |
| `ProjecturedMarkdown` | `package/markdown/` | — |
| `ProjecturedRst` | `package/rst/` | — |
| `ProjecturedBook` | `package/book/` | — |
| `ProjecturedMath` | `package/math/` | — |
| `ProjecturedJulia` | `package/julia/` | — |
| `ProjecturedSql` | `package/sql/` | — |
| `ProjecturedDatabase` | `package/database/` | — |
| `ProjecturedFileSystem` | `package/filesystem/` | — |
| `ProjecturedGraph` | `package/graph/` | — |
| `ProjecturedChart` | `package/chart/` | — |
| `ProjecturedSequenceChart` | `package/sequencechart/` | — |
| `ProjecturedDbCatalog` | `package/dbcatalog/` | Sql |
| `ProjecturedFormula` | `package/formula/` | Julia |
| `ProjecturedFsm` | `package/fsm/` | Julia, Graph |
| `ProjecturedProcess` | `package/process/` | Julia, Graph |
| `ProjecturedConversation` | `package/conversation/` | Json, Julia, Xml |
| `ProjecturedWorkbench` | `package/workbench/` | Conversation, FileSystem, Json, Julia, Markdown, Xml, Yaml |

Every edge in the right column is a domain embedding another domain's content:
a state machine guard is a Julia expression, a catalog query produces a SQL
statement, the workbench opens documents of every kind.

## What is NOT a domain package

Three kinds of thing look like a domain and are not. Each lives in a substrate
package, below every domain:

- **A framework several domains share.** The insert-by-typing leaf and the
  `*Nothing` placeholder (`ProjecturedSyntax`), the plot arithmetic and the
  colour and marker cycles (`ProjecturedPlot`). Two domains needing the same
  thing is what makes it a framework.
- **A domain-neutral editor feature.** The gesture help map and the command
  palette (`ProjecturedGestureHelp`), the gesture log
  (`ProjecturedGestureLog`). They render a *projection*, not a content kind.
- **The render-anything projection.** `NaturalToGraphics`
  (`ProjecturedNaturalProjection`) draws any document, so it cannot name any
  domain. Both its tables come from `NaturalRegistryModule`, and each domain
  registers its own row.

## The root module

A domain package's root module binds the submodules of the packages below it
with one mechanical loop rather than a written alias table, so a source file
names a module exactly as the module names itself:

```julia
module ProjecturedFsm

using ProjecturedKernel, ProjecturedCollection, ProjecturedDomain
using ProjecturedFileFormat, ProjecturedProjection, ProjecturedStyle
using ProjecturedSyntax, ProjecturedText
using ProjecturedJulia, ProjecturedGraph

for _src in (ProjecturedKernel, ProjecturedCollection, ProjecturedDomain,
             ProjecturedFileFormat, ProjecturedProjection, ProjecturedStyle,
             ProjecturedSyntax, ProjecturedText,
             ProjecturedJulia, ProjecturedGraph)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Fsm.jl")
…
end
```

The `parentmodule` guard stops a package's re-exported aliases of a lower
package being bound twice. Because the aliases are written by a loop rather
than as `const` lines, the static layering guard cannot read them off the file:
the test package measures the set from the loaded package and passes it as
`extra_aliases`.

## Adding a domain

1. Create `package/<name>/main/` with a `Project.toml` (fresh UUID, deps on the
   three engine packages plus any domain it embeds) and a root module as above.
2. Write the documents, the parser and the projections.
3. Register the domain with the render-anything projection, in the `*ToSyntax.jl`
   file you already have:

   ```julia
   import ..NaturalRegistryModule: register_natural_syntax!
   function __init__()
       register_natural_syntax!(:mydomain,
           () -> Pair{Type,Any}[MyDocument => MyToSyntax()])
   end
   ```

   A domain that draws itself rather than going through the syntax tail uses
   `register_natural_graphics!` instead; its factory takes `measure`.
4. If the domain has a text form, register `natural_syntax_projection`,
   `natural_extension` and `parse_natural` on `NaturalFormatModule` the same way.
5. Add the package to `Projectured`'s `import` list and `_SOURCES` tuple. That
   tuple is the one place the full set is written down.
6. Add `package/<name>/example/` and `package/<name>/test/`, and add the test
   package to `ProjecturedTest`.
7. Add all three to the root `Project.toml` `[deps]` and `[sources]`, then run
   `Pkg.resolve()`.

## Where a cross-domain thing goes

An example or a test whose fixture names several domains does not belong to any
of them. It goes to the umbrella — `ProjecturedExample` or `ProjecturedTest`.
That is why the registry of examples, the gallery, the file editor, and suites
like `ConstructTest` (JSON, YAML and XML) live there rather than in a domain.
