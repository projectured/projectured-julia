# Collect markers when the parser makes them, not by searching for them afterwards

## The problem

`resolve_stubs!` finds the markers of a freshly loaded document by walking that
document with `search_documents`. The walk descends every field of every object
it meets, so it leaves the document through the stub's own load context:

```
MarkdownFile .content   -> MarkdownRoot
MarkdownRoot .elements  -> CellVector
CellVector   .6         -> ReferenceStub
ReferenceStub .context  -> LoaderContext
LoaderContext .intern   -> Dict
Dict .realize(file("demo.json")) -> CatalogShell
CatalogShell .editor    -> Editor            <- the live editor
```

Measured on the first click of "The simplest model" in `run_demo()`, with an
SDL editor attached and every package precompiled:

| step | time | compilation |
| --- | ---: | ---: |
| read the file, parse the markdown | 0.02 s | 96% |
| `resolve_stubs!` | 12.2 s | 98.9% |
| attach the watch | 0.06 s | 99% |
| `print!` | 0.61 s | 95% |

The walk visits 18568 objects of 480 types to find 4 markers. The page's own
share is 1092 objects of 26 types. The rest is the editor: the screen, the SDL
backend, 531 `GraphicsCanvas` nodes from the last frame, and Julia's own type
objects (1192 `TypeVar`, 1239 `DataType`).

`_walk_document!` instantiates once per child type, so 480 types cost 12 s of
compilation. Two facts follow:

1. The cost is a function of run-time state, not of the document. No precompile
   workload can cover it, because a `GraphicsCanvas` the SDL backend made in the
   previous frame does not exist when the package is built.
2. The same reachable set costs 4.1 s through a plain descent that does not
   specialise per type, so `search_documents` costs three times what the walking
   costs.

## The measured alternatives

Four ways to find the same four markers, each cold, editor attached. All four
end with the same four markers resolved and the same workbench built.

| how the markers are found | first page | second page |
| --- | ---: | ---: |
| today: `search_documents` | 12.33 s | 0.53 s |
| a plain descent, escape still open | 4.06 s | 0.46 s |
| a plain descent that skips `ReferenceStub.context` | 1.16 s | 0.38 s |
| the list handed over, no search | 1.12 s | 0.38 s |

The floor, from a session in which all 42 catalog pages were opened in turn:
parse, resolve and print together cost 6 ms to 100 ms per page once the code is
compiled.

## The design

The parser makes every stub. Five loaders call `ReferenceStub(src, ctx)`:
markdown (block and inline), json, julia, xml and rst. Every one already holds
the context. So the constructor is the collection point, and no loader changes.

`_load_into_context` is the only caller of `populate_file!`, so it is what marks
which file is being populated:

1. `LoaderContext` gains three fields:
   - `stubs` — the file document to the list of stubs its parse made.
   - `minting` — the list being filled, or `nothing` outside a parse.
   - `sink` — a drain worklist to also append to, or `nothing`.
2. `ReferenceStub(source, ctx)` pushes itself onto `ctx.minting` when it is set.
3. `_load_into_context` sets `minting` around `populate_file!`, saves and
   restores the previous value (a `$doctype` loader can start a nested load in
   the middle of a parse), files the list under the document, and appends it to
   `sink` when a drain is running.
4. `resolve_stubs!(root; context)` drains a worklist seeded from
   `context.stubs[root]`. It sets `context.sink` to that worklist for the whole
   drain, so a file loaded by a marker adds its own markers as it is parsed.
   This is the recursion: at every depth the parser reports, and nothing
   searches.
5. `resolve_stubs!(root)` without a context keeps the walk. A stub built by hand
   has no context and no registry, which is what the serializer tests and
   `Precompile.jl` use.

### What changes in behaviour

The fast path resolves the markers the parse made, in the order they were made.
The walk resolves the markers reachable through the object graph. Two
differences, both of them intended:

- The walk reaches other documents in the same session through
  `LoaderContext.intern`, so `resolve_stubs!(pageA)` today also resolves markers
  in an unrelated page B that the session loaded lazily. The fast path does not.
  This restores the laziness that `load_project` documents.
- A marker that returns part of a file (`definition(file(f), name)`) makes the
  fast path resolve every marker in `f`, not only those under the returned node.
  The widening is bounded by the files a resolution actually loads.

## Steps

- [x] 1. Create the worktree and the plan.
- [x] 2. `LoaderContext`: the three fields, with the one-argument constructor
      unchanged.
- [x] 3. `ReferenceStub(source, ctx)`: register with the context.
- [x] 4. `_load_into_context`: mark the file being populated, file the list,
      feed the sink.
- [x] 5. `resolve_stubs!`: the worklist drain, with the walk as the fallback.
- [ ] 6. Tests in `package/base/test/serialization/`.
- [ ] 7. The two call sites in omnetpp-julia's `CatalogShell` pass the session.
- [ ] 8. Measure the click again.

## Result

To be filled in when step 8 runs.

## Follow-up, not in this plan

- A `@compile_workload` that opens one catalog page, so the remaining ~1.1 s is
  paid at build time. See `plan/pending/precompile-workloads.md`.
- `search_documents` costs three times a plain descent over the same objects,
  because `_walk_document!` instantiates per child type. Every other hot path
  that walks pays this too. `DocumentWalk.jl` is sealed, so that is a separate
  conversation.
