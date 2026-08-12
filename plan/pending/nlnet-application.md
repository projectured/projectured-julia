# NLnet Funding Application — ProjecturEd

> **Status (2026-08-12): NOT STARTED.** Still a draft; nothing here has been
> submitted. The date this plan waits for, "after summer 2026," has now arrived
> — check <https://nlnet.nl/propose/> for the reopened call before doing
> anything else in this plan. This file was not otherwise updated for progress:
> it is a funding pitch, not an implementation plan, so this pass only fixes
> facts about the repository that had gone stale.

**Status:** Draft, pending submission.
**Target fund:** NLnet's reopened **general open call** (the *Open Internet Stack* effort,
successor to NGI Zero Commons). Expected to reopen **after summer 2026** — likely an autumn
2026 deadline; that date has now passed (today is 2026-08-12) — check whether the call has
reopened. Watch <https://nlnet.nl/propose/> and subscribe to the newsletter.
**Do NOT** submit to the only currently-open calls (NGI Taler, NGI Fediversity, deadline
1 Aug 2026) — ProjecturEd does not fit either.

**Positioning:** lead with the **AI-native** angle. The README's Vision puts *"AI integration
from the ground up"* first; the whole submission should foreground that the editor is built so
an AI can edit safely via structural operations, with projectional editing as the substrate
that makes it possible.

---

## 0. Pre-submission decisions & gates

- **Licence (resolved):** On award, the **entire project will be released under an
  OSI-approved open-source licence — AGPL-3.0.** AGPL keeps the door open to commercial
  dual-licensing later (we own the copyright). State this commitment explicitly in the
  application; NLnet bakes it into the signed agreement (MoU).
- **R&D primary objective:** ✓ ProjecturEd is genuinely research-grade.
- **European dimension:** ✓ Applicant is EU-based (Hungary). Make address/country obvious.
- **AI sovereignty framing:** the assistant defaults to Claude (US, proprietary). Always frame
  the AI layer as **model-agnostic + offline-capable + open MCP protocol + local-first** so the
  AI emphasis reads as *trustworthy/sovereign AI*, never as "depends on US Big Tech AI."
