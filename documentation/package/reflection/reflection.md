# The reflection view

> **Kind:** reference · **Status:** current · **Stands on:** [bounded-sync.md](bounded-sync.md)

How any Julia value reaches the screen with no projection written for it: a bounded shadow of the value, a widget tree made from that shadow, and the two other paths that draw a value. `run_value_viewer(value)` is the one call that uses this slice; [view-your-data-guide.md](../../guide/view-your-data-guide.md) is the guide for a user.

## The shadow

```julia
shadow = reflect_document(value, DepthPolicy(depth = 1, elements = 20))
```

`reflect_document` walks the value and builds a tree of `ReflectedNode`. It stops where the policy says to stop, and puts a marker where it stopped, so a node that was not walked says how much is behind it. `sync_reflection!(shadow, value, policy)` brings the shadow up to date afterwards; a node that is already open keeps its identity, so the widget that holds it keeps holding it.

The policy is what makes the view affordable:

- `DepthPolicy(depth, elements)` walks that many levels and that many elements of one collection.
- `UNBOUNDED_SYNC` walks everything, for a small value.

A value that refers to itself is safe, because the walk stops at the depth of the policy. [bounded-sync.md](bounded-sync.md) explains the policy and what a marker holds.

## The view

`ReflectionToWidget` turns the shadow into a widget tree: one row per field or element, the kind of each value beside it, and a chevron on a node that holds more. A click on the chevron asks for the next level, which is a `sync_reflection!` with the node marked as requested.

```julia
projection = ChainingProjection(ReflectionToWidget(),
                                WidgetToGraphics(font_ubuntu_monospace_regular_20;
                                                 measure = measure_truetype_text))
```

That pair is what `make_value_viewer(value)` builds.

## The three ways a value is drawn

| Path | What it is for | What it costs |
| --- | --- | --- |
| the reflection view (this slice) | any value, large, running, or one that refers to itself | one level at a time; a chevron asks for more |
| `NaturalToGraphics` | a document of a registered domain, or a small struct | reads every field it reaches; it does not draw a dictionary |
| `ObjectToWidget` | a value that is shown as a form of its fields, inside a designed view | the fields the caller names |

`NaturalToGraphics` reflects a struct through `ObjectToSyntax`, which prints the type name and the fields. That is the flat view a reader wants for a small value. The reflection view is the one to use when the value is large or alive.

## What a reader must know

- The shadow is not the value. A change of the value shows after a `sync_reflection!`, which the view does when it is asked for the next level, and which a caller can do on its own.
- The shadow holds what it walked, so a very large value costs what the policy allowed and no more.
- The view shows values; it does not edit them. An edit needs a projection of the domain that owns the value.

`test/substrate/projection/ReflectionToWidgetTest.jl` checks what a collapsed node says and what a chevron does; `test/projectured/editor/ValueViewerTest.jl` checks the four kinds of value that the one call must draw.
