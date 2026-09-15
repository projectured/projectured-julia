# A file reference is not a document node

## The problem

A document graph is saved as text files, and a tree that spans files needs to say
"this continues in that file". Today that statement is a **node in the document**:
`ReferenceStub`, a `Document` that stands for a marker, plus a `FileDocument`
child that stands for an embedded file. The loaded document carries both, and
every domain carries two projections to draw them as source.

That leaks storage into the document, and it breaks in three places.

**A mixed document cannot hold a reference.** [MixedProjectionExample.jl](../../example/xml/MixedProjectionExample.jl)
merges the json and xml tables by hand. It has no `ReferenceStub` row, and it
cannot have one: a stub inside a `JsonObjectEntry` must print as a quoted JSON
string, and a stub inside an `XmlElement` as a `pred:ref` element. One row, one
spelling. `TypeDispatchingProjection` throws on a type with no row, so a marker in
a mixed document throws.

**The same node draws two ways, and depth decides.** The substrate registers
`ReferenceStub => ReferenceStubToSyntax()`, which prints the resolved *content*.
Each domain registers `ReferenceStub => ReferenceStubTo<Domain>SyntaxLeaf()`,
which prints the marker *source*. A stub at the top of the natural table is
content; the same stub one level down inside a JSON document is source.

**A document made in the editor has no stubs at all.** A user can build an
`XmlFile` and a `JsonFile` that hold substructures of each other, directly, and
never see a marker. The stub exists only because a load put it there. So the
machinery serves the loader, not the document.

The measured cost: `FileProject.jl` 902 lines, `fileformat/` 558, five
`*File.jl` at 720, and about 470 stub and marker mentions across five domains.
The two suites that exercise the embed card, `MarkdownEmbedTest` and
`RstEmbedTest`, fail on a clean `main`, 3 fails and 2 errors each.

## The principle

**A file reference is a fact about storage. It lives in the file, never in the
document.** The document in memory is the real graph: a JSON object holds the
XML element, the XML element holds the JSON object, a shared subtree is one
object reached twice, a cycle is a cycle. Nothing in it says "file".

Saving turns the graph into files. Loading turns the files back into the graph.
The marker exists only on disk, in the host format's own vocabulary, so every
file stays a legal document of its format.

## What stays and what goes

| stays | goes |
| --- | --- |
| `FileDocument` and `is_file_document` — the cut points, a `filename` and a `content` | `ReferenceStub` |
| the marker grammar: `<<expr>>`, parsed by Julia's parser, run by the small interpreter, never `eval` | `resolve!`, `resolve_stubs!`, the marker drain, `LoaderContext.intern` |
| `register_marker_function!` and the verbs `file`, `section`, `definition` | `ReferenceStubTo<Domain>SyntaxLeaf` and `EmbeddedFileDocumentTo<Domain>SyntaxLeaf`, five pairs |
| `print_natural_text` — each file is still written in its natural notation | the generic `ReferenceStubToSyntax` and `FileDocumentToSyntax` rows |
| the write gate — a file whose bytes did not change is not written | each domain's `_substitute_markers` walk |

Each domain keeps **one pair of small functions** in place of two projections and
a walk: how to *make* a reference leaf in its own notation, and how to *recognise*
one.

## The design

### The save walk

Saving is a projection stage in front of the natural notation. For each file, it
copies the content until it must cut, and at a cut it puts a **reference leaf of
the file's own domain** — a `JsonString`, a `pred:ref` element, a `.. pred-ref::`
directive, a fenced block, a `pred_ref(…)` call. The copy is a pure document of
one domain, so `print_natural_text` prints it with no special rows.

`visit(node)` in the copy of file `F`:

1. `node` is a file document → a reference leaf `file("name")`.
2. `node` is owned by another file → a reference leaf naming that file and the
   path inside it.
3. `node` is owned by `F` and this copy has visited it → a reference leaf naming
   `F` and the path of the first visit. A shared subtree inside one file is
   written once.
4. `node` is owned by `F` and not yet visited → copy it and recurse.
5. `node` has no owner → an **orphan**. Record the error and abort the save.

The walk copies a node of the file's domain and the substrate collections that
carry its children. Every other `Document` is a cut.

### Ownership

The rules above need one answer before any copy: which file writes a node. That is
decided once, over the whole save context:

> **A node is written in a file of its own domain, the first one that reaches it
> through nodes of that domain.** A file that reaches a node of another domain
> stops there; that node is the other domain's to own.

Walk the files in the order the context holds them. For each file `F` with domain
`D`, walk its content through nodes of `D`; the first `F` to reach a node `N` with
`N isa D` records `owner[N] = (F, path)`. Stop at a node that is not a `D`.