- **Apply as an individual** — no legal entity required.
- **First proposal cap:** up to **€50,000**.
- **Before submitting:** attend one NLnet Office Hour (<https://nlnet.nl/officehour/>) to
  confirm fit against the reopened call's exact scope.

---

## 1. Admin fields

| Field | Value |
|---|---|
| Your name | Levente Mészáros |
| Email | levente.meszaros@gmail.com |
| Country | Hungary |
| Organisation | *(blank / individual)* |
| Project name | ProjecturEd — an AI-native, open-source projectional editor |
| Website | https://github.com/projectured/projectured-julia |
| Demo videos | https://www.youtube.com/@projectured (Lisp prototype) · new AI-focused video **[TODO]** |
| Fund | *(the reopened general call — confirm exact name when it opens)* |

---

## 2. Form answers

> Wording of the questions is stable across NLnet funds; confirm against the live form when
> the call reopens. Keep answers concise and concrete — reviewers read hundreds.

### Q1 — Can you explain the whole project and its expected outcome(s)?

ProjecturEd is an **AI-native, open-source projectional editor**. Its premise is that the future
of editing is not manual keystroke- and mouse-driven manipulation but *describing intent* — yet
bolting today's LLMs onto ordinary text editors is unsafe, because those tools generate and
patch raw text and routinely emit output that doesn't parse. ProjecturEd is built the other way
around, from the ground up, so that an AI — or a human — can edit safely.

The foundation is projectional editing: the document *is* structured data — trees, ASTs,
graphs — and what you see is produced by **bidirectional, composable projections**. You edit the
projection and each edit is mapped back into a precise structural operation on the model. There
is no text to corrupt, only operations on a model — so a malformed result is impossible by
construction.

That is what makes **AI integration from the ground up** real rather than a bolt-on. The
built-in assistant reads and modifies *both* the document and its projection by executing code
against the live editor: you describe a change and it is applied as a **structural operation**,
so an AI edit can no more produce malformed output than a human one can. The AI conversation is
*itself* a ProjecturEd document — the editor edits its own AI session with the very machinery it
uses for your data. The assistant is **model-agnostic with a fully offline fallback**, and its
tools are exposed over the **open MCP protocol**, so any external client — or a local, open
model — can drive the editor. No cloud dependency, no lock-in.

The same compositional design keeps it general and fast: documents and projections both compose,
so one mechanism already covers JSON, XML, source code, prose, tables and graphics — one
document shown as a tree, a form, a table or source with no copy to keep in sync — while a
**pull-based reactive engine** keeps editing responsive on very large, even unbounded,
documents.

**Twenty** domain packages already work end-to-end with selection and cursor movement (JSON, XML,
YAML, SQL, math, source code, prose/Markdown, and more — see the repository's own domain guide).
**This grant takes ProjecturEd from a working prototype to a usable, AI-native general-purpose
editor**: hardening the AI assistant with support for local/open models, character-level editing
across all domains, broadening mouse click-to-select (it already works, and is tested, for a
subset of domains) to the remaining ones, undo/redo, browser-backend parity, an accessibility
pass, and contributor documentation. All outcomes will be released under AGPL-3.0. Demos of the
projectional editing (Lisp prototype): <https://www.youtube.com/@projectured>; a new
AI-focused video for the Julia version is part of the work.

### Q2 — Have you been involved with projects or organisations relevant to this project before? And if so, can you tell us a bit about your contributions?

> **TODO — fill in your specifics.** Draft frame:

I am the original author of ProjecturEd, first developed in Common Lisp
(<https://github.com/projectured/projectured>; demos at <https://www.youtube.com/@projectured>),
which I have now reimplemented from scratch in Julia with a cleaner, fully compositional
architecture and AI integration from the ground up. I have **[N]** years of experience building
open-source developer tooling and structured-editing systems — **[name hu.dwim and other
specific projects / maintainership / talks / publications here]**. **[Add any relevant FOSS
maintenance, conference talks (e.g. JuliaCon), or research.]**

### Q3 — Requested amount

**€50,000** (see task breakdown in Q4).

### Q4 — Explain what the requested budget will be used for?

The work is broken into independently demonstrable tasks (each becomes a milestone in the MoU).
The AI assistant is the headline goal and the largest task:

- **Harden the AI assistant** — broaden its structural-edit repertoire and reliability, and add
  a **local/open-model backend** (sovereignty; no cloud dependency) — **€10,000**
- **Character-level editing across all domains** — round-tripping single-character
  inserts/deletes through nested, composable projections — **€10,000**
- **Mouse click-to-select, full domain coverage** — hit-testing graphics back to a reference
  path; the mechanism and its test already work for a subset of domains, this task extends it to
  the rest (widgets, tables, XML, math, and more) — **€6,000**
- **Undo/redo** as inverse structural operations — **€6,000**
- **Web-backend parity** with the native frontend — **€6,000**
- **Accessibility pass** — keyboard-complete navigation, screen-reader/ARIA in the web
  backend — **€6,000**
- **Contributor documentation + "add a new domain" tutorial** — **€3,000**
- **AI-focused demo video, examples & release packaging** — **€3,000**

**Total: €50,000.**

We would also welcome NLnet's in-kind partner support (security audit, accessibility review,
UX, translation).

### Q5 — Does the project have other funding sources, both past and present?

ProjecturEd is an existing, self-funded open-source project with no prior or current grant
funding. This proposal funds a defined set of new milestones. On award, the project will be
released under the AGPL-3.0 open-source licence.

### Q6 — Compare your own project with existing or historical efforts.

- **AI coding assistants (Copilot, Cursor, etc.)** — operate on *text*, so they can and do emit
  code that doesn't parse, and depend on remote proprietary models. ProjecturEd's assistant
  edits the *model* through structural operations — correct by construction — and is
  model-agnostic, offline-capable, and drivable over the open MCP protocol.
- **JetBrains MPS** — the best-known projectional editor, but proprietary, JVM-heavy, built
  around its own meta-language, and with no comparable AI integration. ProjecturEd is
  open-source, lightweight, domain-agnostic, and AI-native.
- **Eclipse Xtext / Langium** — text-grammar-based, not projectional; can still produce
  malformed input.
- **Lamdu, Hazel** — excellent, but tied to specific (functional / typed-lambda) languages;
  ProjecturEd is generic across JSON, XML, prose, tables, graphics, and code.
- **Eve** — discontinued.
- **The original ProjecturEd (Common Lisp)** — my own earlier work (see the demo videos); this
  Julia reimplementation has a cleaner, fully compositional projection model, multiple rendering
  backends, and AI integration from the ground up.

What's distinctive: an **AI layer that edits via structural operations** (model-agnostic,
offline-capable, open-protocol), built on **composition on both axes** (documents and
projections compose, and meet via nesting), **incremental reactive evaluation**, and
**multi-backend rendering** (native / browser / terminal from one pipeline) — all under an open
licence.

### Q7 — What are significant technical challenges you expect to solve during the project?

- **Trustworthy AI editing** — having an AI agent operate purely through structural operations
  on the model (never raw text), so its edits are correct by construction, broadening the
  repertoire of edits it can express, and supporting local/open models behind the same
  interface.
- **Bidirectional round-tripping of character-level edits** through a chain of nested,
  composable projections — each projection must invert an edit via its IO map back to a precise
  structural operation.
- **Incremental recomputation at scale** — keeping the pull-based reactive cell system correct
  and fast for large and lazily-materialised (even unbounded) documents.
- **Reference/selection mapping across domain boundaries** so the cursor round-trips faithfully
  through mixed-domain documents.
- **Backend parity** — one projection pipeline driving native, web, and terminal frontends
  identically.
- **Accessibility** of a non-text-buffer editing model for assistive technologies.

### Q8 — Describe the ecosystem of the project, and how you will engage with relevant actors and promote the outcomes?

ProjecturEd serves developer-tooling users, programming-language / HCI researchers (the
language-workbench community), the **AI-agent / MCP tooling ecosystem** (the editor is drivable
by any MCP client), and the Julia ecosystem. I will: release all code open-source on GitHub with
documentation and a "build your own domain" tutorial; publish an AI-focused demo video and
write-ups (building on the existing channel, <https://www.youtube.com/@projectured>); engage the
Julia community (Discourse, Zulip, a JuliaCon talk), the projectional-editing / PL research
community (MPS, Hazel circles), and the open AI-tooling / MCP community. Every outcome is
reusable open infrastructure others can build trustworthy, sovereign, AI-native editors on.

---

## 3. Demo videos (for Q1/Q8 links)

### Existing material — link now

- **Channel:** <https://www.youtube.com/@projectured> — several demos of the **Lisp prototype**.
- **Example:** *"Creating a Simple Web Page with a Projectional Editor"* —
  <https://www.youtube.com/watch?v=s05SlmZ7ZPc>.
- These prove the **depth of the projectional editing**, but predate the AI assistant — use them
  as supporting evidence, not as the headline.

### New video to record — AI-forward, 1.5–3 min, captioned

First 10 seconds must show the AI doing a structural edit. Host on **PeerTube** (federated;
sovereignty bonus) with a YouTube/repo mirror.

1. **AI assistant:** type a natural-language request → it applies a *structural operation*; show
   the result can't be malformed; note it also runs **offline**.
2. The AI **conversation is itself an editable ProjecturEd document**.
3. *(Optional)* drive the editor from an **external MCP client**.
4. Then the projectional fundamentals: edit JSON as a tree (you can't break it); **switch the
   projection** tree → form → table → source on the same data; a live sorting/filtering
   projection (model untouched); a mixed-domain document with the cursor round-tripping across
   boundaries.

Also add animated **GIFs to the README** (reuse stills in `asset/image/example/`).

---

## 4. Selection process (after submission)

1. **Eligibility check** against knock-out criteria (open licence, R&D focus, European
   dimension).
2. **Scoring:** technical excellence **30%**, relevance/impact to NGI **40%**,
   cost-effectiveness **30%**. (→ Q1, Q6, Q8 carry the most weight.)
3. **Second stage:** clarifying questions + fact-checking by email — be responsive.
4. **Independent review committee** validates eligibility and value-for-money.
5. **MoU** signed → execute tasks → **invoice per completed milestone** (nothing paid upfront).

Expect a few months from deadline to signature.

---

## 5. Next-steps checklist

- [ ] Subscribe to NLnet newsletter; watch <https://nlnet.nl/propose/> for the autumn general
      call. **The "after summer 2026" date has now arrived (today is 2026-08-12) — check now
      whether the call has reopened.**
- [ ] Attend one NLnet Office Hour to confirm fit.
- [ ] Confirm AGPL-3.0 as the on-award licence.
- [ ] Fill Q2 track-record specifics.
- [ ] Link existing Lisp-prototype videos; record the new AI-forward Julia video + add README
      GIFs; paste links into the admin fields, Q1 and Q8.
- [ ] Final concision pass on all eight answers.
- [ ] Submit the day the general call opens.

---

## Sources

- NLnet — Propose / open calls: <https://nlnet.nl/propose/>
- NGI Zero Commons — Guide for Applicants: <https://nlnet.nl/commonsfund/guideforapplicants/>
- NLnet — transition notice (1 Aug 2026 call): <https://nlnet.nl/news/2026/20260601-call.html>
- NLnet Office Hour: <https://nlnet.nl/officehour/>
- NLnet — Open Application for Project Financing: <https://nlnet.nl/foundation/request/application.html>
- ProjecturEd demo channel (Lisp prototype): <https://www.youtube.com/@projectured>
</content>
