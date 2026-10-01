# Strict document types

**Status (2026-09-30): PENDING. Not started.** The owner asked for this plan in the decision
walk of [kernel-audit-fixes.md](kernel-audit-fixes.md), at L10-13. Do not implement it until the
owner asks. The questions of §7 come first.

**Goal:** the declared type of a `@document` field becomes a contract that the reactive layout
keeps. An intermediate state of an edit gets a type of its own, a *boundary type*, and a field
admits it by its declared type. A wrong value fails at the write that makes it, not later in a
printer. The pilot is the Julia domain.

**Repositories:** projectured-julia for the model and the pilot. omnet-julia and inet-julia
declare their own documents, so they follow only when the model goes past the pilot.

## 1. The request

At L10-13 the owner first chose a loose reactive layout, then asked for a strict one:

> The number parsing issue can be solved with having a PrimitiveNumber which supports incomplete
> numbers with type safety. When typein goes into a Julia document, there's JuliaInsertion, so
> this could be typed strictly for each Julia field. For cross domain combinations we could have
> a JuliaForeign which allows contains Document, so it allows combining different domains. Then
> we can have strict type handling. What do we loose? Copy pasting an alien domain has to
> introduce the foreign document type at the boundary but how? Editing a data structure that is
> not @document needs a first projection which maps it to a document data structure to support
> intermediate states.

The ruling, 2026-09-30: L10-13 is A for now, so the law states what the code does today. The
strict model is this plan, with a pilot on the Julia domain.

## 2. The facts today

**The reactive layout checks no declared type.** An example on main, with `age::Int`:

| Value | `Person` (reactive) | `MCPerson`, `ICPerson` (kind layouts) |
| --- | --- | --- |
| raw `"thirty"` in the constructor | `"thirty"` | `MethodError` |
| `Cell("thirty")` | `"thirty"` | `"thirty"` |
| `ReactiveCell{String}("thirty")` / `MutableCell{String}("thirty")` | `"thirty"` | `"thirty"` |
| the write `x.age = "thirty"` | `"thirty"` | `MethodError` |

