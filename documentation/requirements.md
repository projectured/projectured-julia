# Requirements

This document states what ProjecturEd is required to do, as capabilities
observable from the outside — by a person or an AI assistant using the editor,
or by someone working with the project. Each requirement is written to hold
regardless of how it is implemented and regardless of what kind of content is
being edited. Requirements describe intended behaviour; the
[roadmap](roadmap.md) tracks how much of it is delivered today.

Two parts follow: the **behaviour of the editor** (what the editor must do for
the person using it) and the **usability of the project** (what the project must
do for the person building with or contributing to it).

---

## Behaviour of the editor

### Correctness

1. **No invalid states.** No matter what the user types, clicks, or drags, the
   editor must never let the document reach a malformed or structurally invalid
   state. Every edit must produce well-formed content.

2. **Only meaningful positions.** Every position the cursor can occupy must be a
   meaningful place in the content. The user must not be able to leave the cursor
   in an impossible or ambiguous location.

3. **What is shown reflects the truth.** Whatever is on screen must always
   correspond exactly to the current content; there must be no way for the
   display and the underlying data to disagree.

### Editing

4. **Whatever is shown can be edited.** Whenever content is displayed, the user
   must be able to change it directly, and the change must be reflected in the
   underlying data.

5. **Editing at the natural granularity.** The user must be able to edit content
   at whatever granularity it has: replace a whole item with another, change a
   value in place, edit a piece of text character by character, and add or remove
   items from a collection.

6. **Context-appropriate edits.** At any position, the editor must offer only the
   edits that are meaningful there, and must prevent edits that are not.

7. **Reversible editing.** The user must be able to undo and redo changes, and to
   return to an earlier state of the content.

8. **A history that can be revisited.** The user must be able to keep and return
   to earlier versions of any part of the content.

### Selecting, navigating, and finding

9. **Reach any part.** The user must be able to move the selection to any part of
   the content, and must always be able to see clearly what is currently
   selected.

10. **Structural and linear navigation.** The user must be able to move through
    the content both by its structure (in, out, and between neighbouring parts)
    and linearly, and input must be directed to whatever is currently selected.

11. **Search and jump.** The user must be able to search the content for what
    they are looking for, move directly to matches, and see matches distinguished
    from the rest.

### Presenting and organizing content

12. **More than one way to see the same data.** The same underlying content must
    be presentable in more than one way, and the user must be able to switch
    between presentations without changing the data.

13. **Sort and filter any collection, without losing editing.** Whenever the
    content on screen includes a collection of items — a list, a set of rows, a
    set of fields, whatever it holds — the user must be able to sort and filter
    that collection for viewing while continuing to edit it, and doing so must not
    alter the underlying data.

14. **Focus and reorganize the view.** The user must be able to narrow the view to
    a part of the content and widen it back, and to rearrange how content is laid
    out, again without changing the data itself.

15. **Combine different kinds of content.** Different kinds of content must be able
    to appear together in one document, and selecting, navigating, and editing
    must work seamlessly across the boundaries between them.

### Interaction

16. **Keyboard and pointer.** The user must be able to work with both the keyboard
    and a pointing device, including placing the cursor by pointing, and dragging
    and scrolling where those make sense.

17. **Multiple routes to the same action.** A given action must be reachable in
    more than one way when appropriate, and every route to it must behave
    identically. Actions that do not apply in the current context must be shown as
    unavailable and must do nothing.

18. **Discoverable actions.** The user must be able to find out what actions are
    available in the current context without prior knowledge.

19. **Transfer content in and out.** The user must be able to copy, cut, and paste
    content within the editor and to and from other applications.

20. **Adjust the scale.** The user must be able to change the scale of what is
    displayed to suit their needs.

### Feedback and workspace

21. **Immediate feedback.** The editor must give immediate, visible feedback for
    interaction — what is hovered, pressed, focused, and selected.

22. **Information on demand.** The editor must be able to present supplementary
    information about what the user is pointing at or working on, on demand and
    without obscuring the content.

23. **Multiple views open at once.** The user must be able to have several views
    or panels open at the same time and work across them.

### Scale, portability, and durability

24. **Responsive at any size.** Editing must stay responsive regardless of how
    large the document is; working in a large document must feel no slower than
    working in a small one.

25. **Unbounded content.** The editor must be able to present and edit content
    that is very large, or even conceptually unbounded, by working with only the
    part currently in view.

26. **Same editor, different environments.** The same editor, with the same
    behaviour, must be able to run in different environments — for example a
    native window, a terminal, or a browser.

27. **Save, reload, and interchange.** The user must be able to save their work
    and reload it exactly as it was, and to import and export content in
    durable, human-readable forms that other tools can consume.

28. **Render without a display.** The user must be able to render what they see to
    durable outputs — images and print-quality documents — without needing an
    interactive display.

### AI assistance

29. **AI edits with the same guarantees.** An AI assistant must be able to inspect
    and change the document with the same guarantees as a person: its edits must
    likewise be unable to produce invalid content, and must target the meaning of
    the content rather than its position on screen.

30. **Editing by request.** The user must be able to ask, in natural language, for
    changes to the content and see them carried out.

---

## Usability of the project

31. **Runs from a clean checkout.** Someone must be able to obtain the project and
    get a working editor running by following documented steps, with the
    prerequisites clearly stated.

32. **Try it in one step.** Any provided example must be launchable with a single,
    obvious command.

33. **Works without a display.** A contributor must be able to inspect the
    editor's output and exercise its behaviour without a graphical display, so
    that development and automated testing do not depend on one.

34. **New kinds of content are cheap to add.** A contributor must be able to add
    support for a new kind of content without changing the existing core, and
    obtain the full editing experience for it with a small, well-defined amount of
    work.

35. **New presentations and interactions compose.** A contributor must be able to
    add a new way of presenting content, a new interaction, or a new output target
    on its own, and have it work together with everything already present.

36. **Change can be verified in the small.** It must be possible to verify a
    change with a check scoped to that change, without running everything, and the
    results must clearly distinguish a genuine regression from a known, tracked
    limitation.

37. **Optional capabilities are separable.** Capabilities that carry heavy or
    external dependencies — special displays, outside data sources, native
    libraries — must be separable, so that the core can be built, run, and tested
    without them.

38. **Can be delivered as an application.** The project must be able to be packaged
    and delivered as a standalone application.

39. **Documented with a clear path in.** The project must be documented so that a
    newcomer is taught the concepts before the mechanisms and can find the right
    guidance for a task without reading everything.

40. **Predictable by convention.** The project's conventions must be stated and
    applied consistently, so that its behaviour and its structure are predictable
    rather than surprising.