**What an orphan is, by this rule.** A JSON object that is reachable only
*through* an XML element is not reached by any JSON file's walk, because the walk
stops at the XML element. It has no owner, and the save aborts with a message
that names the node, the file that reached it, and the remedy: put it in a file
of its domain. This is the strict reading and the only coherent one — an XML
file cannot hold JSON text, so there is no file for the node to be written into.

### The reference leaf, per domain

The one thing a domain contributes. Two functions:

```julia
make_reference_leaf(::Type{JsonDocument}, marker::AbstractString) -> JsonString
find_reference_marker(node::JsonString) -> Union{Nothing, String}
```

`make_reference_leaf` builds the domain's spelling of a marker. `find_reference_marker`
returns the marker text of a leaf that is one, and `nothing` otherwise. Each
domain's existing `_substitute_markers` already knows the shape; the recogniser
is that knowledge with the stub construction removed.

| domain | the leaf |
| --- | --- |
| json | a `JsonString` whose whole value is the marker |
| xml | a `pred:ref` element with one text child |
| markdown | a ```` ```pred-ref ```` fence, or the marker inline |
| rst | a `.. pred-ref::` directive |
| julia | a `pred_ref("…")` call |

### The load splice

Loading is two phases, over a set of files.

1. **Parse.** Every file in the set is parsed by its domain's parser. A reference
   leaf is an ordinary leaf of the domain at this point — a `JsonString` that
   happens to hold a marker.
2. **Splice.** Walk every parsed tree. For each leaf that `find_reference_marker`
   recognises, evaluate the marker to its target node — a file's content, a
   section, a definition, a node at a path — and **replace the leaf with the
   target in its slot**.

After phase 2 no reference leaf remains. Two leaves that name one target splice
the same object, so identity is structural and needs no intern table. A cycle is
fine, because every tree exists before any splice happens.

**A reference to a file outside the set stays a leaf.** A `JsonString` holding a
marker is a legal JSON string. It renders as text, and it saves back as the same
text. So a project can be opened one file at a time, and a reference to a file
that was not opened costs nothing and loses nothing. Following such a reference
means adding the file to the set and splicing again.

### The save context

The files are saved together, because a reference from `a.json` into `b.xml` must
know that `b.xml` exists and what it holds. The context is the set of file
documents, in order, and the base directory. It is the wrapper the design needs
around the whole graph, the way the other large wrappers wrap a document. The
workspace document already holds a tree of files; whether the context is built
from it is a later question.

### The vocabulary for a subtree

A reference to a file root is `file("a.json")`. A reference to a node inside a
file needs a path. The vocabulary has two forms today, each domain-shaped:
`section(file("a.rst"), "Title")` for a heading, `definition(file("a.jl"), "name")`
for a Julia definition. JSON and XML have no such form, and the save walk needs
one for any node it cuts. The plan adds a **generic path verb** that takes a
reference path in the kernel's own DSL. Its name is chosen against the reference
DSL's arm words, which are already spoken for, and is not chosen here.

### What renders — nothing new

[NaturalProjection.jl:164](../../source/natural/NaturalProjection.jl#L164) builds
`RecursiveProjection(TypeDispatchingProjection(table))` over the **global** table,
and every template rule recurses through `recursion`. So a JSON object holding an
XML element renders today under `NaturalToGraphics`, and so does the reverse — I
ran both. The display side of this design needs no change.

The per-domain text chain, `print_natural_text`, wraps the domain's *own* table,
and throws on a nested foreign node. Under this design it never receives one: the
save copy is pure. The hand-merged table in `MixedProjectionExample.jl` becomes
unnecessary once the natural projection is used there.

### The embed card

The card frames an embedded document so a reader sees where the host page stops.
Under this design an embedded document is a foreign subtree, and "foreign" is a
fact the global table can see: the child's domain differs from the parent's. The
card becomes a display decoration keyed on that, independent of files. It is
**out of scope** here. The two embed suites that fail today test the card, and
they are retired or rewritten when the card is redone.

### The `.pred` file: a document written as its constructor

`realize(file("AlohaRun.json"))` is a file format in disguise. It takes a JSON
file with a `$doctype` key and runs a 279-line loader that turns it into a
`LegacyRun`. The loader only reads; `_dump_document` is a comment, so a realized
run cannot be saved back today. The shim exists because the file registry keys
on extension and `.json` was taken.

The replacement is a file whose content **is the document, written as its own
constructor**:

```julia
LegacyRun(project = "aloha", ini_file = "omnetpp.ini", config = "General",
          options = ["cmdenv-status-frequency=0.5s"])
