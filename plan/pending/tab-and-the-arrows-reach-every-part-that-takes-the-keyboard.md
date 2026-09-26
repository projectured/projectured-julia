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

## 4. Open questions

- **Q1. Can one Tab walker do the whole walk (N2)?** The facts of §3 give this
  answer, which is Claude's judgement:
  - A walk over the document does what the composite, the split pane and the
    layouts do today: their code is that walk, in document order.
  - A walk over the document can not see the view. It walks every page of a
    tabbed pane and every section of an accordion, also the hidden ones, because
    they are in the document. The same walk enters a sibling today
    (`get_first_focusable_path`), so today Tab can already land in a hidden
    page. No run confirmed this yet.
  - "Is drawn" by the forward mapping is not a test that works today: the
    accordion, the list, the tree and the dialog answer `nothing`
    (`WidgetToGraphics.jl:7666` for the accordion).
  - Claude's recommendation: the walker enumerates the drawn elements and maps
    each one back to a document with D11 of the other plan. The stops are the
    parts that take the keyboard among them, in document order. A hidden page
    and a closed section are not drawn, so they are not stops, and no container
    needs code for Tab. The same list of drawn stops, with their boxes, serves
    the move in the plane (N6), and the box of the current stop is the box of
    the drawn element that maps back to the selection. So neither Tab nor the
    move in the plane needs the forward mapping.
  - So one walker can do it, but only after the backward mapping of D11 works
    in every projection that ends in graphics.
- **Q2. Which parts are stops?** By the purpose (§1), every part that takes the
  keyboard in a meaningful way. Today the list, the table, the tree, the
  accordion and the charts are not stops, and no document of a domain is a stop
  (N5 wants the JSON document to be one). Which of them get a method of the
  trait, and does the trait mark the whole JSON document and not each of its
  elements?

## 5. The order with the other plan

The refactor of [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md)
removes `WidgetHoverTrackingProjection`, which holds the wrap-around of Tab
today. So the navigation step of this plan must exist before that removal, or
come in the same change. Otherwise Tab stops at the ends.

## 6. Next steps

1. Answer Q1 and Q2 with the owner, and record each answer in §2.
2. Collect the facts that an answer needs at the time it needs them.
3. Then write the steps, each with its test.
