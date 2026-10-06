# Code quality

> **Kind:** rule · **Status:** current · **Stands on:** [architecture-invariants.md](architecture-invariants.md)

How the code of this repository reads, and what keeps it readable. A human reads
this code to learn what it does. Every rule here serves that reader.

This document holds the rules of this repository: the shape of a file, the
local rules, the size budgets, and the measured baseline. Where a rule is about
a name, [naming-rules.md](naming-rules.md) is the one that decides; where it is
about a document, [writing-rules.md](writing-rules.md) is.

## What this document does not cover

| Subject | Owner |
| --- | --- |
| Names of types, functions, files, and modules | [documentation/rule/naming-rules.md](naming-rules.md) |
| What belongs in which package, layer, slice, and module | [architecture-rules.md](architecture-rules.md) |
| What the code must do | [architecture-invariants.md](architecture-invariants.md) |
| The words for the divisions and the pipeline | [division-terminology.md](division-terminology.md) |

[naming-rules.md](naming-rules.md) is the authority on every name. This document starts where a name
ends.

## 1. The shape of a file

**A module file** carries the docstring, the header, the ordered includes and
`__init__`. It holds no other code.
[JsonModule.jl](../../source/domain/json/JsonModule.jl) shows a slice's and
`CellModule.jl` a kernel layer's.

**The header is three blocks, in this order:** every `using`, sorted by module
name; then every `import`, under a comment that says the module extends those
names; then every `export`. A module exports only what no macro exports for it.
`@document`, `@domain` and `@projection` each export the type they declare.

**The export block has one statement for each fragment, in the order of the
includes.** A statement names what one fragment defines, in the order that the
fragment defines it. A reader who finds a name in the block then knows which
file to open, and a reader of a fragment finds all its public names in one
place. The interface fragment comes first. Its statement names every generic
that it declares, also when a sibling file holds the body. A fragment that
defines no public name has no statement. Do not put a comment inside the block:
the docstring of the module says what each fragment holds.
[CellModule.jl](../../source/kernel/cell/CellModule.jl) shows the shape, and
`test_exports()` checks it.

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
[JsonToSyntax.jl](../../source/domain/json/JsonToSyntax.jl) ends with
`make_document_seed`, the document an empty `.json` starts from. The seam is
last because it is the outward face of the file. The `import` it needs sits in
the module file with the rest of the header, so one file holds every import of
the module.

**A name a window declares to a model documents its use.** A declared name is
what a model finds by searching, and the searches read its docstring: the
keyword scorer reads the signature and the first sentence, the meaning model
reads the whole text. A docstring that says only what the thing is, in the
words of its implementation, is not found by the words a person uses. So a
declared function or type has four parts, in this order:

```julia
"""
    make_result_plot(frames::DataFrame...; title) -> SimulationPlotDocument

A chart of every `frame` given, as a document.

Use it to draw a value over time, to compare the runs of a sweep, or to see
the shape of a histogram. The frame decides the chart: …

# Example

    vectors = get_simulation_vector_results(get_project_result_directory())
    open_pane!(make_result_plot(vectors; title = "Delay"))

See also `make_result_table`, which shows the same frame as rows.
"""
```

- The first sentence says what it is; a search hit shows it.
- The **Use it to** paragraph says the goals it serves, in the words a person
  says: "draw", "over time", "compare". The meaning vector and the keyword
  prose score read it.
- The **Example** is one call that runs in the window that declares the name;
  a model copies a shape more than it reads a signature. In a kernel file the
  Example uses kernel names only, and the package that declares the name to a
  window shows that call itself (`PAR-NO-CONSUMER-DOCS`).
- **See also** names the neighbours a model confuses it with.

A name the assistant can reach without its "Use it to" paragraph is found by:

```bash
grep -rlE '^Use it to ' --include='*.jl' source | sort > /tmp/documented
```

The names that matter are the ones `search_api` ranks, which is every exported
name of the loaded packages. A name a model is expected to call, and that has
no such paragraph, is the work left.

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

**A comment that names code in another file goes stale.** A comment about
`__init__` belongs in `JsonModule.jl`, where `__init__` lives, not in
`JsonFile.jl`. Put the comment where the code is.

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