```

That is the marker language at file scale. The interpreter already evaluates
`T(field = value, …)` through a registered type gate, never `eval`, over a
subset with no assignment, no control flow and no bare names. A `.pred` file is
one marker body, and `<<file("AlohaRun.pred")>>` splices a `LegacyRun` the way
any file's content is spliced. `realize`, `$doctype`, the loader and the
`ComputedDocument` idea all go, and the principle holds with nothing added: a
reference names stored content.

**One generic file type, `PredFile`, extension `.pred`.** The first token names
the document type, so one format covers every `@document` with a keyword
constructor, and a domain gets a file notation without writing one. The
notation, its reader and its writer live in the serialization slice beside the
interpreter they are made of.

Three properties come with it. A `.pred` file cannot execute code, because the
interpreter is its reader. Only a type a package registered may be constructed,
so a file cannot name what a session did not offer. And a cut in the save walk
— `file("b.xml")`, `node(file("a.json"), "…")` — is a call in the same
vocabulary, so this format writes its own references and needs no leaf maker.

| piece | state |
| --- | --- |
| the reader: the restricted interpreter with keyword constructors | exists |
| the type gate | exists as one global resolver function; becomes a registry of allowed types, `register_pred_type!(T)` |
| vector literals, `options = ["…"]` | **missing** from the subset; `AlohaRun.json` needs one on day one |
| the writer: document → canonical constructor text | **missing**; the write gate needs it byte-stable, so field order is declaration order and there is one way to write each value |
| the extension `.pred` | free; `.jl` is `JuliaFile`, whose content is a parsed source AST |
| a field derived from the file's location, `base_dir` | not written; derived at load from where the file is |

What a value may be, in the writer and the reader alike: a string, a number, a
char, a bool, `nothing`, a vector of values, a document written as its
constructor, and a reference. Nothing else, and the writer refuses a field that
holds anything else, the way `save_file!` refuses a foreign node.

## The API the tests fix

The tests were written before the code, in
[test/projectured/serializer/FileProjectTest.jl](../../test/projectured/serializer/FileProjectTest.jl),
and the names they use are the API:

```julia
FileProject(base_dir, files)              # the context: an ordered set of file documents
save_project!(project) -> Bool            # cut, print, write; false and an error log on an orphan
load_project(base_dir, filenames)         # parse every file named, then splice
project.files[i]                          # a file document; get_file_content(…) is its root
save_file!(file, base_dir) -> Bool        # one file, no context: every cut is an error
load_file(base_dir, filename)             # one file; a marker in it stays a leaf
PredFile(filename, document)              # a .pred file: any registered document, as its constructor
register_pred_type!(T)                    # the gate: a .pred file may construct T
```

**The single-file save is the same walk with no context.** There is nothing to
refer to, so a foreign node, a shared subtree and a cycle are each an error, and
the file is written only when the default natural notation of its domain can
write the content alone. The message says which node, where, and that a
`FileProject` can save it. A marker that arrived as a plain string is a plain
string and saves as one.

A reference to a whole file is `<<file("b.xml")>>`. A reference to a node
inside a file is `<<node(file("b.xml"), "children[1]")>>`: the generic path
verb is named **`node`**, and its path is the reference DSL's text form, the
one `ReferenceToText` writes. A reference to a file's own root is `file(…)`,
not `node(…)` with an empty path.

The old `save_project!(root, base_dir)` and `load_project(T, filename, base_dir)`
take different arguments, so both shapes coexist until stage 3 deletes the old.

## Stages

### Stage 0 — the tests (done)

Seventeen testsets, every one red with `UndefVarError` and none with a parse
error. The four from the brief:

- a JSON file holding a JSON array that holds an object that holds the same
  array — written once, a `file("a.json")` at the second visit, an identity
  cycle after load;
- an XML element deep in a JSON file and deep in an XML file — a `node(…)`
  reference on the JSON side, the element on the XML side, `===` after load;
- two files that hold each other's inner documents — the JSON file writes
  `file("b.xml")`, the XML file writes `node(file("a.json"), …)`, both
  identities hold after load;
- an XML element in no XML file — the save logs the orphan, returns `false`,
  and writes nothing.

And eight more the design needs: the XML element as the whole XML file; a
JSON object reachable only through an XML element is an orphan too; a file
document held as a value is a `file(…)` reference; a reference to a file
outside the loaded set stays a string and saves back unchanged; two references
to one node splice `===`; save, load, save changes no `mtime`; a string that is
not a marker is left alone; an unknown verb names itself in the error.

And five for one file at a time: a pure file round-trips; a foreign node, a
shared subtree and a cycle are each rejected with nothing written; a marker
that is a plain string saves as one.

### Stage 1 — save

- [ ] The ownership walk over a save context.
- [ ] The cut walk: copy with the five rules, reference leaves at the cuts.
- [ ] `make_reference_leaf` for json, xml, markdown, rst, julia.
- [ ] The generic path verb, so a cut inside a JSON or XML tree can be named.
- [ ] `save_project!` over a context: cut, print, write-if-changed. The orphan
  abort logs and returns; no file is written.
- [ ] `save_file!` and `load_file`: the walk with no context, every cut an
  error.
- [ ] The save half of `FileProjectTest.jl` passes: the cuts, the two orphans,
  the write gate.

The old path is untouched during stage 1.

### Stage 2 — load

- [ ] `find_reference_marker` for the five domains.
- [ ] The two-phase load over a set of files, with the splice.
- [ ] A reference to a file outside the set stays a leaf; adding the file and
  splicing again resolves it.
- [ ] The load half of `FileProjectTest.jl` passes: every identity, the
  partial set, save-load-save.

### Stage 3 — the switch

- [ ] The drivers use the new walks. Delete `ReferenceStub`, `resolve!`,
  `resolve_stubs!`, the drain, the intern table, the ten per-domain projections,
  the five `_substitute_markers` walks, and the two generic rows.
- [ ] `MixedProjectionExample.jl` uses the natural projection instead of a merged
  table.
- [ ] Port the serializer tests that still state a requirement; retire the ones
  that test a stub. `StubCollectionTest` goes whole.
- [ ] Every domain suite for json, xml, markdown, rst and julia matches its
  baseline; `test_substrate()` matches; the stack loads; the naming guard is
  clean.

### Stage 4 — the `.pred` file

- [ ] Vector literals join the subset, in the reader and the canonical printer.
- [ ] `register_pred_type!`: the gate becomes a registry; the one global
  resolver goes.
- [ ] The writer: a document as its constructor, canonical, refusing a value
  the subset cannot write.
- [ ] `PredFile`, registered for `.pred`; its leaf maker and recogniser are the
  vocabulary itself.
- [ ] The `.pred` half of `FileProjectTest.jl` passes.
- [ ] In `omnet-julia`: `AlohaRun.json` becomes `AlohaRun.pred`, the page writes
  `<<file("AlohaRun.pred")>>`, and `realize`, `$doctype` and `DocumentLoader.jl`
  go. The fields that derive from the base directory are derived at load.

### Stage 5 — what is left open

- [ ] The embed card, keyed on a domain boundary.

## What the tests must keep proving

From the suites that exist today, these are requirements and survive in the new
form: a cycle between files terminates; two references to one target are the
same object; a save writes only the files whose bytes changed and leaves the
others' `mtime` alone; a JSON, XML, Markdown, RST and Julia file each round-trip
byte-for-byte when nothing changed; a marker that names an unknown verb errors
with the verb named.

These test a stub and are retired: the drain and its session, "unhosted stub is
not resolvable", "resolve! is idempotent", "load lifts pred_ref into a
ReferenceStub".

## Risks

**The strict ownership rule will surprise a user once.** A node reachable only
through a foreign node has nowhere to go, and the save says so. The message must
name the node and the file that reached it, and say what to do. The first version
logs; a later one can offer to make the file.

**Eager sharing changes what a load means.** Today a stub resolves when looked at.
Here a file in the set is parsed at load. The cost moves from first sight to
open, and a large project should be opened as the files the user asked for, not
the closure — which the "stays a leaf" rule allows.

**A marker in a string that is not a reference.** The recogniser decides by shape,
as `parse_marker_text` does today. A JSON string that happens to read `<<file("x")>>`
is a reference. That is the existing rule and is kept.

**Five domains, one shape each.** The leaf makers and recognisers are the place a
domain can be wrong. Each gets a round-trip test of its own before the switch.

## Decisions taken here

- The document holds no storage node. Storage is a walk at save and a splice at
  load.
- A node is written in a file of its own domain, the first to reach it through
  that domain. Anything else is an orphan, and the save aborts.
- A reference to a file outside the loaded set stays a plain leaf.
- The generic path verb is `node`, and a reference to a file's own root is
  `file(…)`. The tests fixed both.
- `realize` is a file format in disguise and becomes one: `.pred`, one generic
  file type, the document written as its constructor, read by the marker
  interpreter. No `ComputedDocument`.
- The display is not touched: the global natural table already renders a mixed
  tree, in both nestings, measured on 2026-09-15.

## Decisions left open

- Whether the save context is built from the workspace document.
- When the embed card returns, and on what key.
