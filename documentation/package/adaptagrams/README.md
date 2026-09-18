# ProjecturedAdaptagrams

> **Kind:** reference · **Status:** current · **Stands on:** [graph-layout.md](../graph/graph-layout.md), [package-rules.md](../../rule/package-rules.md)

The native graph-layout engine for ProjecturEd. Provides `AdaptagramsLayout`, a
`GraphLayoutEngine` (see `ProjecturedGraph`) that places vertices with
**libcola** and routes edges with **libavoid** from the
[Adaptagrams](https://github.com/mjwybrow/adaptagrams) C++ libraries, bridged
through a small `extern "C"` shim (`deps/adaptagrams_shim.cpp`) called via `ccall`.

It is a **separate package** from `ProjecturedGraph` on purpose: it carries an
external native dependency that core ProjecturEd must not require. The interface
(`GraphLayoutEngine`, `layout_graph`) and the pure-Julia default
(`GridEmbedding`) live in `ProjecturedGraph`; this package only adds the
`AdaptagramsLayout` method behind the same seam.

## 1. Install Adaptagrams (native)

There is no apt package or Julia JLL; build it from source. From the cola/
directory of a checkout:

```bash
sudo apt install build-essential autoconf automake libtool pkg-config
cd ~/workspace/adaptagrams/cola
./autogen.sh && ./configure && make
sudo make install && sudo ldconfig    # optional; or use it in-tree
```

## 2. Build the shim

```julia
using Pkg
Pkg.build("ProjecturedAdaptagrams")
```

`deps/build.jl` finds Adaptagrams via, in order:

1. **pkg-config** — `pkg-config --exists libcola libavoid libvpsc` (works after
   `make install` with the `.pc` files on `PKG_CONFIG_PATH`).
2. **`ADAPTAGRAMS_DIR`** — the `cola/` directory of a checkout (contains
   `libavoid/ libcola/ libvpsc/`). Defaults to `~/workspace/adaptagrams/cola`.
   Used in-tree (links against each `*/.libs`) — no install needed.

It compiles `deps/libadaptagrams_shim.<ext>` — a fixed path the module loads
directly (no generated `deps.jl`). The build never throws: if Adaptagrams is
missing or the compile fails it warns and removes any stale shim, and
`AdaptagramsLayout` then errors at call time with this guidance —
`GridEmbedding` stays available throughout. Availability is a runtime
check, so building the shim is picked up without a stale precompile cache.

> **API drift:** a few libcola/libvpsc/libavoid calls have shifted spelling
> across Adaptagrams revisions. The calls flagged `VERIFY` in
> `adaptagrams_shim.cpp` are the ones to check against the installed headers if
> the compile fails; the C ABI exposed to Julia does not change.

## 3. Use

```julia
using ProjecturedExample, ProjecturedAdaptagrams
proj = make_graph_projection_example(engine = AdaptagramsLayout())
# AdaptagramsLayout(; ideal_length=60.0, avoid_overlaps=true, orthogonal=false, node_margin=nothing)
```
