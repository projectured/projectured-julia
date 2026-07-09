# Requirements

This document states what ProjecturEd is required to do, as capabilities
observable from the outside — by a person or an AI assistant using the editor,
or by someone working with the project. Each requirement is written to hold
regardless of how it is implemented and regardless of what kind of content is
being edited. Requirements describe intended behaviour; the
[roadmap](roadmap.md) tracks how much of it is delivered today.

These are the *product* requirements (what the editor and project must do). For
the *internal development* requirements that keep the codebase tractable — the
invariants and conventions every change must respect — see
[architecture-requirements.md](architecture-requirements.md).

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

9. **Every intermediate state is representable.** If the editor can represent one
   state of the content and can represent another, then it must also be able to
   represent every intermediate state the user pictures in her mental model on the
   way from the first to the second — even a state that is ill-formed in the
   original kind of content. The architecture must permit such a state to exist,
   one way or another.

### Selecting, navigating, and finding

10. **Reach any part.** The user must be able to move the selection to any part of
    the content, and must always be able to see clearly what is currently
    selected.

11. **Structural and linear navigation.** The user must be able to move through
    the content both by its structure (in, out, and between neighbouring parts)
    and linearly, and input must be directed to whatever is currently selected.

12. **Search and jump.** The user must be able to search the content for what
    they are looking for, move directly to matches, and see matches distinguished
    from the rest.

### Presenting and organizing content

13. **More than one way to see the same data.** The same underlying content must
    be presentable in more than one way, and the user must be able to switch
    between presentations without changing the data.

14. **Sort and filter any collection, without losing editing.** Whenever the
    content on screen includes a collection of items — a list, a set of rows, a
    set of fields, whatever it holds — the user must be able to sort and filter
    that collection for viewing while continuing to edit it, and doing so must not
    alter the underlying data.

15. **Focus and reorganize the view.** The user must be able to narrow the view to
    a part of the content and widen it back, and to rearrange how content is laid
    out, again without changing the data itself.

16. **Combine different kinds of content.** Different kinds of content must be able
    to appear together in one document, and selecting, navigating, and editing
    must work seamlessly across the boundaries between them.

17. **Any kind of content can nest in any other, arbitrarily.** Any kind of
    content must be able to appear inside any other kind, in any arrangement,
    whether or not that combination has a predefined meaning. The meaning is not
    required up front: it may be supplied elsewhere, defined later, or exist only
    in the user's mind.

18. **Any part can be a document on its own.** Any fragment of any kind of content
    must be able to stand as a complete document in its own right, edited and
    presented with the same capabilities as any larger whole.

### Interaction

19. **Keyboard and pointer.** The user must be able to work with both the keyboard
    and a pointing device, including placing the cursor by pointing, and dragging
    and scrolling where those make sense.

20. **Multiple routes to the same action.** A given action must be reachable in
    more than one way when appropriate, and every route to it must behave
    identically. Actions that do not apply in the current context must be shown as
    unavailable and must do nothing.

21. **Discoverable actions.** The user must be able to find out what actions are
    available in the current context without prior knowledge.

22. **Transfer content in and out.** The user must be able to copy, cut, and paste
    content within the editor and to and from other applications.

23. **Adjust the scale.** The user must be able to change the scale of what is
    displayed to suit their needs.

### Feedback and workspace

24. **Immediate feedback.** The editor must give immediate, visible feedback for
    interaction — what is hovered, pressed, focused, and selected.

25. **Information on demand.** The editor must be able to present supplementary
    information about what the user is pointing at or working on, on demand and
    without obscuring the content.

26. **Multiple views open at once.** The user must be able to have several views
    or panels open at the same time and work across them.

### Scale, portability, and durability

27. **Responsive at any size.** Editing must stay responsive regardless of how
    large the document is; working in a large document must feel no slower than
    working in a small one.

28. **Unbounded content.** The editor must be able to present and edit content
    that is very large, or even conceptually unbounded, by working with only the
    part currently in view.

29. **Same editor, different environments.** The same editor, with the same
    behaviour, must be able to run in different environments — for example a
    native window, a terminal, or a browser.

30. **Many editors in one process.** A single running process must be able to
    host several independent editors at the same time, each with its own
    document, selection, view, and time, running and animating side by side.
    Starting, using, or stopping one editor must have no effect on any other,
    and one editor's activity must never disturb, slow, or corrupt another's.

31. **Save, reload, and interchange.** The user must be able to save their work
    and reload it exactly as it was, and to import and export content in
    durable, human-readable forms that other tools can consume.

32. **Render without a display.** The user must be able to render what they see to
    durable outputs — images and print-quality documents — without needing an
    interactive display.

### AI assistance

33. **AI edits with the same guarantees.** An AI assistant must be able to inspect
    and change the document with the same guarantees as a person: its edits must
    likewise be unable to produce invalid content, and must target the meaning of
    the content rather than its position on screen.

34. **Editing by request.** The user must be able to ask, in natural language, for
    changes to the content and see them carried out.

---

## Usability of the project

35. **Runs from a clean checkout.** Someone must be able to obtain the project and
    get a working editor running by following documented steps, with the
    prerequisites clearly stated.

36. **Try it in one step.** Any provided example must be launchable with a single,
    obvious command.

37. **Works without a display.** A contributor must be able to inspect the
    editor's output and exercise its behaviour without a graphical display, so
    that development and automated testing do not depend on one.

38. **New kinds of content are cheap to add.** A contributor must be able to add
    support for a new kind of content without changing the existing core, and
    obtain the full editing experience for it with a small, well-defined amount of
    work.

39. **New presentations and interactions compose.** A contributor must be able to
    add a new way of presenting content, a new interaction, or a new output target
    on its own, and have it work together with everything already present.

40. **Change can be verified in the small.** It must be possible to verify a
    change with a check scoped to that change, without running everything, and the
    results must clearly distinguish a genuine regression from a known, tracked
    limitation.

41. **Optional capabilities are separable.** Capabilities that carry heavy or
    external dependencies — special displays, outside data sources, native
    libraries — must be separable, so that the core can be built, run, and tested
    without them.

42. **Can be delivered as an application.** The project must be able to be packaged
    and delivered as a standalone application.

43. **Documented with a clear path in.** The project must be documented so that a
    newcomer is taught the concepts before the mechanisms and can find the right
    guidance for a task without reading everything.

44. **Predictable by convention.** The project's conventions must be stated and
    applied consistently, so that its behaviour and its structure are predictable
    rather than surprising.
