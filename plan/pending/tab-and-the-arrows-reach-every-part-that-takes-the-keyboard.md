# Tab and the arrows reach every part that takes the keyboard

> **Status (2026-09-26): design, no code.** Split on the same day from
> [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md), where
> the decisions N1 to N6 of this plan were D33 and D35 to D39. The two subjects
> are unrelated (D2 of that plan), but the refactor of that plan removes the
> projection that holds the wrap-around of Tab today (§5).

## 1. The purpose

In the owner's words: "to be able to reach any user interface component which
can interact using the keyboard in a meaningful way".

The focus is the selection (the docstring of `FocusModule`): a part is reached
when the selection names it. A part that takes the keyboard is a **stop**.

## 2. The owner's decisions

All of them are from 2026-09-26.

- **N1** (was D33). Keyboard navigation between parts is a projection step of its
  own, outside the hover tracker. It does three things:
  - Tab and Shift+Tab move to the next and the previous stop, and start over at
    each end;
  - cursor keys with modifiers move in the plane to the stop that is next in
    that direction, found with the mapping of references;
  - it works with any document that accepts it, not only with widgets.
- **N2** (was D35). One Tab walker does the whole walk of Tab, if it can. The owner
  is not sure that it can (Q1).
- **N3** (was D36). Shift + Alt + arrow moves in the plane. No code uses this key
  today. Alt + arrow walks the structure (`SelectionWalkingProjection`).
- **N4** (was D37). A part that uses a key answers it first, and the navigation
  step gets only what no part answered. So no key always leaves a part: a part
  that takes Tab keeps Tab.
- **N5** (was D38). A JSON document is one stop. Inside it, its own cursor keys
  move.
- **N6** (was D39). A move in the plane maps the current stop forward to its drawn
  element. Then a search looks around it, in the direction of the key, for the
  closest graphical element that maps back to a document that takes the
  keyboard. The backward mapping of a point is D11 of the other plan.

## 3. What exists today

- The package `ProjecturedFocus` (`source/focus/`) holds the open trait
  `is_focusable_document`, to which a domain adds a method. The widgets mark each
  enabled interactive leaf (`WidgetDocument.jl:2795`).
- The same package holds the walks `get_first_focusable_path` and
  `get_last_focusable_path`. They name no widget type.
- The widget and layout containers move Tab inside themselves
  (`WidgetToGraphics.jl:1225`, `LayoutToGraphics.jl:207`) and decline at the end
  of their subtree. Only the start over at the ends is in
  `WidgetHoverTrackingProjection` (`WidgetHoverTracking.jl:69-85`).
- `SelectionWalkingProjection` of the same package is a precedent for the step:
  a transparent wrapper that answers the Alt + arrow keys that nothing inside
  answered, with a walk over the structure of any document
  (`SelectionWalking.jl:1-60`).

## 4. Open questions

- **Q1. Can one Tab walker do the whole walk (N2)?** A walk over the document can
  reach a part that is not drawn: a hidden page of a tabbed pane, a closed
  section of an accordion. The containers know this. If the walker counts only
  the stops that are drawn, as the search of N6 does, it can know it too, and
  Tab and the move in the plane share one idea of a stop. The facts to collect:
  the special cases that the Tab code of each container holds.
- **Q2. How far does the forward mapping reach (N6)?** A move in the plane needs
  the drawn box of each stop. Nobody checked yet how far `map_reference_forward`
  reaches the output in the widgets, the layouts and the screen.

## 5. The order with the other plan

The refactor of [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md)
removes `WidgetHoverTrackingProjection`, which holds the wrap-around of Tab
today. So the navigation step of this plan must exist before that removal, or
come in the same change. Otherwise Tab stops at the ends.

## 6. Next steps

1. Collect the facts of the Tab code of the containers (Q1), and the reach of the
   forward mapping (Q2).
2. Answer Q1 and Q2 with the owner, and record each answer in §2.
3. Then write the steps, each with its test.
