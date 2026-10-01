# Appearance

> **Kind:** design · **Status:** current · **Stands on:** [style.md](../style/style.md), [editor.md](../../kernel/editor.md), [operation.md](../../kernel/operation.md)

The appearance slice of `ProjecturedPlatform` connects the `Appearance` of an editor to its view. It holds the `Appearance` in the root document, binds the keys of the zoom and of the scales, and makes the view print again after a change. The editor knows nothing about themes: it gets a document and a projection, as always.

## The parts

- `AppearanceDocument(appearance, content)` is the root document of an editor with the wrapper. The `Appearance` is a part of the document, so a view can show it and a reference can name it. `get_wrapped_document` goes through it to the content.
- `AdjustZoomOperation(appearance, delta)` steps the zoom, and `AdjustScaleOperation(appearance, scale, delta)` steps one of the six scales (`APPEARANCE_SCALES`), through the table of `step_factor`: `+1` up, `-1` down, `0` back to 1. The zoom operation also copies the zoom into the `Display` of the editor, where the backends read it. Neither is an edit of the content, so the inverse is `DoNothingOperation`.
- `AppearanceManagingProjection(inner)` prints the content through `inner` and returns its output, and maps references through the `content` field.
- The `appearance` wrapper of `build_editor` puts both around everything else, the window manager too. It is on by default.

## The keys

| Factor | Larger | Smaller | Reset |
| --- | --- | --- | --- |
| zoom | Ctrl+`=` | Ctrl+`-` | Ctrl+`0` |
| font scale | Ctrl+Alt+`=` | Ctrl+Alt+`-` | Ctrl+Alt+`0` |
| icon scale | Ctrl+Alt+`.` | Ctrl+Alt+`,` | — |
| spacing scale | Ctrl+Alt+`]` | Ctrl+Alt+`[` | — |

The keys are the `@gestures` table of `AppearanceDocument`, so F1 and the palette list them. The control, radius and line scales have no key.

## How a change reaches the view

A projection reads its scaled theme through untracked style fields, which record no edge, so a change of a scale reaches no cell of the view. `AppearanceManagingProjection` is the one place that sees such a change:

1. The content reads each input first. A view that binds a key, such as the zoom of a `WidgetTransformPane`, keeps it.
2. When the content answers nothing, the keys of the `AppearanceDocument` answer.
3. When the answer changes the appearance (`is_appearance_change`: a step of the zoom or of a scale, or a write into the `Appearance` or into one of its themes, alone or inside a compound or a wrapping operation), the projection puts `InvalidateProjectionOperation` after it.

The editor then prints the whole view again in the same frame, and the inputs after the change wait for the new view. A frame prints at most once.

For `CollectIntents`, the projection joins the keys of the content and its own, so a listing shows both.

## One appearance for each editor

The content, the tab strip of the `tabs` wrapper and the `AppearanceDocument` must draw from one `Appearance`. `build_editor` makes the argument of each wrapper with `make_wrapper_argument` before it builds anything; for the argument `true` this slice makes a new `Appearance`. With no projection named, `make_document_projection(document; arguments...)` gives the renderer the same object. `EditorParts.arguments` holds the arguments, so the `tabs` wrapper takes the appearance from there when its own argument names none. A start step of the wrapper copies the zoom of the appearance into the `Display`, so an editor starts at the zoom that its appearance holds.

A main builder that builds its own projection makes one `Appearance`, builds with it, and passes it as `appearance = …` to `build_editor`.

## How it fits

The slice depends on the kernel and on the style slice. The backends read the zoom from the `Display`: the SDL backend finds a new zoom when it draws, and keeps the device size of each window. The domains and the widgets get their themes from the `Appearance` that their builders pass; see [style.md](../style/style.md#themes-and-the-appearance) and [widget.md](../widget/widget.md).

## Design decisions

- **The editor knows nothing about themes.** The wrapper handles every change of the appearance, and the kernel only passes the arguments of the wrappers on. See [plan/pending/zoom-and-theme-controls.md](../../../../plan/pending/zoom-and-theme-controls.md), D4, D20, D29 and D32.
- **A change prints the whole view again.** The view has no edge to the theme, so a print of the whole view is the one way a change reaches it, and it costs one print for a rare event.
