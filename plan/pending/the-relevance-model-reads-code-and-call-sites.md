# The relevance model reads the code and the call sites

Status: **deferred**, 2026-09-29. Nothing is implemented. The owner: "let's
defer adding call sites for now, we will come back to this when we have more
real life examples", and of the code of the definition: "clearly there will be
docstring for all function that the AI will use"; the code helped only names
with no docstring. The evidence of §3 comes from 60 answers drawn at random
and questions a model wrote from code; real requests of real users are the
evidence to wait for. It builds on the branch `classifier-search`, which is not
on `main` yet (§7, question 4).

## 1. The request

Step 4c of `a-classifier-ranks-the-search.md` measured what a classifier ranks
when it also reads the first lines of the definition of each name and its call
sites. The owner said before it: "We can assume that some documentation needs
to be written for each function. But in general the usage examples will
probably not be there and certainly not tuned for the task." After it, to "Should
I plan that change?": "Yes".

The change: the text of an entry that the `RelevanceModel` of the kernel reads
holds the code of its definition and its best call sites, in a Julia session and
in a built binary.

## 2. What exists

- **The kernel** (on the branch): `RelevanceSearch.jl` of `ToolModule`.
  `_make_relevance_text(entry)` gives the relevance model the name, the kind,
  the signature and the documentation of an entry, cut at 1,500 characters.
  `_make_relevance_line(entry)` gives a choice the name and the first sentence.
  Decision 7 of §8c of the measurement plan kept the call sites out.
- **The measurement code** (on the branch): `ProjecturedKernelExample` holds
  `collect_call_sites`, `rank_call_sites`, `format_call_sites`,
  `find_module_folder` and `collect_definition_code`, with their tests. They
  parse the Julia files with `Base.JuliaSyntax`; the scan of about 3,500 files
  took 1.1 s.
- **The builder**: `PROJECTURED_ASSETS` in `source/builder/ProjecturedProgram.jl`
  copies the documentation and the web assets into `share/projectured/` of a
  bundle, and `_get_bundle_directory` finds that folder at run time. The meaning
  vectors are computed at run time and kept in a file per model.

## 3. The evidence

Step 4c, 60 answers drawn at random with at least four call sites, questions
written from a call site the rankers do not show; Jev as a cascade on the 5,187
entries of the IDE (first / in five / in ten, of 20):

| answers | the meaning vectors | Jev | Jev, code | Jev, code and call sites |
| --- | --- | --- | --- | --- |
| no docstring | 0 / 0 / 1 | 5 / 10 / 15 | 6 / 14 / 17 | 9 / 17 / 18 |
| short docstring | 3 / 5 / 6 | 11 / 15 / 18 | 10 / 15 / 19 | 12 / 16 / 18 |
| longer docstring | 6 / 9 / 12 | 13 / 15 / 16 | 13 / 16 / 16 | 14 / 16 / 16 |

- With no docstring, the code and the call sites take the cascade from 5 to 9
  first and from 10 to 17 in five: almost what a short docstring gives.
- With a docstring they never cost a place, and they add one or two first.
- The meaning vectors do not gain from either (Step 1, Step 4c).
- Only the cascade reaches a name with no docstring; a pool of words and
  vectors does not hold it.

## 4. The design

### 4a. The text of an entry

The relevance model reads, after the documentation:

- **`code:`** — the first 15 lines of the definition, from the line that
  defines the name, cut at 800 characters. The docstring is above that line, so
  it is not read twice.
- **`calls:`** — the three best call sites, a call from outside the folder of
  the module first, one per calling function, one per file first; each the file,
  the line, the calling function and the line of the call, cut at 160
  characters.

Always, and not only for a short docstring: the evidence says they never cost a
place, and a rule by length is one more number to tune. The cost is about 250
tokens more per scored entry: about 15,000 more per cascade, $0.0006 at the
price of Jev.

### 4b. The line of a choice

A name with no first sentence shows the first line of its code, as Step 4c did:
`Module.name: function name(argument)`. The names with a first sentence keep
it.

### 4c. The meaning vectors

