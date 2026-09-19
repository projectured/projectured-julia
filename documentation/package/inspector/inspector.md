# Inspector

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [reference.md](../kernel/reference.md)

A window that shows what a reference is and what it points into: the
`ReferenceInspector` document, its rendering as two-section text, and the
probe that follows the mouse and opens one for whatever a click would select.
Nothing here changes a document; the inspector is a read-only view beside it.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/inspector/InspectorModule.jl` | the module, and what it exports |
| `source/inspector/ReferenceInspector.jl` | the `ReferenceInspector` document: a `reference` and the `target` it points into |
| `source/inspector/ReferenceInspectorToText.jl` | `ReferenceInspectorToText`, the projection to a two-section `TextBlock` |
| `source/inspector/HoverProbe.jl` | `HoverProbeProjection`, the wrapper that opens the inspector on idle mouse motion |

## The document and its rendering

`ReferenceInspector(; reference = nothing, target = nothing)` pairs a
`Reference` with the document it is read against. `ReferenceInspectorToText`
renders it as two stacked sections: a compact header followed by the
Julia-printed reference on one line, and a "Human-readable" header followed
by the reverse-order English narrative that
[reference.md](../kernel/reference.md)'s `ReferenceToHumanReadableText`
produces. Before rendering, `annotate_reference_types` adds `TypeReferenceStep`
checkpoints to the reference against `target`, so the compact form shows each
step's `::Type` and the narrative names each step's parent type. Both
`map_reference_forward` and `map_reference_backward` return `nothing`, so a
click landing inside the rendered panel produces no operation — the inspector
is display-only.

## The hover probe

`HoverProbeProjection(; inner, pointer, id=:inspector, offset=(16,20),
size=(1000,400), title="reference")` wraps a window's content projection.
Its printer is transparent: it projects through `inner` and returns the
output unchanged, so wrapping a document in the probe changes nothing
visually. Its reader answers `MouseMove` by reverse-projecting the pointer
position through `inner` exactly as a left click at that position would be.
It feeds `inner` a synthetic `MousePress` and reads the `path` of the
`ReplaceSelectionOperation` it would produce, without committing it. Over a
clickable glyph, it opens a `:tooltip`-styled follower window near the
pointer holding a `ReferenceInspector(reference, target)`; over dead space,
it closes that window. Every other event passes straight through to `inner`,
so a real click, a key, a scroll or a drag selects and edits the document
normally. `pointer` is injected as a 0-arg callable rather than read from a
backend directly, so this projection carries no backend dependency, the way
`TextToGraphics` takes its `measure` function.

## How it fits

`InspectorModule` depends on `ProjecturedScreen`, `ProjecturedStyle` and
`ProjecturedText`, and on nothing from any source domain: the inspector
reads a `Reference` and a `Document` generically. `WindowManagingProjection`
is what applies the `OpenWindowOperation` / `CloseWindowOperation` the probe
emits, opening and updating the follower window in place. An application
wraps its top-level content projection in a `HoverProbeProjection` to get a
live reference inspector beside it; `example/projectured/Gallery.jl` shows
the wiring.

## What a reader must know before changing this

There is no `test/inspector/` folder; the probe is exercised by
`test/projectured/projection/HoverProbeTest.jl`. `HoverProbeIoMap` is
declared `@iomap` and forwards its `output` through a `ComputedCell` even
though the printer is transparent, which keeps the IoMap's own identity
stable while the wrapped child re-derives. Dropping that indirection would
break identity for a caller that holds onto the outer IoMap across a rerun.
