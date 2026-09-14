# Code quality

> **Kind:** rule · **Status:** current · **Stands on:** [architecture-invariants.md](architecture-invariants.md)

How the code of this repository reads, and what keeps it readable. A human reads
this code to learn what it does. Every rule here serves that reader.

The rules that hold in all three repositories are in
`omnet-team/policy/code-quality-rules.md`. Read them first. This document adds
what is true here: the shape of a file, the local rules, the size budgets, and
the measured baseline. It never weakens a shared rule.

## What this document does not cover

| Subject | Owner |
| --- | --- |
| Names of types, functions, files, and modules | [documentation/rule/naming-rules.md](naming-rules.md) |
| What belongs in which package, layer, slice, and module | [architecture-rules.md](architecture-rules.md) |
| What the code must do | [architecture-requirements.md](architecture-invariants.md) |
| The words for the divisions and the pipeline | [terminology.md](division-terminology.md) |

`naming.md` is the authority on every name. This document starts where a name
ends.

## 1. The shape of a file

**A module file** carries the docstring, the header, the ordered includes and
`__init__`. It holds no other code.
[JsonModule.jl](../../source/json/JsonModule.jl) shows a slice's and
`CellModule.jl` a kernel layer's.

**The header is three blocks, in this order:** every `using`, sorted by module
name; then every `import`, under a comment that says the module extends those
names; then every `export`. A module exports only what no macro exports for it —
`@document`, `@domain` and `@projection` each export the type they declare.

**A fragment file opens with a one-line comment**, not a docstring:

```julia
# Fragment of `CellModule` — the plain mutable, non-reactive cell kind.
```

65 files carry that header. This repository uses that form and not the box
comment that the other two repositories use. The header says which module
owns the fragment and what the fragment adds.