- The bounds of the layout are `<: AbstractCell`, not `<: AbstractCell{T}`
  ([DocumentMacro.jl:96-99](../../source/kernel/document/DocumentMacro.jl#L96-L99)). The machinery
  makes an untyped `Cell(x)`, a `ReactiveCell{Any}`, and stores it in typed fields.
- The owner ruled on 2026-09-04 that a reactive cell stores `Any`, so that projections can
  combine domains. A read narrows to the declared type. This plan keeps the storage `Any` (§3.2).
- The macro already records the declared types: `_declared_value_types` in
  [DocumentCopy.jl:239](../../source/kernel/document/DocumentCopy.jl#L239). L10-21 recommends
  that this becomes a public seam.

**The boundary types that exist:**

- 20 domains have an insertion type for text that a person types (`JuliaInsertion`,
  `JsonInsertion`, `PrimitiveInsertion`, and others). `@domain` generates the kit.
- 3 domains have a type for an empty place: `DocumentNothing`, `JsonNothing`, `JuliaNothing`.
- No domain has a foreign type.
- `PrimitiveNumber.value` is `Union{Number, Nothing}`. A number text that does not parse, such as
  `-` or `1e`, has no typed home (L13-1).

**The loose fields.** About 1,080 of about 5,300 declared fields in `source/` are `Any` or
`Document`. The Julia domain has 57 `@document` types with 102 fields:

| Declared type | Fields |
| --- | --- |
| `Document` | 52 |
| `CellVector` (elements untyped) | 20 |
| `String` | 10 |
| `Bool` | 6 |
| `Union{Document,Nothing}` | 5 |
| `Symbol` | 4 |
| `JuliaDocument`, `Int`, `Float64`, `Char` | 1 each |

Other domains hold Julia code in their own loose fields: `FsmTransition.guard` and `.action`,
`FsmState.entry` and `ProcessStep.action` are `Any`; `ProcessModel.parameters` is a
`CellVector`. The pilot does not change them.

**The paste already checks a slot.** `_is_slot_accepting` in
[Clipboard.jl:210](../../source/platform/clipboard/Clipboard.jl#L210) refuses a value that is not of the
value type of the cell. For a `ReactiveCell{Any}` that type is `Any`, so the check passes
everything today.

## 3. The model

### 3.1 Boundary types are subtypes of the domain

Each domain declares its boundary types under its own abstract type:

- `JuliaInsertion <: JuliaDocument`: text that a person types, parsed later. It exists.
- `JuliaNothing <: JuliaDocument`: an empty place. It exists.
- `JuliaForeign <: JuliaDocument`: a document of another domain, in the field `content::Document`.
  It is new.
- In the primitive domain, an incomplete number: a text that does not parse yet. It is new, and it
  is option B of L13-1.

A field declared `JuliaDocument` then admits all of them, with no `Union` in each field. Julia has
single inheritance, so one kernel `Foreign` type can not be a subtype of every domain. Each domain
needs its own. `@domain` can generate it, as it generates the insertion kit.

### 3.2 The check

The constructor and the setter of the reactive layout check a value against the declared type of
the field. The storage stays `ReactiveCell{Any}`. So the engine does not change, the cells still
combine, and the invariance problem of `DocumentMacro.jl:96-99` does not come back. The check reads
the declared types that the macro already records.

A computed field keeps "narrow at the read", because its value exists only after the computation.

### 3.3 The adapting seam

Every edit goes through an operation (PAR-ONE-WAY-TO-EDIT). The operation knows its target slot,
and the path of the operation is typed. One seam of the host domain, called at the write, adapts a
value to the slot:

1. If the value has the declared type, it passes.
2. If the value is text, it becomes the insertion type of the domain, to be parsed later.
3. If the value is a document of another domain, it becomes the foreign type of the domain, for
   example `JuliaForeign(document)`.
4. Otherwise the seam refuses the write, with a message that says why.

A paste, a drag, a type-in and an operation from the model all pass through this one place. A
direct write by program code does not pass through the seam. It meets the check of §3.2 and gets
an error.

### 3.4 The conversion rule

An `Int` into a `Float64` field: the kind layouts convert today. The rule:

1. If Julia has a conversion to the declared type that loses nothing, convert.
2. Else adapt through the seam of §3.3.
3. Else refuse.

### 3.5 The lenient load

Saved files, the undo history, version snapshots and the gesture log can hold values that the new
types refuse. A load wraps such a value into an insertion or a foreign value of the domain, or a
migration changes the files once. The load never fails on a value that was valid before.

### 3.6 What stays loose

Generic containers keep `Document` or `Any`, because to hold anything is their purpose: the tabs,
the clipboard, the results of the evaluator, the messages of a conversation, and the fault log. So
strictness is a property of a domain, not of the whole system.

A data structure that is not a `@document` gets strict types only through a first projection that
maps it to a `@document` structure. That structure holds the intermediate states.

## 4. The trade-offs

**What the strict model costs:**

1. **Nesting becomes a choice of the host domain.** A domain with no foreign type refuses an alien
   paste, which today it takes and a projection can show. The types of the host decide what can
   sit where, and the projection decides only how it looks. With a foreign type in every domain,
   this loss is small.
2. **Migration.** The 1,080 loose fields get a narrower type one by one, in three repositories.
   The type-in and example sweeps first show every place that writes a raw value today. Each of
   those is a hidden fault now, so this is a cost and a benefit at once.
3. **Stored data** needs the lenient load of §3.5.
4. **Each new domain costs more.** It needs its insertion, foreign and nothing types, and their
   projections.
5. **Each write costs one type check.** It is an `isa` against a type that the macro knows.

**What the strict model gives:**

- A wrong value fails at the write that makes it, not later in a printer.
- A model gets a clear refusal.
- The printers can rely on the declared types and need fewer defensive branches.
- The declared type becomes a real contract for the copy, the paste and the type checkpoints.

## 5. The pilot on the Julia domain

The pilot measures the migration before the other domains follow. Each step is one commit in a
worktree.

- [ ] **Step 0: an inventory.** The check of §3.2 runs in a mode that records each violation and
  does not throw. Run the Julia, FSM, process, formula and conversation suites, and the Julia
  examples with the type-in and position sweeps. The result is the list of every write of a value
  that is not a `JuliaDocument` into a Julia field, with its caller.
- [ ] **Step 1: `JuliaForeign`.** Add the type, its projection to syntax, and its reader. The
  printer shows `content` through the projection that the recursion picks for its type. A cursor
  passes through the boundary in both directions.
- [ ] **Step 2: the seam.** Add the adapting seam of §3.3 with its default, and call it at the
  write of the operation (`_write_slot!` in
  [Operations.jl:171](../../source/kernel/operation/Operations.jl#L171)). Give the Julia domain its
  method. The clipboard check `_is_slot_accepting` reads the declared type.
- [ ] **Step 3: the check.** Add the check of §3.2 to the reactive layout, for the Julia types
  only (question S-1).
- [ ] **Step 4: narrow the Julia fields.** The 52 `Document` fields become `JuliaDocument`. The 5
  `Union{Document,Nothing}` fields become `Union{JuliaDocument,Nothing}` or `JuliaDocument` with
  `JuliaNothing`. The 20 list fields follow the answer to S-2.
- [ ] **Step 5: fix the callers** that the inventory of Step 0 found, one by one.
- [ ] **Step 6: test and measure.** Run `test_julia()`, `test_fsm()`, `test_process()`,
  `test_formula()`, `test_conversation()`, and the omnet-julia suite, because the omnet IDE edits
  Julia code. Report the count of changed callers, the new refusals that a person meets, and the
  cost of the check per write.
- [ ] **Step 7: the owner decides** whether the other domains follow, and in which order.

The laws change only when the pilot lands (§6).

## 6. The laws that change

- **PAR-NO-NESTED-CELL.** L10-13 gives it the text of the loose layout now. After the pilot, the
  reactive layout checks the declared type of a strict domain, and the text says so.
- **PAR-WIDE-FIELD-TYPES** says: "Widen the annotation to admit the transient value". In the strict
  model the annotation admits the transient value through a boundary type of the domain, not
  through `Any` or `Document`.
- **PAR-DOMAIN-OWNS-EDITS** names the insertion type of each domain. It also names the foreign
  type and the nothing type.
- **PAR-DOMAINS-INDEPENDENT** does not change. `JuliaForeign.content` is a `Document`, so the Julia
  domain names no other domain.

## 7. Questions for the owner before the pilot

- **S-1: opt-in or all at once.** Does a strict type say so in its declaration, for example a
  struct-level word of `@document`, so that the pilot changes only the Julia types? Or does the
  check apply to every type, and a loose field stays loose by its `Any` or `Document`?
  *Recommended (mine):* all at once, with no flag. A field declared `Any` or `Document` passes
  everything anyway, so the check changes only the fields that already claim a narrower type. Step
  0 shows how many writes break in the other domains before the check throws.
- **S-2: the element type of a list.** `CellVector.elements` is an untyped `Vector`. Does a list
  field declare its element type, for example `arguments::Vector{JuliaDocument}`, and does the
  `CellVector` check each element write? This changes the collection package.
- **S-3: a cell that a constructor gets.** It becomes the cell of the field, and later writes to it
  can come from another place. Does the constructor check only the value at construction, or does
  it refuse a cell that another place can write?
- **S-4: the seam.** Its name, and the layer that declares it. The operation layer calls it, and
  each domain gives a method.
- **S-5: the incomplete number.** A type in the primitive domain (L13-1, option B), and do the
  number fields of the Julia domain (`JuliaInteger.value::Int`, `JuliaFloat.value::Float64`) use it
  or go through `JuliaInsertion`?
- **S-6: the refusal.** A new exception type for a write that the check refuses, and what a person
  sees when an edit meets it.

## 8. Related items

- L10-13 of [kernel-audit-fixes.md](kernel-audit-fixes.md): decided A for now. This plan changes
  it again when the pilot lands.
- L13-1: the home of a number text that does not parse. S-5 connects them.
- L10-21: the public seam for the declared types of a field. The check and the clipboard need it.
