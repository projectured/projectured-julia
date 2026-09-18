# Adaptagrams

> **Kind:** reference · **Status:** current · **Stands on:** [graph-layout.md](../graph/graph-layout.md)

The native graph layout engine: `AdaptagramsLayout`, a `GraphLayoutEngine`
that places vertices with libcola (constraint-based force-directed layout)
and routes edges with libavoid (obstacle-avoiding connectors), reached
through a small `extern "C"` shim via `ccall`. It is the one engine of
[graph-layout.md](../graph/graph-layout.md) with a native dependency, which
is why it lives in its own package rather than in `ProjecturedGraph`.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/adaptagrams/Adaptagrams.jl` | `AdaptagramsLayout`, the shim `ccall`s, and the fallback to a pure-Julia engine when the shim is not built |

`deps/adaptagrams_shim.cpp` and `deps/build.jl`, under
`package/ProjecturedAdaptagrams/`, are the native shim and its build script;
they are not part of `source/`.

## `AdaptagramsLayout`

```julia
AdaptagramsLayout(; ideal_length=60.0, avoid_overlaps=true, orthogonal=false,
                   node_margin=nothing)
```

`ideal_length` is the size-independent base gap between connected boxes; the
effective ideal edge length libcola uses is computed per edge as
`ideal_length` plus each endpoint's half-extent, so large card-sized nodes
spread apart in proportion to their size. `avoid_overlaps` asks libcola for a
hard overlap guarantee rather than a soft force term. `orthogonal` asks
libavoid for orthogonal routes instead of poly-lines. `node_margin` is the
hard minimum gap kept on each side of every node; left `nothing`, it is
derived from the mean node size instead of a fixed pixel value, the same
reasoning `ideal_length` follows.

`layout_graph` returns the same `(positions, routes)` shape every engine of
[graph-layout.md](../graph/graph-layout.md) returns.
`get_supported_constraint_kinds` answers `(:pin, :fixed_size)`; a pin is
imposed after the native run rather than fed into libcola, since the shim's
`adaptagrams_layout` call takes no constraint argument.

## Building the shim, and the fallback

```julia
using Pkg; Pkg.build("ProjecturedAdaptagrams")
```

builds the shim against an installed or built Adaptagrams checkout — point
`ADAPTAGRAMS_DIR` at its `cola/` directory, or put its `.pc` files on
`PKG_CONFIG_PATH`. `isavailable()` re-checks the filesystem on every call, so
a shim built during a session is picked up with no restart. Until it is
built, `AdaptagramsLayout` loads normally: `effective_engine` warns once per
session and hands each layout to the pure-Julia engine that would have drawn
it, and `layout_engine_name` reports whichever engine really ran, so the
substitution is visible rather than silent.

## How it fits

Loading `ProjecturedAdaptagrams` is the whole opt-in: its `__init__` calls
`register_layout_engine!`, so any caller of `make_deferred_layout_engine()` —
an example, a pane tab, a live diagram — gets native placement from
the moment the package is in the session, with nothing else rewired. Nothing
under `source/graph/` depends on this package; the dependency runs the other
way, from `ProjecturedAdaptagrams` to `ProjecturedGraph`'s
`GraphLayoutEngine` interface.

## What a reader must know before changing this

There is no `test/adaptagrams/`; `example/adaptagrams/GraphProjectionExample.jl`
is the example that exercises the engine, and it draws with the pure-Julia
fallback on a checkout where the shim is not built. A change to the shim's
C ABI (`adaptagrams_shim.cpp`) must keep the `ccall` signatures in
`Adaptagrams.jl` in step, since a mismatch fails at the call, not at compile
time.
