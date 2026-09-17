# The documentation

> **Kind:** reference · **Status:** current · **Stands on:** every document in this folder

This folder holds the documents of the editor, from why it exists to how the
code is laid out. This file is the map. It draws the chain that derives the code
from first principles, lists every document with its place in the chain, and
states the header that every document carries.

The structure is the one omnet-julia uses, so a reader who knows one repository
knows the other. See
[omnet-julia/documentation/README.md](../../omnet-julia/documentation/README.md).

## The folders and the chain

Each folder answers one question that a reader brings. The folders follow the
chain: each row stands on the row above it. A reader who wants to know why a
thing is the way it is walks up; a reader who wants to know what to build walks
down.

```
requirement/   why does anyone want it, and what must it do
  └─ design/   how is it built, why not otherwise, and what is each part
       ├─ rule/        what is a change checked against
       └─ the code     design/system-anatomy.md and package/ say where it lives
```

Beside the chain:

```
guide/         how to do a task: set up, debug, test, add a domain, compile
package/       the guide of each slice
presentation/  the slide decks
```

Three folders that omnet-julia has are **not** here, because there is nothing
yet to put in them. `evidence/` holds a risk register and the numbers measured
against a predecessor; `study/` holds experiments that are not decisions;
`history/` holds how the chain came to be. Until then the history is
[plan/done/](../plan/done/), one plan per step.

## Every document

In the order of the chain. The kind is the one in the document's header.

| Document | Kind | What it answers |
| --- | --- | --- |
| [product-vision.md](requirement/product-vision.md) | why | What is the long-term potential, which pain does it address, and how does it relate to other tools? |
| [accepted-requirements.md](requirement/accepted-requirements.md) | what | What must the editor do, as capabilities observable from outside? `PR-…` |
| [delivery-roadmap.md](requirement/delivery-roadmap.md) | what | What is delivered, what is in progress, and what is next? |
| [architecture-decisions.md](design/architecture-decisions.md) | decision | Why is it built this way, and why not otherwise? |
| [architecture-invariants.md](rule/architecture-invariants.md) | rule | What must every change respect, so the system stays tractable as it grows? `PAR-…` |
| [architecture-rules.md](rule/architecture-rules.md) | rule | How is the code divided, and where does a new thing belong? |
| [package-rules.md](rule/package-rules.md) | rule | What is a package for, what may it depend on, and which one do I load? |
| [code-quality-rules.md](rule/code-quality-rules.md) | rule | How does the code read, and what keeps it readable? |
| [naming-rules.md](rule/naming-rules.md) | rule | How is a package, a file, a module, a type or a function named? |
| [division-terminology.md](rule/division-terminology.md) | reference | What do package, layer, slice and module mean, exactly? |
| [editor-concepts.md](design/editor-concepts.md) | design | What is projectional editing, and what are the five ideas? No code. **Start here if you are new.** |
| [editor-derivation.md](design/editor-derivation.md) | design | How do the concepts combine into a system, each one with its real code? |
| [system-anatomy.md](design/system-anatomy.md) | design | What is the editor made of? The pipeline, the package graph, the layers, the module inventory. |
| [domain-inventory.md](design/domain-inventory.md) | reference | What are the twenty domains, what depends on what, and what makes one? |
| [package/README.md](package/README.md) | reference | The guide of each slice, one folder per slice. |
| [orientation.md](guide/orientation.md) | reference | Where do I look first, and what do I search for? |
| [setup-guide.md](guide/setup-guide.md) | procedure | How do I install it and open a session? |
| [examples-tour.md](guide/examples-tour.md) | reference | Which examples exist, what does each show, and what should I try? |
| [debugging-guide.md](guide/debugging-guide.md) | procedure | How do I drive the printer and the reader by hand, and force a cell? |
| [testing-guide.md](guide/testing-guide.md) | procedure | Which test covers my change, and how do I read the summary? |
| [new-domain-guide.md](guide/new-domain-guide.md) | procedure | How do I add a domain: documents, projection, reader, example, test? |
| [build-guide.md](guide/build-guide.md) | procedure | How do I build a native binary, and what does it need to run elsewhere? |
| [static-compilation-guide.md](guide/static-compilation-guide.md) | procedure | How do I get a `juliac --trim` binary out of this repository? |
| [presentation/README.md](presentation/README.md) | reference | Which slide decks exist, and how do I render one? |

## The header

Every document starts with one block-quote line under its title:

```markdown
> **Kind:** decision · **Status:** current · **Stands on:** [accepted-requirements.md](requirement/accepted-requirements.md)
```

**A slide deck is exempt.** A file under `presentation/` that Marp renders is a
rendered artifact, not a reference page: its first lines are YAML front matter,
and a block-quote placed after them appears as text on the first slide. The
folder's own `README.md` carries the header and says what each deck is.

**Kind** is one of:

| Kind | The document answers |
| --- | --- |
| why | What does a user gain? |
| what | What must the editor do? |
| decision | How is it built, and why not otherwise? |
| rule | What is a change checked against? |
| design | What is each part, in the settled form? |
| reference | Where is what, and how is it used? |
| procedure | How do I do this task? |

`evidence`, `study` and `history` are kinds omnet-julia uses that no document
here carries yet. Add one when the folder that holds it arrives.

**Status** is `current` (a qualifier can follow a semicolon), `snapshot <date>`,
`superseded by <document>`, or `generated, do not edit`.

**Stands on** names the documents the document depends on directly, by their
path from the citing file. It is the citation direction, which can differ from
the order of the chain: a benefit names the requirements it comes from, and a
requirement never names a benefit.

## Two rules that hold everywhere

**A document describes what is.** How it came to be is in
[plan/done/](../plan/done/), one plan per step. A reader who wants the current
state is not made to read the history, and a reader who wants the history finds
it in one place.

**Cite, do not repeat.** A statement that belongs to one document is linked from
the others. Two copies drift, and one of them is then wrong. A bare `§N` means a
section of the file you are reading; cite any other file by name.

## The neighbours

| Folder | What it holds |
| --- | --- |
| [plan/pending/](../plan/pending/) and [plan/done/](../plan/done/) | The design and implementation plans. A done plan is a step of the history. |
| [../SEALING.md](../SEALING.md) | Which kernel files are sealed, and the audit before a seal. |
| [asset/](../asset/) | Fonts, the reference screenshots the examples are checked against, the web client, and the precompile recording. |

## Where to start

1. New to projectional editing: [editor-concepts.md](design/editor-concepts.md), then [examples-tour.md](guide/examples-tour.md).
2. New and an engineer: [editor-derivation.md](design/editor-derivation.md), then [system-anatomy.md](design/system-anatomy.md).
3. About to open a session: [setup-guide.md](guide/setup-guide.md), then [debugging-guide.md](guide/debugging-guide.md).
4. About to change code: [architecture-invariants.md](rule/architecture-invariants.md), then [architecture-rules.md](rule/architecture-rules.md), [package-rules.md](rule/package-rules.md) and [naming-rules.md](rule/naming-rules.md).
5. About to add a domain: [domain-inventory.md](design/domain-inventory.md), then [new-domain-guide.md](guide/new-domain-guide.md).
6. About to run a test: [testing-guide.md](guide/testing-guide.md).
