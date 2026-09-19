# Writing

> **Kind:** rule · **Status:** current · **Stands on:** [code-quality-rules.md](code-quality-rules.md)

How every document of this repository is written: plain technical English, no
marketing, no personification, and the present state only. It applies to each
file under `documentation/`, to the Markdown files at the root, and to
docstrings. `test_documentation()` checks the part of it that a program can
check.

## Plain technical English

The rules follow Simplified Technical English (ASD-STE100).

- Use one word for one thing. Do not use a synonym for variety.
- Use the active voice, and name who acts.
- Use simple tenses: the present, the past, the future, the imperative.
- Keep an instruction to 20 words, and a description to 25 words.
- Keep a paragraph to six sentences, with one topic. Put the topic first.
- Write "must" for a requirement, and "can" for a possibility.
- Do not use a contraction, an idiom or a metaphor.
- Give the full form of an abbreviation at its first use.
- Number the steps of a procedure, and put a condition before its instruction.
- Do not put more information between dashes or in parentheses. Write a new
  sentence.

## No slop and no marketing

The reader is an engineer who wants to know what the program does. Do not sell.

**Do not use these words and phrases**: seamless, powerful, robust, elegant,
first-class, out of the box, batteries included, under the hood, it's not X —
it's Y, not bolted on, by construction as a claim, literally, customers, value
proposition.

- Do not use an emoji in a heading or in a list item.
- Use bold for a term where the document defines it, or for the first words of
  a list item. Nothing else.
- Do not group items in threes for rhythm.
- A claim names the code that makes it true, or a measurement that shows it.

## No personification

The subject of a sentence is a person — you, the user, the developer — or a
part of the program that computes, returns, stores or calls something. An
object does not know, want, ask, decide, refuse, offer, promise or tell.

| Do not write | Write |
| --- | --- |
| A domain knows nothing about how it is displayed. | A domain has no reference to a projection. |
| A card folds only from its chevron. | A click on the chevron folds the card. A click elsewhere on the card does not. |
| A flow breaks at the width it is offered. | The flow layout breaks a line at the width that its parent gives it. |
| The reader declines the gesture. | The reader returns `nothing` for the gesture, so the next reader gets it. |
| The assistant is not bolted on. | The tool set is a layer of the kernel. The assistant and an MCP client use it. |

## The present state only

A document says what is. It does not say what was, what moved, or what a
refactor did. History goes into a plan under `plan/done/` and into the commit
message. The same rule holds for a comment and a docstring; see
[code-quality-rules.md](code-quality-rules.md).

## Honest status

A feature that exists only in a plan is not written in the present tense. State
a limit where a reader looks for the feature, not in a list at the end.

## The header and the summary

Each document starts with three things, in this order:

1. The title, as a level-one heading.
2. The header line: `> **Kind:** <kind> · **Status:** <status> · **Stands on:**
   <link>`. The kinds are `why`, `what`, `decision`, `rule`, `design`,
   `reference` and `procedure`, and [README.md](../README.md) says what each one
   answers.
3. One paragraph of at most three sentences that says what the document
   answers.

The assistant shows that paragraph in its list of guides, so it must read on
its own.

## The name of a guide

The assistant reads the guides by name, and the name comes from the path:
`documentation/guide/x.md` is `guide/x`, and
`documentation/package/<slice>/x.md` is `<slice>/x`. A new name or a move
changes `resource://guide/<name>`, so every such string in `source/` and in
`documentation/` must name a guide that exists. `test_documentation()` checks
that.

## Links

A link to another document of this repository is relative, and its target must
exist. A link to a heading must name a heading that is in the target file.