**A contract fragment says where each body lives**, so a reader who wants the
implementation does not have to search.
[DocumentInterface.jl:1](../../source/kernel/document/DocumentInterface.jl#L1)
is the model: it names `DocumentDefaults.jl`, `DocumentCopy.jl`,
`DocumentSync.jl`, `DocumentWalk.jl`, and `DocumentMacro.jl` in its first seven
lines.

**A section banner divides a long file.** The form is a comment, the section
name, and box-drawing dashes to about column 78:

```julia
# ── Insertion factories ─────────────────────────────────────────────────────
```

This repository uses the banner more than the other two. A banner is not
decoration. It is the table of contents of the file. A banner that only repeats
the name on the next line is decoration, and it goes.

**A registration seam goes at the bottom of its fragment.**
[JsonToSyntax.jl](../../source/json/JsonToSyntax.jl) ends with
`make_document_seed`, the document an empty `.json` starts from. The seam is
last because it is the outward face of the file. The `import` it needs sits in
the module file with the rest of the header, so one file holds every import of
the module.

## 2. A comment says what is, never what was

**Source describes the code as it stands.** A comment, a docstring and a
fragment header answer one question: what is this, and what does it promise.
None of them answers what it was before, what it was called, where it moved
from, or which refactor put it here.

History belongs in a plan under [plan/done/](../../plan/done/), and the rest is
in the commit. The plan already holds the reason, the alternatives and the
measurement, so a reader who wants the past has a better place to look. A reader
who wants the present should not have to step over the past to reach it.

**Delete a history comment. Do not rewrite it.** If it carries a constraint the
code cannot show, keep that one sentence in the present tense and drop the rest.

**A comment that names code in another file goes stale.** `JsonFile.jl` ended
with a comment about `__init__`, which lives in `JsonModule.jl`. Put the comment
where the code is.

**A past tense is fine when it is about a run, not about a refactor.** `# The
cell was written before this read` describes what happens at run time.

### The forms that break this rule here

The word list in the shared policy catches only some of them. Measured in
`source/` on 2026-09-14:

| Form | Example | Count |
| --- | --- | ---: |
| A banner that names the file's own past | `# Folded in from JsonParser.jl.` | 0, was 166 |
| A past tense about the code | `# ProjecturedNatural used to hold this` | 0, was 25 |
| A statement of what is gone | `# … a sign that no longer …` | 13 |
| A rename record | `# … renamed from …` | 6 |
| The narrow word list | `previously`, `now we` | 3 |

The banner was the one that got through. `# Folded in from JsonParser.jl.` sat
at the top of `JsonParser.jl`, named the file it already was, and used none of
the banned words. There were 166 of them, and they are gone: each now opens with
the module that owns the fragment.

The other four forms need a reader, not a grep. 27 lines still match, and 26 of
them are legitimate: in `# Used to size an output to the content`, `used to`
means *is used to*, and `# a rect whose row no longer exists` describes a run,
not a refactor. The twenty-seventh is in a sealed file,
`kernel/selection/SelectionDefaults.jl:76`, and waits for permission.

A check, not a verdict:

```sh
grep -rniE '^\s*#.*\b(folded in from|previously|used to|was changed|now we|formerly|no longer|originally|renamed|TODO|FIXME|XXX|HACK)\b' source --include='*.jl'
```

`# Used to size an output to the content` is a legitimate hit, because there
`used to` means *is used to*. Read every hit before you delete it.

## 3. Local rules

**A contract fragment holds no body.**
[DocumentInterface.jl](../../source/kernel/document/DocumentInterface.jl) is
193 lines of docstring and `function f end`. Every body lives in a named
sibling. A reader who wants the promise reads one short file.

**A trait keeps a concrete type out of a lower layer.** The document layer names
no concrete collection type, because `is_element_collection` and
`is_collection_field_type` ask instead. A list of types in a lower layer is a
dependency in the wrong direction.

**A projection delegates through its child.** An object projection sends each
entry to the entry projection rather than inline. The comment in
[JsonToSyntax.jl:66](../../source/json/JsonToSyntax.jl#L66) says why: the child
then projects on its own as well.

**Use `@projection_template`, not a hand-written printer and reader.** The
template gives the reader and keeps the pair in step. A hand-written pair needs
a reason.

**Use the macros.** `@document`, `@projection`, `@iomap`, and `@reference_case`
declare a schema once. `naming.md` states that none of the coded prefixes is
ever hand-rolled.

**A sealed file is frozen.** [`SEALING.md`](../../SEALING.md) holds the list. A quality fix is not a
reason to change a sealed file, and a wide sweep is exactly where one gets
changed by accident. List the sealed files before a sweep and exclude them.

## 4. Size budgets

| Thing | Today | Budget |
| --- | --- | --- |
| Line width | median 43, 90% under 81, 95% under 86 | 90 characters |
| A main-code function | median 9 lines, 90% under 30, longest 200 | 60 lines |
| A file | mean 216 lines, 61 over 500 | 500 lines |

The four longest hand-written files are `WidgetToGraphics.jl` at 6392 lines,
`ProjecturedSdl.jl` at 3033, `Widget.jl` at 2107, and `SqlToSyntax.jl` at 2095.
They are far over the budget. Do not sweep them. When you next work in one, take
one section out into its own fragment.

A test function is exempt. `test_reference_rules()` is 1049 lines, and it reads
better as one list.

`package/repl/PrecompileStatements.jl` is generated. No rule applies to it.

## 5. The measured baseline

Reproduce these with the commands in
`omnet-team/policy/code-quality-rules.md`. A number that grows without a
reason is the signal the steward watches.

| Measurement | 2026-08-14 |
| --- | --- |
| Julia files | 755, mean 216 lines |
| Main-code files | 380 |
| Main-code function blocks | 2816, mean 14 lines |
| Export statements | 874 |
| Docstrings | about 2090 |
| Comment lines | 21050 |
| Comment lines with a history word or a marker | 51 |
| Imports: blanket against named | 1013 against 2118 |
| Private helpers with a leading underscore | 2809 |
| Section banners | 1451 in 264 files |
| Fragment headers | 63 |
| Inline field comments | 362 |
| Files over 500 lines, generated file excluded | 61 |
| File names that carry a schedule instead of a subject | 0 |

**The 51 was an undercount.** The command behind it looks for eight words. It
did not see `# Folded in from …`, which is a banner and not a sentence, and
`source/` held 166 of those — so history in a comment stood at about 210 lines,
not 51. The banners are gone, and so are the nineteen word-list
lines that really were history. 27 still match, 26 of them legitimately. The
size of the four largest files is the other weak point.

## 6. Where this repository differs from the other two

An agent that crosses repositories must not carry a habit over.

| Point | Here | the other two |
| --- | --- | --- |
| File header | `# Fragment of \`XModule\` — job` | a `# ====` box comment |
| Section banner | heavy, 1451 | 523 and 51 |
| Requirement prefix | `PAR-`, `PR-` | `OR-`/`OAR-` and `IR-`/`IAR-` |

## 7. How this document is used

The code quality steward audits a slice when its plan moves to `plan/done/`. It
measures first, then reads the files that the plan touched, then writes a reader
report: every place where its understanding broke, with the file and the line.

The steward proposes. The human accepts a new rule into this document. No large
cleanup starts before that.