No change. The measurements gave them no gain from the code or the call sites,
and a vector of a changed text would be computed again for every entry.

### 4d. Where the texts come from, in a Julia session

A new fragment of `ToolModule`, `SourceText.jl`, takes the functions of the
measurement code as they are: the scan of call sites with the parser of Julia,
their ranking, their format, and the code of a definition. The example package
then calls the kernel and holds no copy.

- **The roots.** The repository of the kernel, which the kernel finds as it
  finds its documentation, and the roots an application registers with a new
  `register_source_root!(directory)`, as it registers its guides with
  `register_guide_root!`. The folders read under a root are `source`,
  `example`, `test`, `tool` and `documentation` (the Julia blocks of a guide).
  omnet-julia registers its repository in `OmnetCampaignUi.__init__`, beside its
  guides.
- **The index.** The texts of the entries of one declaration, built at the first
  search by relevance and kept per declaration, as the API index is kept in
  `_DECLARED_INDEX`. It is process-global under the same carve-out of
  PAR-PER-EDITOR-STATE: it is derived from source files that do not change while
  the process runs, and it is the same for every editor that declares that list.
  One lock guards the build.
- **An edit in a running process** reaches the index only after a restart, as
  it reaches the API index now.

### 4e. Where the texts come from, in a built binary

A binary holds no source. The builder writes the texts of every function and
type of the program into `share/projectured/source-text.bin` at build time, in
the build environment, where the source is: one record per qualified name, its
code and its call sites. The kernel reads the file when the bundle folder
exists, and scans the source otherwise. A bundle without the file ranks with
the documentation alone, as the kernel does now.

The file is about 5,000 records of about 1.3 KB: a few megabytes. A bundle of
the source folders instead would be about 15 MB of Julia code and 42 MB of the
test data of omnet-julia, and it would ship the tests.

### 4f. What the answer shows

Nothing changes in what a hit shows the model: the code and the call sites are
read by the relevance model only. A hit still shows its signature and its first
sentence, and one clear hit its docstring.

## 5. Steps

- [ ] **Step 0. The owner answers §7.**
- [ ] **Step 1. `SourceText.jl`.** The five functions move from
  `ProjecturedKernelExample` into the kernel, with their tests into
  `test/kernel/tool/`. The example package calls them. The naming guard and the
  layering guard of the kernel pass.
- [ ] **Step 2. The roots and the index.** `register_source_root!`, the index
  per declaration, and the registration in omnet-julia. A test with a folder of
  its own.
- [ ] **Step 3. The text and the line.** `_make_relevance_text` and
  `_make_relevance_line` read the index. `test_relevance_search` checks both.
- [ ] **Step 4. The binary.** The builder writes the file; the kernel reads it;
  the test of the builder checks that the bundle holds it.
- [ ] **Step 5. The measurement.** The questions of Step 4c through the
  `search_api` of the kernel, end to end, with Jev: the ranks must match the
  ranks of the harness within a question or two. The time of the first search
  that builds the index is a timing, so it runs on an idle machine with the word
  of the owner.
- [ ] **Step 6. The documentation.** `documentation/package/kernel/agent.md`
  says what the relevance model reads and where it comes from.

## 6. Rules

The rules of a run of `a-classifier-ranks-the-search.md` §7 hold: memory, the
key, the limit of cost of the ledger, the work in the worktree with a commit per
step, and this plan updated as the steps are done.

## 7. Questions for the owner

1. **Tests and examples as call sites.** They are the best usage a scan finds,
   and Step 4c read them. In a product they are read from the checkout or from
   the file of the build, and never shipped. Is that right?
2. **The context.** Still open from before: should the agent loop pass the
   request of the person as the context, with the `context` parameter out of the
   tool schema (a field of the `ToolSet` that the assistant sets at each turn)?
   It is a separate change; I would plan it apart.
3. **The backend.** The product needs a package for the Decisions API of
   OpenRouter (for Jev), where the measurement used a script. A separate plan?
4. **The branch.** This plan builds on `classifier-search`, which holds the
   `RelevanceModel` and is not on `main`. Land it first, after the kernel suite
   and the IDE tests pass, or build this on it and land both together?
