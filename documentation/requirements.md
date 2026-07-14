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

Each requirement carries a symbolic ID — `R-NO-INVALID-STATES`,
`R-UNDO-REDO` — to cite in reviews, commit messages, and plans. An ID is
permanent and is never reused; it names the requirement, not the section it sits
in, so requirements can be regrouped without invalidating a citation. Each ID is
a heading, so a citation can link to the requirement itself:
`[R-UNDO-REDO](requirements.md#r-undo-redo)`.

Two parts follow: the **behaviour of the editor** (what the editor must do for
the person using it) and the **usability of the project** (what the project
must do for the person building with or contributing to it).

---

## Index

Every product requirement in document order. The ID links to the
requirement; the rule is its own lead sentence.

**Correctness**

| ID | Rule |
| --- | --- |
| [R-NO-INVALID-STATES](#r-no-invalid-states) | No invalid states |
| [R-MEANINGFUL-POSITIONS](#r-meaningful-positions) | Only meaningful positions |
| [R-DISPLAY-IS-TRUTH](#r-display-is-truth) | What is shown reflects the truth |

**Editing**

| ID | Rule |
| --- | --- |
| [R-EDIT-WHAT-IS-SHOWN](#r-edit-what-is-shown) | Whatever is shown can be edited |
| [R-NATURAL-GRANULARITY](#r-natural-granularity) | Editing at the natural granularity |
| [R-CONTEXT-APPROPRIATE-EDITS](#r-context-appropriate-edits) | Context-appropriate edits |
| [R-UNDO-REDO](#r-undo-redo) | Reversible editing |
| [R-REVISITABLE-HISTORY](#r-revisitable-history) | A history that can be revisited |
| [R-INTERMEDIATE-STATES](#r-intermediate-states) | Every intermediate state is representable |

**Selecting, navigating, and finding**

| ID | Rule |
| --- | --- |
| [R-REACH-ANY-PART](#r-reach-any-part) | Reach any part |
| [R-STRUCTURAL-AND-LINEAR-NAVIGATION](#r-structural-and-linear-navigation) | Structural and linear navigation |
| [R-SEARCH-AND-JUMP](#r-search-and-jump) | Search and jump |

**Presenting and organizing content**

| ID | Rule |
| --- | --- |
| [R-MANY-VIEWS-OF-ONE-DOCUMENT](#r-many-views-of-one-document) | More than one way to see the same data |
| [R-SORT-AND-FILTER](#r-sort-and-filter) | Sort and filter any collection, without losing editing |
| [R-FOCUS-AND-REORGANIZE](#r-focus-and-reorganize) | Focus and reorganize the view |
| [R-COMBINE-CONTENT-KINDS](#r-combine-content-kinds) | Combine different kinds of content |
| [R-ARBITRARY-NESTING](#r-arbitrary-nesting) | Any kind of content can nest in any other, arbitrarily |
| [R-ANY-PART-IS-A-DOCUMENT](#r-any-part-is-a-document) | Any part can be a document on its own |

**Interaction**

| ID | Rule |
| --- | --- |
| [R-KEYBOARD-AND-POINTER](#r-keyboard-and-pointer) | Keyboard and pointer |
| [R-MULTIPLE-ROUTES](#r-multiple-routes) | Multiple routes to the same action |
| [R-DISCOVERABLE-ACTIONS](#r-discoverable-actions) | Discoverable actions |
| [R-CLIPBOARD](#r-clipboard) | Transfer content in and out |
| [R-ADJUST-SCALE](#r-adjust-scale) | Adjust the scale |

**Feedback and workspace**

| ID | Rule |
| --- | --- |
| [R-IMMEDIATE-FEEDBACK](#r-immediate-feedback) | Immediate feedback |
| [R-INFORMATION-ON-DEMAND](#r-information-on-demand) | Information on demand |
| [R-MULTIPLE-VIEWS-AT-ONCE](#r-multiple-views-at-once) | Multiple views open at once |

**Scale, portability, and durability**

| ID | Rule |
| --- | --- |
| [R-RESPONSIVE-AT-ANY-SIZE](#r-responsive-at-any-size) | Responsive at any size |
| [R-UNBOUNDED-CONTENT](#r-unbounded-content) | Unbounded content |
| [R-SAME-EDITOR-EVERYWHERE](#r-same-editor-everywhere) | Same editor, different environments |
| [R-MANY-EDITORS-ONE-PROCESS](#r-many-editors-one-process) | Many editors in one process |
| [R-SAVE-AND-INTERCHANGE](#r-save-and-interchange) | Save, reload, and interchange |
| [R-RENDER-HEADLESS](#r-render-headless) | Render without a display |

**AI assistance**

| ID | Rule |
| --- | --- |
| [R-AI-SAME-GUARANTEES](#r-ai-same-guarantees) | AI edits with the same guarantees |
| [R-EDIT-BY-REQUEST](#r-edit-by-request) | Editing by request |

**Usability of the project**

| ID | Rule |
| --- | --- |
| [R-CLEAN-CHECKOUT](#r-clean-checkout) | Runs from a clean checkout |
| [R-ONE-STEP-EXAMPLE](#r-one-step-example) | Try it in one step |
| [R-DEVELOP-HEADLESS](#r-develop-headless) | Works without a display |
| [R-CHEAP-NEW-DOMAIN](#r-cheap-new-domain) | New kinds of content are cheap to add |
| [R-COMPOSABLE-PROJECTIONS](#r-composable-projections) | New presentations and interactions compose |
| [R-VERIFY-IN-THE-SMALL](#r-verify-in-the-small) | Change can be verified in the small |
| [R-SEPARABLE-OPTIONALS](#r-separable-optionals) | Optional capabilities are separable |
| [R-SHIPPABLE-APPLICATION](#r-shippable-application) | Can be delivered as an application |
| [R-DOCUMENTED-PATH-IN](#r-documented-path-in) | Documented with a clear path in |
| [R-PREDICTABLE-CONVENTIONS](#r-predictable-conventions) | Predictable by convention |

## Behaviour of the editor

### Correctness

#### R-NO-INVALID-STATES

**No invalid states.** No matter what the user types, clicks, or drags, the
editor must never let the document reach a malformed or structurally invalid
state. Every edit must produce well-formed content.

#### R-MEANINGFUL-POSITIONS

**Only meaningful positions.** Every position the cursor can occupy must be a
meaningful place in the content. The user must not be able to leave the cursor
in an impossible or ambiguous location.

#### R-DISPLAY-IS-TRUTH

**What is shown reflects the truth.** Whatever is on screen must always
correspond exactly to the current content; there must be no way for the display
and the underlying data to disagree.

### Editing

#### R-EDIT-WHAT-IS-SHOWN

**Whatever is shown can be edited.** Whenever content is displayed, the user
must be able to change it directly, and the change must be reflected in the
underlying data.

#### R-NATURAL-GRANULARITY

**Editing at the natural granularity.** The user must be able to edit content
at whatever granularity it has: replace a whole item with another, change a
value in place, edit a piece of text character by character, and add or remove
items from a collection.

#### R-CONTEXT-APPROPRIATE-EDITS

**Context-appropriate edits.** At any position, the editor must offer only the
edits that are meaningful there, and must prevent edits that are not.

#### R-UNDO-REDO

**Reversible editing.** The user must be able to undo and redo changes, and to
return to an earlier state of the content.

#### R-REVISITABLE-HISTORY

**A history that can be revisited.** The user must be able to keep and return
to earlier versions of any part of the content.

#### R-INTERMEDIATE-STATES

**Every intermediate state is representable.** If the editor can represent one
state of the content and can represent another, then it must also be able to
represent every intermediate state the user pictures in her mental model on the
way from the first to the second — even a state that is ill-formed in the
original kind of content. The architecture must permit such a state to exist,
one way or another.

### Selecting, navigating, and finding

#### R-REACH-ANY-PART

**Reach any part.** The user must be able to move the selection to any part of
the content, and must always be able to see clearly what is currently selected.

#### R-STRUCTURAL-AND-LINEAR-NAVIGATION

**Structural and linear navigation.** The user must be able to move through the
content both by its structure (in, out, and between neighbouring parts) and
linearly, and input must be directed to whatever is currently selected.

#### R-SEARCH-AND-JUMP

**Search and jump.** The user must be able to search the content for what they
are looking for, move directly to matches, and see matches distinguished from
the rest.

### Presenting and organizing content

#### R-MANY-VIEWS-OF-ONE-DOCUMENT

**More than one way to see the same data.** The same underlying content must be
presentable in more than one way, and the user must be able to switch between
presentations without changing the data.

#### R-SORT-AND-FILTER

**Sort and filter any collection, without losing editing.** Whenever the
content on screen includes a collection of items — a list, a set of rows, a set
of fields, whatever it holds — the user must be able to sort and filter that
collection for viewing while continuing to edit it, and doing so must not alter
the underlying data.

#### R-FOCUS-AND-REORGANIZE

**Focus and reorganize the view.** The user must be able to narrow the view to
a part of the content and widen it back, and to rearrange how content is laid
out, again without changing the data itself.

#### R-COMBINE-CONTENT-KINDS

**Combine different kinds of content.** Different kinds of content must be able
to appear together in one document, and selecting, navigating, and editing must
work seamlessly across the boundaries between them.

#### R-ARBITRARY-NESTING

**Any kind of content can nest in any other, arbitrarily.** Any kind of content
must be able to appear inside any other kind, in any arrangement, whether or
not that combination has a predefined meaning. The meaning is not required up
front: it may be supplied elsewhere, defined later, or exist only in the user's
mind.

#### R-ANY-PART-IS-A-DOCUMENT

**Any part can be a document on its own.** Any fragment of any kind of content
must be able to stand as a complete document in its own right, edited and
presented with the same capabilities as any larger whole.

### Interaction

#### R-KEYBOARD-AND-POINTER

**Keyboard and pointer.** The user must be able to work with both the keyboard
and a pointing device, including placing the cursor by pointing, and dragging
and scrolling where those make sense.

#### R-MULTIPLE-ROUTES

**Multiple routes to the same action.** A given action must be reachable in
more than one way when appropriate, and every route to it must behave
identically. Actions that do not apply in the current context must be shown as
unavailable and must do nothing.

#### R-DISCOVERABLE-ACTIONS

**Discoverable actions.** The user must be able to find out what actions are
available in the current context without prior knowledge.

#### R-CLIPBOARD

**Transfer content in and out.** The user must be able to copy, cut, and paste
content within the editor and to and from other applications.

#### R-ADJUST-SCALE

**Adjust the scale.** The user must be able to change the scale of what is
displayed to suit their needs.

### Feedback and workspace

#### R-IMMEDIATE-FEEDBACK

**Immediate feedback.** The editor must give immediate, visible feedback for
interaction — what is hovered, pressed, focused, and selected.

#### R-INFORMATION-ON-DEMAND

**Information on demand.** The editor must be able to present supplementary
information about what the user is pointing at or working on, on demand and
without obscuring the content.

#### R-MULTIPLE-VIEWS-AT-ONCE

**Multiple views open at once.** The user must be able to have several views or
panels open at the same time and work across them.

### Scale, portability, and durability

#### R-RESPONSIVE-AT-ANY-SIZE

**Responsive at any size.** Editing must stay responsive regardless of how
large the document is; working in a large document must feel no slower than
working in a small one.

#### R-UNBOUNDED-CONTENT

**Unbounded content.** The editor must be able to present and edit content that
is very large, or even conceptually unbounded, by working with only the part
currently in view.

#### R-SAME-EDITOR-EVERYWHERE

**Same editor, different environments.** The same editor, with the same
behaviour, must be able to run in different environments — for example a native
window, a terminal, or a browser.

#### R-MANY-EDITORS-ONE-PROCESS

**Many editors in one process.** A single running process must be able to host
several independent editors at the same time, each with its own document,
selection, view, and time, running and animating side by side. Starting, using,
or stopping one editor must have no effect on any other, and one editor's
activity must never disturb, slow, or corrupt another's.

#### R-SAVE-AND-INTERCHANGE

**Save, reload, and interchange.** The user must be able to save their work and
reload it exactly as it was, and to import and export content in durable,
human-readable forms that other tools can consume.

#### R-RENDER-HEADLESS

**Render without a display.** The user must be able to render what they see to
durable outputs — images and print-quality documents — without needing an
interactive display.

### AI assistance

#### R-AI-SAME-GUARANTEES

**AI edits with the same guarantees.** An AI assistant must be able to inspect
and change the document with the same guarantees as a person: its edits must
likewise be unable to produce invalid content, and must target the meaning of
the content rather than its position on screen.

#### R-EDIT-BY-REQUEST

**Editing by request.** The user must be able to ask, in natural language, for
changes to the content and see them carried out.

---

## Usability of the project

#### R-CLEAN-CHECKOUT

**Runs from a clean checkout.** Someone must be able to obtain the project and
get a working editor running by following documented steps, with the
prerequisites clearly stated.

#### R-ONE-STEP-EXAMPLE

**Try it in one step.** Any provided example must be launchable with a single,
obvious command.

#### R-DEVELOP-HEADLESS

**Works without a display.** A contributor must be able to inspect the editor's
output and exercise its behaviour without a graphical display, so that
development and automated testing do not depend on one.

#### R-CHEAP-NEW-DOMAIN

**New kinds of content are cheap to add.** A contributor must be able to add
support for a new kind of content without changing the existing core, and
obtain the full editing experience for it with a small, well-defined amount of
work.

#### R-COMPOSABLE-PROJECTIONS

**New presentations and interactions compose.** A contributor must be able to
add a new way of presenting content, a new interaction, or a new output target
on its own, and have it work together with everything already present.

#### R-VERIFY-IN-THE-SMALL

**Change can be verified in the small.** It must be possible to verify a change
with a check scoped to that change, without running everything, and the results
must clearly distinguish a genuine regression from a known, tracked limitation.

#### R-SEPARABLE-OPTIONALS

**Optional capabilities are separable.** Capabilities that carry heavy or
external dependencies — special displays, outside data sources, native
libraries — must be separable, so that the core can be built, run, and tested
without them.

#### R-SHIPPABLE-APPLICATION

**Can be delivered as an application.** The project must be able to be packaged
and delivered as a standalone application.

#### R-DOCUMENTED-PATH-IN

**Documented with a clear path in.** The project must be documented so that a
newcomer is taught the concepts before the mechanisms and can find the right
guidance for a task without reading everything.

#### R-PREDICTABLE-CONVENTIONS

**Predictable by convention.** The project's conventions must be stated and
applied consistently, so that its behaviour and its structure are predictable
rather than surprising.