The other four forms need a reader, not a grep. Most lines that still match are
legitimate: in `# Used to size an output to the content`, `used to` means *is
used to*, and `# a rect whose row no longer exists` describes a run, not a
refactor.

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
[JsonToSyntax.jl:66](../../source/domain/json/JsonToSyntax.jl#L66) says why: the child
then projects on its own as well.

**Use `@projection_template`, not a hand-written printer and reader.** The
template gives the reader and keeps the pair in step. A hand-written pair needs
a reason.

**Use the macros.** `@document`, `@projection`, `@iomap`, and `@reference_case`
declare a schema once. [naming-rules.md](naming-rules.md) states that none of the coded prefixes is
ever hand-rolled.

**A sealed file is frozen.** [`SEALING.md`](../../SEALING.md) holds the list. A quality fix is not a
reason to change a sealed file, and a wide sweep is exactly where one gets
changed by accident. List the sealed files before a sweep and exclude them.

## 4. Arguments: positional for what the name says, names for the rest

**Prefer at most three positional arguments.** This is advice, not a limit. A
fourth positional argument is fine when the name of the function implies it. A
name at a call site says what a value is. An order says nothing, and a reader can not
check it without opening the definition, so an argument that the name of the
function does not imply takes a name.

**A positional argument is one that the name of the function already names.**
The subject comes first — the document, the store, the editor of
`evaluate_operation(editor, operation)` — and then the arguments that the verb
implies. `open_pane!(document)` needs no names. If a reader can not say what an
argument is from the name of the function, that argument takes a name of its
own.

**A verb takes its editor as a keyword.** A verb that a person or a model calls
takes `editor = get_evaluation_editor()`, so its call in the evaluator names no
editor, and code that has an editor passes it as `editor`. PAR-PER-EDITOR-STATE
says where the default comes from.

**A `Bool` is never positional.** `clip_child_to_slot(…, true, false)` says
nothing; `clip_x = true, clip_y = false` says everything. A `Symbol` that picks a
mode takes a name as soon as a second `Symbol` stands beside it, as in
`orientation = :vertical, side = :right`.

**Two arguments of one type that a caller could swap take a name**, at least one
of the two: two `PaneGroup`s, three `Vector{Int}`s, a lower and an upper bound,
the name and the description of a `Tool`.

**Anything that a caller may leave out is a keyword.** A definition takes at most
one optional positional argument, and never one beside a keyword argument. This
is a recommendation, not a hard rule, and an exception says why on the line above
the definition:

```julia
# @optional: the name of the example stands first, as at a command line.
function run_example(name = "json"; backend = nothing)
```

A short form of a protocol method is a method of its own, not a default value:
`copy_document(K, value)` calls `copy_document(K, value, nothing, 0)`, so a type
that adds the protocol method writes its full signature once.

**A parameter that arrives later is a keyword.** Every call that exists stays
valid, and every new call says what the new value is. This half of the rule is
about change rather than about reading.

**More than five keyword arguments is a type that is missing.** Make the
geometry, the style or the policy a struct of its own and pass that. A function
with eight parameters holds a type; a long keyword list spells that type out at
every call instead.

**A constructor takes what the document is, and names its chrome.** The content,
the centre and the radius stand positionally; a style, a view state and an option
take names. `WidgetLabel(content; position, text_style, padding, tooltip)` is the
shape.

### The guard

`test/suite/arguments.jl` is the guard, and `test_arguments()` runs it. A public
definition fails when it takes more than one optional positional argument, or one
beside a keyword argument, and no `# @optional:` marker stands above it. A
`# @positional:` marker fails too, because no rule needs it: the count is advice.
A port keeps the whole signature of the program that it
mirrors, default arguments included, so a definition in a port folder needs no
marker. `julia test/suite/arguments.jl --report` and `julia
tool/survey-arguments.jl` print the count of positional arguments across the
code, the private helpers included; nothing fails on it.

**The public functions come first.** A private helper inside one file costs one
reader one file. A public function costs every call site and every caller that
comes later. [plan/done/keyword-arguments.md](../../plan/done/keyword-arguments.md)
holds the list, the waves and what is deferred.

## 5. Size budgets

| Thing | Today | Budget |
| --- | --- | --- |
| Line width | median 43, 90% under 81, 95% under 86 | 90 characters |
| A main-code function | median 9 lines, 90% under 30, longest 200 | 60 lines |
| A file | mean 216 lines, 61 over 500 | 500 lines, as a signal |

**The size of a file is a signal, not a limit.** A file over 500 lines is a reason
to look for a boundary in it, not a reason to split it. Split a file only at a
good boundary: a part with its own concept, its own readers and a small interface
to the rest. Where no such boundary exists, the file stays whole, whatever its
length. The four longest hand-written files are `WidgetToGraphics.jl` at 6392
lines, `ProjecturedSDL.jl` at 3033, `Widget.jl` at 2107, and `SqlToSyntax.jl` at
2095.

A test function is exempt. `test_reference_rules()` is 1049 lines, and it reads
better as one list.

The statement files `package/*/precompile/*.txt` are generated. No rule applies
to them.

## 6. The measured baseline

Each number below comes from the command beside it. A number that grows
without a reason is the signal to look at the file that grew.

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
| Definitions over three positional arguments | 835 of 7158 |
| Of those: a protocol method, a public function, a private helper | 341, 137, 357 |

The two rows about arguments were measured on 2026-09-22 with `julia
tool/survey-arguments.jl`, over `source/` and `example/`. Every other row is of
2026-08-14.

**The 51 was an undercount.** The command behind it looks for eight words. It
did not see `# Folded in from …`, which is a banner and not a sentence, and
`source/` held 166 of those — so history in a comment stood at about 210 lines,
not 51. The banners are gone, and so are the nineteen word-list
lines that really were history. On 2026-09-29, 30 still match, 29 of them
legitimately. The size of the four largest files is the other weak point.

## 7. Where this repository differs from the other two

An agent that crosses repositories must not carry a habit over.

| Point | Here | the other two |
| --- | --- | --- |
| File header | `# Fragment of \`XModule\` — job` | a `# ====` box comment |
| Section banner | heavy, 1451 | 523 and 51 |
| Requirement prefix | `PAR-`, `PR-` | `OR-`/`OAR-` and `IR-`/`IAR-` |

## 8. How this document is used

The code quality steward audits a slice when its plan moves to `plan/done/`. It
measures first, then reads the files that the plan touched, then writes a reader
report: every place where its understanding broke, with the file and the line.

The steward proposes. The human accepts a new rule into this document. No large
cleanup starts before that.
