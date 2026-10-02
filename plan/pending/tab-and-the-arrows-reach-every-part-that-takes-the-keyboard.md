# Tab and the arrows reach every part that takes the keyboard

> **Status (2026-09-26): deferred by the owner.** The owner focuses on
> [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md), and
> every decision of this plan waits, except the one step that the other plan
> needs (§5). This plan was split on the same day from that plan, where its
> decisions N1 to N6 were D33 and D35 to D39. The two subjects are unrelated (D2
> of that plan).

## 1. The purpose

In the owner's words: "to be able to reach any user interface component which
can interact using the keyboard in a meaningful way".

The focus is the selection (the docstring of `FocusModule`): a part is reached
when the selection names it. A part that takes the keyboard is a **stop**.

### The model: a caret that moves from one text into the next

The owner gave this model on 2026-09-26. Two documents, "Hello" and "World",
stand in a row. Each one has its own projection with its own text navigation.
Their parent is a projection that puts the two in sequence.

1. The caret is at the end of "Hello", and the person presses Right.
2. The parent gives the key to "Hello", the child that the selection names.
3. "Hello" has no place to move to, so it answers no operation.
4. The parent sees that no operation came, and it moves the selection to the
   start of "World", the next child in its own order.
5. If "World" was the last child, the parent answers no operation too, and its
   own parent tries the same step one level up.

No projection knows more than its own children. Each child decides where the
caret can go inside it, and each parent decides only which child comes next.

Tab and the move in the plane work the same way:

- **Tab.** A container gives Tab to the selected child. When the child answers
  no operation, the container moves to the next child that holds a stop, and
  enters it at its first stop. The containers of today already do this (§3).
- **The move in the plane (Shift + Alt + arrow).** A container gives the key to
  the selected child. When the child answers no operation, the container looks
  among its own children, by its own layout, for the neighbour in that direction,
  and enters it from the side that the move comes from. With no neighbour, it
  answers no operation, and its parent tries.
- **The wrapper** does only what no part can do: when the outermost part answers
  no operation for Tab, it starts over at the other end.

## 2. The owner's decisions

All of them are from 2026-09-26.

- **N1** (was D33). Keyboard navigation between parts is a projection step of its
  own, outside the hover tracker. It does three things:
  - Tab and Shift+Tab move to the next and the previous stop, and start over at
    each end;
  - cursor keys with modifiers move in the plane to the stop that is next in
    that direction, found with the mapping of references;
  - it works with any document that accepts it, not only with widgets.
- **N2** (was D35). ~~One Tab walker does the whole walk of Tab, if it can.~~
  Replaced by N7.
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
  keyboard. The owner later said that the widgets can maybe do this move too,
  each one inside itself and recursively (N7). Deferred.
- **N7.** The walk stays in the parts. Each container walks Tab inside itself, as
  today, and the wrapping step does hardly anything on its own. The owner's
  reasons:
  - the wrapping projection does not know all the state that matters, nor how to
    interpret it;
  - any projection can skip any part of a document for any reason, and a wrapper
    has no way to know it;
  - that a part maps forward to the graphics does not mean that it can take the
    focus.
- **N8.** A general rule, in the owner's words: "anything which can be done
  locally should be done locally because it combines better". It must become a
  rule of the design documents. It is near `PAR-DELEGATE-ONE-LEVEL` of
  `architecture-invariants.md`, which says the same for printers and mappers.

## 3. What exists today

- The package `ProjecturedFocus` (`source/focus/`) holds the open trait
  `is_focusable_document`, to which a domain adds a method. It has two methods:
  the default `false` (`Focus.jl:5`), and the one of the widgets, which marks
  each enabled button, checkbox, text, text area, select, switch, slider, spin
  box, toggle, toggle group, radio group, menu item and toolbar item
  (`WidgetDocument.jl:2795`).
- The same package holds the walks `get_first_focusable_path` and
  `get_last_focusable_path` (`Focus.jl:49-64`). They walk the document only:
  every element of a vector and every field that holds a document, in the order
  of declaration. They name no widget type, and they read nothing that is drawn.
  A set of visited nodes stops the walk in a list with links in both directions.
- The widget composite, the split pane and the layouts move Tab inside
  themselves, all in the same way: they give Tab to the selected child, and when
  it declines, they go to the next sibling that holds a stop, in document order
  (`WidgetToGraphics.jl:2694`, `:3731`, `LayoutToGraphics.jl:358-398`). At the
  end they decline. Only the start over at the ends is in
  `WidgetHoverTrackingProjection` (`WidgetHoverTracking.jl:69-85`).
- The tabbed pane has no code for Tab: Tab goes to the page that the selection
  names, like every key. No list, table, tree, accordion or dialog has code for
  Tab, and none of them is a stop, although the list, the table and the tree
  answer arrow keys and the chart answers keys.
- The JSON and YAML documents take Tab to move from a key to its value
  (`JsonDocument.jl:116`, `YamlDocument.jl:107`). The text declines Tab
  (`TextToGraphics.jl:159`). An open completion takes Tab
  (`InsertionToSyntax.jl:261`). No JSON, text or syntax document is a stop; the
  focus reaches it only by a click or by the keys of the panes.
- omnet-julia has no code for Tab and no method of the trait.
- `SelectionWalkingProjection` of the same package is a precedent for the step:
  a transparent wrapper that answers the Alt + arrow keys that nothing inside
  answered, with a walk over the structure of any document
  (`SelectionWalking.jl:1-60`).
- The plan [widget-focus-traversal.md](../done/widget-focus-traversal.md) (done
  2026-06-28) chose this split on purpose: "no dedicated traversal projection and
  no flat enumeration table". It kept the start over at the ends as the one
  global rule. N1 changes that choice.

## 4. Deferred questions

- **Which parts are stops?** By the purpose (§1), every part that takes the
  keyboard in a meaningful way. Today the list, the table, the tree, the
  accordion and the charts are not stops, and no document of a domain is a stop
  (N5 wants the JSON document to be one).
- **Does Tab land in a hidden page today?** A container enters a sibling with
  `get_first_focusable_path`, which walks every page of a tabbed pane and every
  section of an accordion. A reading of the code suggests it; no run confirmed
  it.
- **The move in the plane (N6):** by a search from the wrapper, or by the widgets,
  recursively.

A rejected alternative: Claude proposed on 2026-09-26 that one walker lists the
drawn elements, maps each one back, and takes the stops among them, so that no
container needs code for Tab. The owner rejected it for the reasons of N7.

## 5. The one step that the other plan needs

The refactor of [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md)
removes `WidgetHoverTrackingProjection`, which holds the start over at the ends
of Tab today. So that start over must leave it first, or in the same change,
into a small wrapping step of its own. Otherwise Tab stops at the ends.

Today the start over walks the whole document with `get_first_focusable_path`,
which N7 says a wrapper can not know. The containers already choose their first
stop themselves when nothing is selected (the comment at
`WidgetHoverTracking.jl:74-78`). So the step can hand the declined Tab back
to the parts as a Tab with no selection, and let each container choose. Claude
noted this on 2026-09-26; it waits with the rest.

## 6. Next steps

Deferred. When the owner takes this plan up again, answer §4 and write the steps,
each with its test.
