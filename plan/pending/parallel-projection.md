# Parallel Projection

A higher-order projection that runs multiple projections in parallel on the same input and combines their outputs into a tuple. Enables simultaneous access to multiple views of a single document without creating new document types.

## Design Concepts

### Motivation

Some use cases require multiple independent views of the same document simultaneously:

- **DbCatalogTable**: Need both column metadata (`DbCatalogTableToChildren`) and tabular data (`DbCatalogTableToTabularGrid`)
- **Document analysis**: Need syntax tree, text representation, and graphics view together
- **Multi-format export**: Generate JSON, XML, and YAML from the same source document

Current options:
1. **SequentialProjection**: Chains outputs (A→B→C), not parallel combination
2. **AlternativeProjection**: Selects one branch by index, not multiple simultaneously
3. **New document type**: Create composite document (adds complexity, requires new types)

`ParallelProjection` fills this gap by running projections in parallel and returning a tuple of outputs.

### Relationship to existing higher-order projections

| Projection | Input → Output | Pattern |
|---|---|---|
| `SequentialProjection` | input → (p₁ → p₂ → … → pₙ) → output | Chain: each step feeds the next |
| `AlternativeProjection` | input → (p₁, p₂, …, pₙ) → output[i] | Select: one branch by index |
| `ParallelProjection` | input → (p₁, p₂, …, pₙ) → (output₁, output₂, …, outputₙ) | Parallel: all branches simultaneously |

### Key design decisions

1. **Tuple output**: Simple, no new document type needed. Users destructure: `columns, grid = iomap.output`
2. **Shared input**: All projections receive the same input document
3. **Independent execution**: Each projection runs independently, all outputs are reactive
4. **Reader dispatch**: Try each projection's reader in order, first handler wins
5. **Reference mapping**: Returns `nothing` by default (can be enhanced to route to specific sub-projection)

### Reactive behavior

Since each projection produces reactive cells (via `CellVector`, `Cell`, etc.), the tuple output is fully reactive:

```julia
parallel = ParallelProjection(p1, p2, p3)
iomap = projection_print(parallel, input)
output1, output2, output3 = iomap.output

# When input changes, all three outputs recompute automatically
# Each output maintains its own dependency graph
```

## Specification

### File: `program/src/projection/higherorder/Parallel.jl`

```julia
"""
    ParallelProjectionModule

Runs multiple projections in parallel on the same input and combines their
outputs into a tuple. Useful when you need multiple views of the same document
simultaneously (e.g., column metadata + tabular data).
"""
module ParallelProjectionModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
export ParallelProjection, ParallelProjectionIoMap

struct ParallelProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Tuple  # Tuple of outputs from each projection
    step_iomaps::Vector{Any}  # IoMaps from each parallel projection
end

"""
    ParallelProjection(projections...)

A compound higher-order projection that applies multiple projections to the
same input in parallel and returns their outputs as a tuple.

Given projections `[p₁, p₂, …, pₙ]`, calling `projection_print` produces:

    input → (p₁, p₂, …, pₙ) → (output₁, output₂, …, outputₙ)

Each projection runs independently, so all outputs are reactive and will
update when the input changes.

# Example

    parallel = ParallelProjection(
        DbCatalogTableToChildren(),
        DbCatalogTableToTabularGrid()
    )
    iomap = projection_print(parallel, db_catalog_table)
    # iomap.output = (CellVector{DbCatalogColumn}, TabularGrid)
"""
struct ParallelProjection <: Projection
    projections::Vector{Any}
    ParallelProjection(projections::Vector{Any}) = new(projections)
end

ParallelProjection(ps...) = ParallelProjection(collect(Any, ps))

"""
    projection_print(parallel::ParallelProjection, input, recursion, ctx) -> ParallelProjectionIoMap

Apply each projection to the same input, collecting all outputs into a tuple.
"""
function projection_print(parallel::ParallelProjection, input, recursion, ctx)
    step_iomaps = Any[]
    outputs = Any[]
    for p in parallel.projections
        iomap = projection_print(p, input, recursion, ctx)
        push!(step_iomaps, iomap)
        push!(outputs, iomap.output)
    end
    return ParallelProjectionIoMap(parallel, input, Tuple(outputs), step_iomaps)
end

"""
    projection_read(parallel::ParallelProjection, iomap::ParallelProjectionIoMap, event)

Try each parallel projection's reader in order until one handles the event.
Returns the translated operation in the input domain.
"""
function projection_read(parallel::ParallelProjection, iomap::ParallelProjectionIoMap, event)
    for (i, p) in enumerate(parallel.projections)
        op = projection_read(p, iomap.step_iomaps[i], event)
        op !== nothing && return op
    end
    return nothing
end

function map_reference_forward(::ParallelProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::ParallelProjection, iomap, reference)
    return nothing
end

end # module
```

## Use Cases

### DbCatalogTable: Column metadata + Tabular data

```julia
parallel = ParallelProjection(
    DbCatalogTableToChildren(),      # → CellVector{DbCatalogColumn}
    DbCatalogTableToTabularGrid()   # → TabularGrid
)

iomap = projection_print(parallel, db_catalog_table)
columns, grid = iomap.output

# columns: CellVector{DbCatalogColumn} (metadata)
# grid: TabularGrid (data rows)
```

### Document analysis: Syntax + Text + Graphics

```julia
parallel = ParallelProjection(
    JsonToSyntax(),
    JsonToText(),
    JsonToGraphics()
)

iomap = projection_print(parallel, json_doc)
syntax, text, graphics = iomap.output
```

### Multi-format export

```julia
parallel = ParallelProjection(
    JsonToSyntax(),
    JsonToXml(),
    JsonToYaml()
)

iomap = projection_print(parallel, json_doc)
syntax, xml, yaml = iomap.output
```

## Implementation Steps

1. Create `program/src/projection/higherorder/Parallel.jl` with the implementation above
2. Add to `program/src/Projectured.jl`:
   - `include("projection/higherorder/Parallel.jl")`
   - Export `ParallelProjection`, `ParallelProjectionIoMap`
3. Add tests in `test/src/projection/ParallelTest.jl`:
   - Test with two simple projections (e.g., `PrimitiveStringToText` + `PrimitiveStringToSyntax`)
   - Test reactive behavior (change input, verify all outputs update)
   - Test `projection_read` dispatch (event handled by first responding projection)
   - Test with DbCatalog projections (columns + grid)
4. Update guide documentation:
   - Add to `guide/higher-order-projections.md`
   - Add row to `guide/projection-system.md` table

## Future Extensions

1. **Named outputs**: Use `NamedTuple` instead of `Tuple` for clearer access:
   ```julia
   ParallelProjection(columns=DbCatalogTableToChildren(), data=DbCatalogTableToTabularGrid())
   # iomap.output = (columns=..., data=...)
   ```

2. **Reference routing**: Enhance `map_reference_forward/backward` to route references to specific sub-projections based on a selector (e.g., index or name)

3. **Selective re-computation**: Add a mode where only projections whose outputs are actually consumed are re-computed (optimization for expensive projections)

4. **Error handling**: Add options for how to handle failures in individual projections (fail-fast, continue with `nothing`, collect all errors)
