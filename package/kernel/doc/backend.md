# The backend layer

Layer 6 of the kernel — **rendering targets**. Independent sibling of the
device layer; the two abstractions only come together in a concrete
implementation. The layer carries the abstract `Backend` type, the batch
generics, the display-size seam, and the dependency-free `HeadlessBackend`
that CI and documentation examples run against.

The layer lives in [src/backend/](../src/backend/):

```
Backend.jl          (BackendModule)         — Backend abstract + generics + make_backend factory
Display.jl          (DisplayModule)         — display-size query + provider indirection
HeadlessBackend.jl  (HeadlessBackendModule) — dependency-free in-memory backend + scripted event source
```

## BackendModule

Declares `Backend <: Any` and the batch generics `initialize_backend!`,
`quit_backend!`, `measure_text`, `write_image`, `record_video`,
`render_canvas`, `decode_image`, `get_pointer_position`, plus the
`make_backend(kind::Symbol; kwargs...)` factory seam. Concrete backends
(SDL, Web, PDF, Console, …) live in opt-in packages that add methods for
their own `::MyBackend` type and register `make_backend(::Val{kind})`.

No document is imported here. The batch I/O generics are duck-typed on the
`document` argument, so the layer stays document-free at layer 6.

## DisplayModule

Display-size query with a process-global provider indirection. The SDL
backend registers a provider; without one, a fixed SDL-free default is
returned so headless callers still get a sensible size. Belongs in the
backend layer — displays are what backends render to.

## HeadlessBackendModule

A dependency-free in-memory backend with a scripted event source:

- `HeadlessBackend()` records every `write_to_devices` call into `rendered`
  (log for later assertion) and pops events from a scripted queue on every
  `read_from_devices` call.
- `make_backend(:headless)` returns a fresh instance — the factory
  registration that lets kernel editor tests reach for the backend by name
  without depending on any concrete backend package.
- `push_event!(backend, event)` enqueues an event for the next
  `read_from_devices` call.
- `measure_text` returns a fixed `(8 * length, 16)` metric — sufficient for
  layout tests that only care about relative sizes.

The backend is deliberately **document-agnostic** — it uses only the
abstract `Document` type (opaque payload) and the device I/O generics; no
concrete document is imported. That is the pressure that keeps
`backend/` layer-6 clean.

## Downward edges

- `..DeviceModule: Device, read_from_devices, write_to_devices` (only
  HeadlessBackend needs this; the abstract generics don't).

That is the whole import surface. No document, reference, operation,
projection, agent, or editor.
