# Five more gallery wrappers

`run_example` already wraps an example in a workbench, a scroll pane, a tooltip,
an inspector, an introspection pane, a clipboard, or a text-control bar. Five
cross-domain wrappers exist in the code and the gallery cannot reach them. Add
one keyword for each.

| Keyword | What it wraps the example in |
| --- | --- |
| `shell` | a `WidgetShell` — a menu bar, a toolbar, and a status bar around the content |
| `hover` | a `WidgetHoverTrackingProjection` — the pointer crossings a widget needs |
| `dragging` | a `DraggingState` + `DraggingProjection` — press, drag, and drop reorders a collection |
| `command_palette` | the upcoming command type-in overlay (see [command-palette.md](command-palette.md)) |
| `gesture_help` | a `GestureHelpProjection` — F1 lists the gestures the context offers |

## What changes for a caller who passes none of them

One thing. The gesture-help decorator is unconditional today: every window of
every `run_example` call gets it. It becomes opt-in, so F1 opens no window
unless the caller writes `gesture_help=true`. The user chose this over a
`true` default, so that all five keywords read the same way.

## Design

### Where each wrapper goes

The existing document wrappers form an exclusive `if`/`elseif` chain, because a
workbench and a scroll pane are two answers to the same question. The five new
ones are layers, so they compose, and they apply in a fixed order after that
chain:

1. `dragging` — wraps the document, then the projection.
2. `shell` — wraps the document, then the projection.
3. `caching` — the existing flag.
4. `hover` — wraps the projection.
5. `gesture_help` — wraps the projection.
6. `command_palette` — wraps the projection, outermost.

A projection wrapper that comes later sits further out. The gesture-help
decorator therefore sees the whole pipeline below it, which is what its
collector needs.

### The gesture-help decorator moves out of the composer

`_multi_window_projection` builds the decorator itself today, inside the
reference-dispatch arm that matches a window's content. It moves to the loop
that applies the flags, one shared `GestureHelpState` for every window, so F1
toggles one window. The composer's arm then reads like the other two
composers': a `NestingProjection` and nothing else.

The move also gives the tooltip and the inspector pipelines the help window,
which they never had. Their composers gain the `GestureMap` type entry that
renders it.

### The selection lift takes a chain of fields

`_build_window_scene` lifts a seeded selection from the inner document to a
screen-rooted path. It needed to know how deep that document sits under
`win.content`, and `content_unwrap` named the one wrapper in the way: `:plain`,
`:tooltip`, or `:clipboard`.

Two wrappers can now stack, so the parameter becomes a vector of field names,
outermost first — `Symbol[]`, `[:child]`, `[:content]`, `[:content, :content]`.
A recursive helper prefixes them onto the inner path, one `@reference` per level,
built against the document that level addresses so the node type folds in.

**The runtime-field step does not reach the front of a path.** `@reference`
has a `field(e)` step whose name is a runtime value, which would have made one
recursion serve any chain. The parser reads `field(name)` as an extension step
unless a path precedes it, so `@reference(document, field(name).^(inner))`
raises "no `build_reference_step(::Val{:field}, …)` method registered". The
wrappers introduce two field names, `child` and `content`, so the helper spells
both out and refuses a third.

### A shell renders any content

`WidgetShellToGraphicsCanvas` drew its content only when the content was a
`WidgetDocument`. An example document is not one, so the shell would have framed
an empty hole. The guard becomes `!== nothing`, which is what
`WidgetTabbedPaneToGraphicsCanvas` already does for a tab — and the tabbed pane
is how `introspection=true` puts an example document inside a widget today.

### The command palette is a seam, not an implementation

`CommandPaletteProjection` does not exist yet. Phase 5 step 1 of the
command-palette plan is "wrap each example pipeline in the decorator in
`Gallery.jl`". `make_command_palette_projection` is that call site: it raises a
clear error today, and the phase replaces its one line.

## Files

- `package/visual/main/widget/WidgetToGraphics.jl` — the shell content guard.
- `package/domain/example/document/Wrapper.jl` — `make_shell_document`,
  `make_dragging_document`.
- `package/domain/example/projection/Wrapper.jl` — `make_shell_projection`,
  `make_dragging_projection`, `make_command_palette_projection`.
- `package/domain/example/Gallery.jl` — the five keywords, the field-chain
  selection lift, the moved decorator.
- `package/domain/example/ProjecturedDomainExample.jl` — the exports.

## Phases

### Phase 1 — the wrappers — **done**

1. ~~Widen the shell's content guard.~~
2. ~~Add the document and projection helpers.~~
3. ~~Add the five keywords and apply them.~~
4. ~~Turn the field chain of the selection lift into a vector.~~
5. ~~Move the gesture-help decorator out of the composer.~~

### Phase 2 — the tests — **done**

1. ~~`test_visual()` — the shell guard.~~
2. ~~`test_domain()` — the gallery and the scene builder.~~
3. ~~A scene-builder case for a two-field unwrap chain.~~

`test_gallery_wrappers()` is the new case, in
[GalleryWrapperTest.jl](../../package/domain/test/editor/GalleryWrapperTest.jl).
It counts the text leaves a wrapped example draws, so a frame around nothing
fails: a shell draws the content's leaves plus its own eight, and the dragging
wrapper draws exactly the content's.

`test_gesture_help()` had one case that fired F1 through
`_multi_window_projection` and expected a help window. The decorator is opt-in
now, so the case wraps the example projection first, and a new case asserts that
an undecorated pipeline opens no window.

## Deferred

- A live menu in the shell. A submenu opens a popup window, and the gallery
  composer installs no `WidgetPopupResolverProjection`, so the menu bar draws
  and its submenus do not open. The toolbar and the status bar draw the same
  way. The flag exists to see an example inside a shell frame.
- Composing `dragging` with `workbench`. The workbench projection does not know
  `DraggingProjection`, so the wrapper would be inert inside an editor page.
