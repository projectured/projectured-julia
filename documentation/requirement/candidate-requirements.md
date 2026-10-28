# Candidate requirements

> **Kind:** what · **Status:** current; a backlog, not a promise · **Stands on:** [accepted-requirements.md](accepted-requirements.md)

This document holds the proposed product requirements that nobody has reviewed
yet. A candidate moves to [accepted-requirements.md](accepted-requirements.md)
only after a review, and the review can change its words or drop it.

A candidate states intended behaviour. It does not say that the editor has that
behaviour today; the [roadmap](delivery-roadmap.md) tracks what is delivered.

Each candidate carries a symbolic ID in the same form as an accepted
requirement, `PR-…`. An ID is permanent and is never reused. A candidate keeps
its ID when it moves to the accepted document.

The candidates come from the first principles of the user experience of the
editor. Each candidate has a bold rule, the sentences that say what the editor
must do, and a **Why** with its source in the literature. The last section
proposes extensions of accepted requirements; an extension keeps the ID of the
requirement that it extends.

---

## Index

Every candidate in document order. The ID links to the candidate; the rule is
its own lead sentence.

**Speed**

| ID | Rule |
| --- | --- |
| [PR-FAST-START](#pr-fast-start) | Start fast, and fast from the first use |
| [PR-ALWAYS-ANSWERS](#pr-always-answers) | The editor always answers |
| [PR-COST-FOLLOWS-THE-CHANGE](#pr-cost-follows-the-change) | A small change costs little |

**Look**

| ID | Rule |
| --- | --- |
| [PR-ONE-VISUAL-LANGUAGE](#pr-one-visual-language) | One look |
| [PR-READABLE-FOR-EVERYONE](#pr-readable-for-everyone) | Readable for everyone |

**Feedback and attention**

| ID | Rule |
| --- | --- |
| [PR-STILL-WHEN-IDLE](#pr-still-when-idle) | Still when idle |
| [PR-PERSON-OWNS-ATTENTION](#pr-person-owns-attention) | The person owns the attention |
| [PR-VISIBLE-WORK](#pr-visible-work) | Work that runs is visible |

**Interaction**

| ID | Rule |
| --- | --- |
| [PR-VISIBLE-CLUES](#pr-visible-clues) | Clues show where an interaction can happen |
| [PR-FAMILIAR-CONVENTIONS](#pr-familiar-conventions) | The keys that a person knows |
| [PR-SAME-OPERATION-SAME-WAY](#pr-same-operation-same-way) | One operation, one way |

**Presenting and organizing content**

| ID | Rule |
| --- | --- |
| [PR-CHAIN-AND-KEEP](#pr-chain-and-keep) | Chain operations, and keep the result |

**Durability**

| ID | Rule |
| --- | --- |
| [PR-WORK-SURVIVES-A-CRASH](#pr-work-survives-a-crash) | Work survives a crash |
| [PR-FAULT-STAYS-LOCAL](#pr-fault-stays-local) | A fault stays local |

**AI assistance**

| ID | Rule |
| --- | --- |
| [PR-ASSISTANT-AT-HAND](#pr-assistant-at-hand) | The assistant is at hand |
| [PR-AI-IN-THE-OPEN](#pr-ai-in-the-open) | The assistant works in the open |

**Usability of the project**

| ID | Rule |
| --- | --- |
| [PR-SELF-DESCRIBING-BEHAVIOUR](#pr-self-describing-behaviour) | Behaviour describes itself |
| [PR-RECORD-AND-COMPARE](#pr-record-and-compare) | Record and compare |

**Extensions of accepted requirements**

| Extends | Addition |
| --- | --- |
| [PR-KEYBOARD-AND-POINTER](#extension-of-pr-keyboard-and-pointer) | Every function by the keyboard alone, and by the pointer alone |
| [PR-DISCOVERABLE-ACTIONS](#extension-of-pr-discoverable-actions) | Find every command by its name, from anywhere |
| [PR-SORT-AND-FILTER](#extension-of-pr-sort-and-filter) | Group a collection too |
| [PR-UNDO-REDO](#extension-of-pr-undo-redo) | Undo every change, whoever makes it |

## Speed

#### PR-FAST-START

**Start fast, and fast from the first use.** A person must be able to give
input to the editor less than one second after its launch. The first use of
each function must take no more time than its later uses.

**Why.** One second is the limit for the flow of thought of a person (Nielsen
1993). A person who waits at the first use of each function loses that flow
many times in one session.

#### PR-ALWAYS-ANSWERS

**The editor always answers.** The response to every interaction must be on
the screen less than 50 ms after the input. A drag, a scroll, a resize and a
zoom must draw a new frame at every refresh of the display. Work that takes
longer must run apart from the interaction, and the editor must continue to
answer the person while that work runs.

**Why.** A response within 0.1 s feels instant (Nielsen 1993), and a person who
drags notices much smaller delays (Ng et al. 2012). One interaction that blocks
the editor makes every other part feel slow.

#### PR-COST-FOLLOWS-THE-CHANGE

**A small change costs little.** The work that the editor does for a change
must be in proportion to the size of the change. It must not grow with the
amount of content on the screen.

**Why.** An incremental computation computes again only what a change touches
(Acar 2005). If one typed character costs as much as the whole screen, the cost
of typing grows with every part that the person opens.

## Look

#### PR-ONE-VISUAL-LANGUAGE

**One look.** Every part must take its fonts, colours, sizes, spacing and
layout from one set of style values. The same kind of part must look the same
wherever it appears, and a different look must mean a different kind of part.

**Why.** The eye groups what looks alike, by the Gestalt law of similarity. So a
look that differs for no reason shows the person a difference that does not
exist. Consistency is one of the ten usability heuristics (Nielsen 1994).

#### PR-READABLE-FOR-EVERYONE

**Readable for everyone.** Every text must have enough contrast to its
background, in the light, the dark and the high contrast modes. Information
must not come from colour alone. At a large scale the layout must still hold:
no text is cut, and no part covers another part.

**Why.** The Web Content Accessibility Guidelines (WCAG 2.2) set a contrast of
4.5:1 for text, and ask for text that a person can enlarge to 200 %. A person
who can not tell two colours apart must still be able to read the state of a
part.

## Feedback and attention

#### PR-STILL-WHEN-IDLE

**Still when idle.** The screen must change only when the person, or work that
the person started, causes the change. When nothing happens, the editor must
draw nothing and use no processor time.

**Why.** Movement on the screen pulls the attention of a person away from the
work (Weiser and Brown 1995, calm technology). An idle editor that draws also
uses energy for nothing.

#### PR-PERSON-OWNS-ATTENTION

**The person owns the attention.** Only a gesture of the person must move the
selection, the focus, the scroll position or the layout. A background result, a
change of a file on the disk and the assistant must change content in place,
and must not move what the person looks at.

**Why.** A person builds habits on stable places, and a target that moves breaks
them (Raskin 2000). An unexpected layout shift is one of the measured problems
of the web (Web Vitals).

#### PR-VISIBLE-WORK

**Work that runs is visible.** Each piece of work that runs apart from the
interaction must show what it is, how far it is, and a control that stops it.
When the work ends, its result must show at its place.

**Why.** Visibility of system status is the first usability heuristic (Nielsen
1994). After about one second a person needs a sign that the work continues.
After about ten seconds the person needs a measure of progress and a way out
(Nielsen 1993; Myers 1985).

## Interaction

#### PR-VISIBLE-CLUES

**Clues show where an interaction can happen.** Where a person can act on a
part, the screen must show a clue, for example a pointer shape, a highlight, a
handle or a caret. The clue must also show which kind of interaction is
possible there.

**Why.** A signifier shows where an action is possible and what the action is.
Without it, a person must guess (Norman 2013).

#### PR-FAMILIAR-CONVENTIONS

**The keys that a person knows.** The standard keys and gestures of the
platform must do what a person expects, in every part where the action has a
meaning. Examples are copy, cut, paste, undo, redo, find, save, select all and
close.

**Why.** People spend most of their time in other programs, so they expect the
same conventions in this one (Nielsen 2000).

#### PR-SAME-OPERATION-SAME-WAY

**One operation, one way.** An operation that applies to many kinds of content
must work the same way on each kind: the same gesture, the same look and the
same words.

**Why.** One command that works on many kinds of objects means fewer commands
to learn (Beaudouin-Lafon and Mackay 2000, polymorphism). What a person learns
on one kind of content then works on every other kind.

## Presenting and organizing content

#### PR-CHAIN-AND-KEEP

**Chain operations, and keep the result.** A person must be able to use the
result of one operation as the input of the next one. For example, a person
sorts a filtered collection, and then makes a chart of it. A person must be
able to keep a combination of views and operations, give it a name, and use it
again.

**Why.** Reification turns a command into an object that a person can keep and
combine, and reuse applies it again (Beaudouin-Lafon and Mackay 2000). A person
who can not keep a combination must build it again each time.

## Durability

#### PR-WORK-SURVIVES-A-CRASH

**Work survives a crash.** After a crash or a restart, the unsaved edits, the
open documents, the layout and the selection must come back as they were.

**Why.** The protection of the work of the person is a first principle of
interaction design (Tognazzini 2014). A crash that loses an hour of edits costs
more trust than any other fault.

#### PR-FAULT-STAYS-LOCAL

**A fault stays local.** A fault in one part of the editor must change only
that part. The other parts must continue to work and to answer. The fault must
show at its place, in plain words, with an action that the person can do next.

**Why.** Help to recognize, diagnose and recover from errors is a usability
heuristic (Nielsen 1994). If one broken part stops the whole editor, a person
loses all open work for one small fault.

## AI assistance

#### PR-ASSISTANT-AT-HAND

**The assistant is at hand.** A person must be able to ask the assistant about
any part with one gesture, with that part as the context of the question. A
person must be able to dismiss the assistant with one gesture.

**Why.** Efficient invocation and efficient dismissal are guidelines for
human-AI interaction (Amershi et al. 2019). When help comes on request, the
screen can stay small.

#### PR-AI-IN-THE-OPEN

**The assistant works in the open.** Each change by the assistant must be
visible and marked as the work of the assistant. A person must be able to undo
it in the same way as a change of the person. The assistant must not move the
selection or the focus of the person. Before a large change, the editor must
show what the change will do.

**Why.** A person can trust and correct only what the person can see (Amershi
et al. 2019). In a mixed-initiative interface, the person keeps the control
(Horvitz 1999).

## Usability of the project

#### PR-SELF-DESCRIBING-BEHAVIOUR

**Behaviour describes itself.** Each part of the editor must describe the
gestures that it takes and the states to which they lead. With that
description, a program must be able to drive and check every behaviour, with
no person. If the states are finite and few, the check must reach all of them.

**Why.** A model-based test derives its cases from a description of the system
(Utting and Legeard 2007). A description that comes from the parts stays
correct when the parts change.

#### PR-RECORD-AND-COMPARE

**Record and compare.** Each state of the editor must give a picture, and the
same state must give the same picture each time. A scripted scenario must give a
video. A program must be able to compare two versions of the editor, picture by
picture, and list only what changed.

**Why.** A change of the user interface is visible only on the screen. A person
reviews a short list of differences much faster than the whole program.

## Extensions of accepted requirements

An extension proposes more words for an accepted requirement. The words go into
that requirement, so the extension has no ID of its own.

#### Extension of PR-KEYBOARD-AND-POINTER

**Add.** A person must be able to use every function with the keyboard alone,
and with the pointer alone.

**Why.** Some people can not use a pointer, and some people work faster with
the keys. A function that only one device reaches is lost to them (WCAG 2.2,
success criterion 2.1.1).

#### Extension of PR-DISCOVERABLE-ACTIONS

**Add.** A person must be able to find every command by its name, from
anywhere, and not only the commands of the current context.

**Why.** Recognition is easier than recall (Nielsen 1994). A person who
remembers a part of the name of a command must not need to know where the
command applies.

#### Extension of PR-SORT-AND-FILTER

**Add.** A person must be able to group a collection and to see an aggregate of
each group, in the same way as a sort and a filter, and with the same
guarantee that the underlying data does not change.

**Why.** With a grouping, a person sees the count or the mean of each kind,
which a sort does not show.

#### Extension of PR-UNDO-REDO

**Add.** A person must be able to undo every change, whoever makes it,
including a change of the assistant and a write to a file. An action that
destroys data must be reversible, and the editor must not guard it with a
question.

**Why.** A person learns to confirm a question with no thought, so an undo
protects the work better than a question (Raskin 2000).

## Sources

- Acar, U. (2005). Self-adjusting computation. PhD thesis, Carnegie Mellon
  University.
- Amershi, S. et al. (2019). Guidelines for Human-AI Interaction. CHI 2019.
- Beaudouin-Lafon, M. and Mackay, W. (2000). Reification, polymorphism and
  reuse: three principles for designing visual interfaces. AVI 2000.
- Google. Web Vitals: cumulative layout shift.
- Horvitz, E. (1999). Principles of mixed-initiative user interfaces. CHI 1999.
- Myers, B. (1985). The importance of percent-done progress indicators for
  computer-human interfaces. CHI 1985.
- Ng, A. et al. (2012). Designing for low-latency direct-touch input. UIST 2012.
- Nielsen, J. (1993). Usability Engineering, chapter 5: response times.
- Nielsen, J. (1994). Enhancing the explanatory power of usability heuristics.
  CHI 1994.
- Nielsen, J. (2000). End of web design.
- Norman, D. (2013). The Design of Everyday Things, revised edition.
- Raskin, J. (2000). The Humane Interface.
- Tognazzini, B. (2014). First principles of interaction design.
- Utting, M. and Legeard, B. (2007). Practical Model-Based Testing.
- W3C (2023). Web Content Accessibility Guidelines (WCAG) 2.2.
- Weiser, M. and Brown, J. S. (1995). Designing calm technology.
