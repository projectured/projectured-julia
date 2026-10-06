# ProjecturEd

A Julia reimplementation of [ProjecturEd](https://github.com/projectured/projectured), a generic-purpose projectional editor. Documents are structured data (trees, ASTs, graphs) presented through bidirectional, composable projections; editing acts on the projection and is mapped back to the underlying domain.

## 🔒 Sealed files

**Some files in this repository are sealed. Read [SEALING.md](SEALING.md)
before modifying anything: a file marked `🔒` there MUST NOT be modified by an
AI in any way unless the user gives explicit permission for that specific file
in the current conversation.** If a change you are asked to make would require
editing a sealed file, STOP and ask. `SEALING.md` also holds the audit protocol
and the full audit-order inventory of `source/kernel/`.

## Before working in this repo

Read the guides in [documentation/](documentation/) before a change that is not trivial. The index is [documentation/README.md](documentation/README.md), and it names every document with what it answers.

The short path:

1. [documentation/design/concepts.md](documentation/design/concepts.md) — what a document, a view, an edit and the tool set are. Start here.
2. [documentation/design/engineer-tour.md](documentation/design/engineer-tour.md) — the same system in code.
3. [documentation/design/system-anatomy.md](documentation/design/system-anatomy.md) — the packages, the layers of the kernel, and what depends on what.
4. [documentation/rule/](documentation/rule/) — the rules a change must keep: naming, packages, architecture, code quality, writing. **Read [naming-rules.md](documentation/rule/naming-rules.md) before you write a name.**

Each package has a design document in [documentation/package/](documentation/package/README.md), one folder per slice: how the package works, how it fits with the others, and why it is built so. Read the document of a package before you change it. When you touch selection and reference handling, read [reference.md](documentation/package/kernel/reference.md) and [selection.md](documentation/package/kernel/selection.md); when you add or change a domain, read [domain-anatomy.md](documentation/design/domain-anatomy.md), [domain-inventory.md](documentation/design/domain-inventory.md) and [new-domain-guide.md](documentation/guide/new-domain-guide.md).

When you iterate in a session: [debugging-guide.md](documentation/guide/debugging-guide.md) and [testing-guide.md](documentation/guide/testing-guide.md).

## Naming

**Before you name anything — a file, a module, a type, a function, a constant —
read [documentation/rule/naming-rules.md](documentation/rule/naming-rules.md)
and follow it.** The law is also an architecture invariant, `PAR-NAMING-LAW`,
so a name that breaks it fails the audit that every file passes before it is
sealed.

The parts that are broken most often:

- **Every function name starts with a verb**, and the verb follows the nature
  of the work: `find_` searches and can return `nothing`, `get_` reads a value
  at a known place, `compute_` does real work, `make_` creates a new something.
- **A predicate is `is_…` or `has_…`**, or a plain verb that reads as a
  question at the call site.
- **A function that mutates ends with `!`**, and an external side effect counts.
- **No ad-hoc abbreviation**: `operation` not `op`, `reference` not `ref`,
  `column` not `col`, `evaluation` not `eval`, `navigation` not `nav`,
  `context` not `ctx`. The sanctioned short forms are `api`, `iomap`, `ctrl`,
  `alt`, `meta`, `ctor` and `expr`.
- **An operation type is a verb-first phrase** ending in `Operation`; an event
  is `<Source><Action>`; an exception ends in `Exception`.

**To rename an existing name, use `workspace/bin/julia-rename.jl`.** It walks
the syntax tree that Julia's own parser builds, so it tells a call from a field
access, a local variable, a keyword argument and a word in prose. A text
substitution can not, and it will corrupt the code. Run it with `--report`
first, and read `--show-other` before you trust a rename whose `other` count is
not zero. The parser skips a string and a docstring by design, so a second pass
must update the prose that names the function.

## Comments and documentation

**Source describes the code as it stands. It never records what the code was.**
No "folded in from", no "used to", no "previously", no "renamed from", no note
of which refactor put a thing where it is. A comment, a docstring and a fragment
header all answer one question: what is this, and what does it promise.

History goes in the plan under `plan/done/`, which already holds the reason and
the alternatives, and in the commit message. A reader of the source wants the
present and must not have to step over the past to reach it.

When you find a history comment, delete it. If it carries a constraint the code
cannot show, keep that one sentence in the present tense and drop the rest. The
full rule, the forms that break it, and a grep that finds them are in
[documentation/rule/code-quality-rules.md](documentation/rule/code-quality-rules.md)
under "A comment says what is, never what was".

## Conventions

- All indexing is 1-based (Julia convention).
- Projections must be bidirectional: every printer needs a matching reader, and the IO map is what makes the inversion possible.

## Testing a change

When you change something and want to verify it, run the **smallest test that covers the change** — do not blindly run `test_all`. It is slow and its output floods the context with tokens.

Pick the narrowest scope that exercises your change:

- A single example: `test_printer(json_example)`, `test_reader(json_example)`, `test_position_navigation(json_example)`, `test_repl(json_example)`, or `test_example(json_example)` for all three at once. Add `test_position_navigation(json_example; check_reaches_all=true)` to also assert navigation reaches every enumerated position.
- A single domain or pipeline stage: e.g. `test_json_document()`, `test_syntax()`, `test_json_to_syntax()`, `test_syntax_to_text()`.
- One package's whole suite: `test_kernel()`, `test_platform()`, and one per domain — `test_json()`, `test_sql()`, … Each is its own test package (`package/Projectured<Name>Test`) that only depends on the packages below it, so these also run in an environment without SDL/ODBC/Tulip installed (`julia --project=package/ProjecturedKernelTest`, etc.). Each includes its package's static layering guard (`test_kernel_layering()`, `test_json_layering()`, …).
- The reactive primitive only: `test_cell()`.
- Want errors back as a `Vector{String}` instead of `@testset` output (less noise, keeps going on failure): the walker helpers `walk_printer_output(doc, proj)`, `walk_repl_loop(doc, proj)`, `explore_position_selections(doc, proj)`.

Running `test_all()` is usually not needed — the targeted test above is enough to verify a change. Only reach for the per-package aggregators (`test_kernel()` / `test_platform()` / the eighteen `test_<domain>()`), the loop-over-every-example functions (`test_printers()` / `test_readers()` / `test_position_navigations()` / `test_repls()`), and rarely `test_all()` (which runs every per-package suite plus the umbrella integration tests, and takes about 47 minutes), when you specifically want a broad sweep after the targeted test already passes. See [documentation/guide/testing-guide.md](documentation/guide/testing-guide.md) for the full table of test functions and which package each one covers.

Always narrow down tests to the smallest reasonable scope — never default to `test_all()`, it is slow. Prefer single-example or single-domain test functions as described in the "Testing a change" section above.

**Reading the summary.** An unmarked `Fail` or `Error` is a regression from your change — do not need to bisect to know. Known-failing assertions are marked `@test_broken` and appear in the `Broken` column; only `Fail` / `Error` counts should be zero after a passing run. If the count of `Broken` changes, read the `# @broken:` comment on the marker: fewer broken means an assertion started passing (promote it to `@test`); more broken means a new marker was added. See the "Marking known-failing tests" section in [documentation/guide/testing-guide.md](documentation/guide/testing-guide.md).
