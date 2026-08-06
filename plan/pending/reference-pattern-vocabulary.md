# A pattern language that says everything a configuration needs

The reference pattern grammar can name a place exactly. It cannot name a *kind*
of place — "every queue's capacity, wherever it sits" — which is the commonest
line in any real configuration and the first thing anyone migrating an OMNeT++
`.ini` file reaches for. This plan gives the grammar wildcards, gives the
wildcards a semantics that composes with the arm words already there, and folds
the two matchers into one so the new forms are implemented once rather than
twice.

## Why

`@reference_rules` exists so a configuration can be written before the thing it
configures exists. A configuration that can only name exact paths is a
configuration that has to be rewritten every time the tree changes shape, which
is the problem it was meant to remove. OMNeT++'s ini language earns its keep
almost entirely through `**`, and we have no equivalent.

Two things make this more than "add a wildcard":

- The vocabulary should be **complete against OMNeT++** — everything an ini key
  can say, sayable here — while keeping everything we have that it does not:
  binders, guards, node types, cursor positions, extension steps, delegation.
- A wildcard makes matching a *search*. Doing that twice, once in
  `ReferenceCase.jl`'s codegen and once in `ReferenceRules.jl`'s interpreter, is
  the drift risk the conformance corpus was built to contain — and a compiled
  backtracking matcher is exactly where a divergence would hide. So the matchers
  unify first, and the language grows afterwards.

## What it is

### Steps — path position

| form | matches | new |
| --- | --- | --- |
| `a` / `a.b` | the field named `a` | |
| `.field(v)` | a field whose name matches value pattern `v` | |
| `_` | **exactly one** step, of any kind | ● |
| `__` | **any run** of steps, possibly none — greedy | ● |
| `__ʔ` | the same, lazy (`\glst`+Tab) | ● |
| `__(name)` / `__ʔ(name)` | a run, bound to `name` | ● |
| `name...` | a run bound to `name`, at the end only | |
| `any(P, Q, …)` | any one of the alternative subpaths | ● |
| `xs[v]` | element, 1-based | |
| `xs{v}` | cursor position, 0-based | |
| `xs{s:e}` | range | |
| `::T` | narrow: a recorded node type must be `<: T` | |
| `::t` | bind the node's type to `t` | |
| `.name(args…)` | extension step (`.point`, `.proj`, …) | |
| `^(p)` | splice a whole path — sole step only | |
| `∅` | the empty path (whole-element selection) | |

### Values — inside `[…]`, `{…}`, `.field(…)`, extension args

| form | matches | new |
| --- | --- | --- |
| `_` | any value | |
| `v` | binds | |
| `v::T` | binds if `isa T` | |
| `3`, `"q"`, `:s` | literal | |
| `a..b` | a number in the range | ● |
| `any(x, y, …)` | any one of them; `any(^(coll))` splices a collection | ● |
| `glob"host*"` | character-level name pattern | ● |
| `^(e)` | a value from the writing site | |

`glob` is OMNeT++'s character language and never crosses a step: `*` any run of
characters, `?` one character, `{a-e}` a set, `{^a-e}` negated, `{38..47}` a
numeric range, `\` escapes.

### Arms

| arm | holds when |
| --- | --- |
| `P` / `at(P)` | the input **is** `P` |
| `within(P)` | `P` or deeper |
| `below(P)` | strictly deeper |
| `toward(P)` | `P` or shallower |
| `above(P)` | strictly shallower — the input runs out inside `P` |
| `when(P, cond)` | any of the above, and the guard holds |

Three of them have pattern spellings, and both spellings are accepted:

| word | sugar |
| --- | --- |
| `at(P)` | `P` |
| `within(P)` | `P.__` |
| `below(P)` | `P._.__` |
| `toward(P)` / `above(P)` | none — no pattern form can express them |

### The string surface

One semantics, two spellings. `ref"…"` parses OMNeT++ syntax into the same
pattern data, at macroexpand time or at run time (a rule set read from a
configuration file has no macro, so the runtime path is needed anyway).

| INI | Julia |
| --- | --- |
| `**` | `__` |
| `**?` | `__ʔ` |
| `*` as a whole component | `_` |
| `host*`, `host?`, `mac{a-c}` | `.field(glob"…")` |
| `[*]` | `[_]` |
| `[0..3]` | `[0..3]` — 1-based; the front end shifts |

```julia
ref"**.host[*].queue.capacity"   ≡   __.host[_].queue.capacity
```

## Semantics

**A pattern denotes a set of paths.** Wildcards make it a set rather than a
single path, and every arm word is then one relation against that set — which is
what lets gaps and arm words compose with no special cases, so that
`above(__.q)` is meaningful and needs no rule of its own.

| arm | formally |
| --- | --- |
| `at(P)` | the input is a member |
| `within(P)` | the input is a member, or below one |
| `below(P)` | the input is strictly below a member |
| `toward(P)` | the input is a prefix of a member |
| `above(P)` | the input is a *proper* prefix of a member |

1. **Anchored at both ends.** A pattern consumes the whole input; a leading or
   trailing `__` is what un-anchors that end. Same convention as OMNeT++, where
   an unqualified key must match the full module path.
2. **Greedy, leftmost-first.** Each gap takes as much as it can while letting the
   rest match; `__ʔ` reverses that gap only. This never changes *whether* an arm
   matches — only which member of the set was the witness, and so which bindings
   come out.
3. **`__` counts navigation steps; `_` counts steps.** A gap skips an unfolded
   `TypeReferenceStep`, because its length arithmetic is shared with the stripped
   shape walk `^(p)` uses. `_` consumes one step whatever it is, including such a
   checkpoint. Neither is observable on a canonical path, where checkpoints are
   folded into the nodes and there are no checkpoint steps to count — and the
   unfolded form is a transitional build-time artifact.
4. **A repeated binder is an equality check**, read left to right.
5. **First match wins** across arms; no match answers `nothing`. The same rule
   OMNeT++ uses for ini lines, so a migrated file keeps its precedence.
6. **Type steps are non-navigating** and attach where written, gaps or not.

## Design decisions already made

- **`_` is one step, `__` is the catch-all.** They mirror `*` and `**`, and both
  are legal Julia identifiers in path position where `*` is not.
- **All five arm words stay, and none spells a disjunction.** `at_or_below` and
  `at_or_above` become `within` and `toward`. The pattern sugar exists beside the
  words rather than replacing them.
- **`ends_with` is not added.** A leading gap says it: `ends_with(P)` is `__.P`.
  The word would have been a sixth arm on a second axis; the gap makes the axis
  unnecessary.
- **`any`, not `one_of`.** No underscore, and it reads correctly both with a
  literal list and with a spliced collection. Its case is not convenience —
  two arms already express a two-way choice — but that `any(^(allowed))` is
  parameterized by data, and *N* arms cannot be written when *N* is a runtime
  value. That is the same argument that motivated `@reference_rules` at all.
- **Greedy by default, `__ʔ` for lazy.** Greedy agrees with "the deepest match
  wins" and with regex intuition. The marker had to be a legal Julia identifier
  character: `?` is the ternary operator and is **rejected by the parser**, as is
  `…`. Measured on 1.12:

  | candidate | identifier | in path | completion |
  | --- | --- | --- | --- |
  | `__?` | rejected | — | — |
  | `__…` | rejected | — | — |
  | `__ʔ` | ✓ | ✓ | **`\glst`** |
  | `__ˀ` | ✓ | ✓ | none |
  | `__′` | ✓ | ✓ | `\prime` |
  | `__!` | ✓ | ✓ | ASCII |

  `ʔ` (U+0294) renders as a dotless question mark and is the only candidate that
  is both question-mark-shaped and typable by completion. The precedent is
  already in the language: `∅` is a pattern today and types as `\emptyset`+Tab.
  Its one cost is that a literal `__?` fails in Julia's parser before the macro
  sees the block, so that mistake cannot be given our own error message.
- **The interpreter is the specification; codegen is an optimization.** Not a
  compromise — a rule set built at run time has no macro, so a complete
  interpreter has to exist regardless. Making it normative turns the drift risk
  into a differential test.

## Implementation

Ordered so that each phase is green on its own, and so that **nothing new is
implemented twice**: unification comes before the language grows.

1. **Unify the matchers.** Give `@reference_case` a fallback: patterns it cannot
   compile call the interpreter, which answers a bindings dict, and the macro
   emits `let x = b[:x], …; <escaped answer> end` over the binder names. Two
   pieces already exist — `ReferenceCase.jl:611` computes the bound-name set and
   **discards it** (`ex, _ = …`), and `ReferenceRules.jl:623`'s `_quote_pattern`
   already turns a pattern into runtime data. The fallback must call the
   *matcher* only, never `apply_reference_rules`: a `@reference_case` answer is
   escaped user code that closes over the call site, while a rules answer is
   deliberately closed. Both DSLs share matching; neither shares answer
   evaluation. This phase adds the seam and a differential test over the existing
   corpus. No behaviour change. **Done** — the entry point is
   `match_reference_pattern(mode, pattern, reference)`, exported, and
   `_gen_interpreted_rule` reopens its bindings as locals.

   The **forced-fallback switch was dropped**. It would have been global mutable
   state in the kernel, and it turned out to buy nothing: the corpus already runs
   every pattern compiled (through `@reference_case`) *and* interpreted (through
   the equivalent rule set), and the fallback's own code — the bindings handoff —
   is exercised by every gap pattern, which is forced down that path by
   construction. The only combination left untested is a contiguous pattern
   through the fallback, which no caller can produce.
2. **`__`, greedy, interpreter-side only.** The macro routes any pattern
   containing a gap to the fallback. As a sole pattern `__` matches everything,
   so it is already the catch-all. **Done**, including the gap's reading in the
   above-family: reaching a gap while the input still has steps settles an
   above-arm as *true*, because a gap is unbounded and so the input is a proper
   prefix of some member. `PatStepGap` carries its `name` and `lazy` fields from
   the start, but only the anonymous greedy spelling is wired up; `__ʔ` and
   `__(name)` stay in phase 5 as planned.
3. **Migrate the catch-all.** **Done** — **92** arms, not the 113 a grep
   reports. The other 21 belong to `@event_case` and `@gestures`, which spell
   their own catch-all `_ =>`, and a blind rewrite would have broken them. The
   arms were found by parsing all 581 files and walking for `@reference_case` /
   `@reference_rules` macro calls, so the set is exactly the reference ones.
4. **`_` becomes one step**, and a *sole* `_` becomes an error for one release —
   see Migration. **Done.** Only the *un-worded* arm is guarded: `at(_)` is a
   deliberate one-step arm, and is how the new meaning is written while the guard
   stands. Both DSLs raise one shared message so they cannot word it differently.

   Two things this phase also had to do, neither of them foreseen:

   - **`@reference` rejects `_` and `__`.** Otherwise `@reference(a.__.b)` builds
     a field literally named `__`. Needs `ReferenceBuilder.jl`, which was
     **unsealed for it** and is now `⬜` in the inventory.
   - **A lone anonymous gap compiles.** Phase 3 had just created 92 sole-`__`
     patterns — the catch-all arm, on the hot path of every mapper and reader —
     and routing them to the interpreter would have cost a materialized pattern
     and a bindings dict per evaluation. A gap with nothing before or after it to
     line up against answers the same for every input, so there is nothing to
     search and it is emitted as the body itself. This is the first rung of the
     tier-2 ladder, arriving early because phase 3 made it urgent.
5. **`__ʔ` and `__(name)`.** `name...` **survives as its own form**, not as sugar
   to be retired: a trailing bind is what almost every caller wants, and reading
   `rest...` at the end of a path is clearer than reading a gap that happens to
   be last.
6. **Value patterns:** `a..b`, `any(…)`, `glob"…"`.
7. **Path-position `any(P, Q, …)`** — subpath alternation, the general form.
8. **Arm renames** `at_or_below`→`within`, `at_or_above`→`toward`, plus the
   pattern sugar as an accepted alternative spelling.
9. **The `ref"…"` string surface**, macro and runtime, lowering to the same
   pattern data.
10. **Tier-2 codegen** — a pure optimization, safe because the differential test
    is already in place. See below.

### The compile/interpret ladder

The macro sees every pattern, so the choice is a macroexpand-time dispatch on a
decidable property of the pattern rather than a global one:

| tier | pattern shape | emitted | cost |
| --- | --- | --- | --- |
| 1 | contiguous — everything written today | straight-line type checks | unchanged |
| 2 | one gap, fixed-length remainder — `__.a.b`, `a.__.b` | a computed offset, one attempt | a walk |
| 3 | anything else — several gaps interacting | a call into the interpreter | allocation, dynamic dispatch |

Tier 2 is larger than it looks. When everything after a gap has a fixed step
count and the pattern is tail-anchored, the gap's length is **computed, not
searched** — `__.queue.capacity` against a five-step path fixes the gap at three
and makes exactly one attempt. Search is needed only when something after the gap
is itself variable-length: another gap, a tail bind, or a type step against an
unfolded path. Most real ini lines never leave tier 2, so the general
backtracker is built for correctness and rarely runs.

Tier 3 must materialize its pattern to call the interpreter, and `const` hoisting
is unavailable inside a function body, so a tier-3 arm allocates its pattern per
evaluation unless the expansion emits a lazily-filled module-level slot. That
cost is the reason tier 1 stays compiled rather than "just interpret everything".

The narrowing rule (`_type_step_matches`) must be **called** by both paths, never
reimplemented: it is the subtlest thing here and the likeliest place for a split
to reintroduce drift.

## Migration

`_` changes meaning from the catch-all to one step across **92** arms. A grep
reports 113, but 21 of those are `@event_case` / `@gestures` arms with their own
`_ =>` catch-all — so the migration was driven by *parsing* every file and
walking for reference macro calls, not by a regex. The danger is that `_ => v`
still *parses* afterwards and silently means "any one-step path", so the change
would be invisible at each site.

Therefore a sole `_` is an **error** for one release —

> write `__` for the catch-all; `_` matches exactly one step

— which turns 92 silent behaviour changes into 92 compiler messages. Value
position is untouched: `xs[_]` still means "any value", and a bare `_` as a whole
*subpath* argument (`proj(^(p), _)`) still binds the whole subpath, because a
subpath slot takes a path and a bare symbol there binds one by the grammar's own
rule.

Two reserved-word consequences, both from value slots that are raw Julia today:

- `xs[0..3]` currently evaluates to a `UnitRange` compared against an `Int` and
  so silently never matches. It goes from quietly broken to working.
- `.field(any(x))` currently interpolates. `^(…)` restores the old reading
  wherever it is wanted: `.field(^(any(x)))`.

## The risk to design against

Two implementations of one matching semantics is the risk this plan inherits, and
wildcards would double it exactly where it hurts most. Phase 1 is the answer:
after it, the interpreter is normative and the conformance corpus stops being two
hand-written blocks that are hoped to agree. It becomes a **differential test** —
every corpus pattern run through the compiled path and the forced-fallback path,
asserted equal — which covers every pattern rather than only the ones someone
remembered to write twice.

The second risk is performance. `@reference_case` sits on hot projection paths;
every mapper and reader calls it. Tier 1 must be byte-for-byte what it is today,
and the suites' wall-clock is the check that it is.

## Tests

Extend `package/kernel/test/reference/ReferenceRulesTest.jl`, and add
`ReferencePatternTest.jl` for the language itself.

- **The differential test** from phase 1: the whole corpus, both paths, equal.
- **Gaps:** leading, trailing, middle, several; a gap matching nothing; a gap
  spanning the whole input; `__` alone against every corpus path.
- **`_`:** one field step, one index step, one position step, one extension step;
  `xs[3]` as `_._`; a sole `_` raising.
- **Greediness:** the cases where it is observable — two gaps
  (`__(a).q.__(b).cap`) and gap-then-tail-bind (`__.q.rest...`) — asserted
  against both `__` and `__ʔ`, and a case where the split is *determined* so the
  two agree.
- **Arm words against sets:** each of the five against a pattern containing a
  gap, so the set semantics is pinned rather than assumed.
- **Values:** `0..3` in and out of range; `any` with literals, with a spliced
  collection, and in path position; `glob` for each OMNeT++ metacharacter.
- **Sugar equivalence:** `within(P)` and `P.__` answer identically across the
  corpus; likewise `below(P)` and `P._.__`.
- **The string surface:** each row of the INI table, plus a real multi-line ini
  fragment parsed at run time and applied.
- **Delegation** from an arm whose pattern ends in a gap, and from one whose gap
  is bound.

## Verification

Run from the repo root environment, memory-capped under `systemd-run`.

- `test_reference_rules()`, `test_reference_eval()`, `test_reference_builder()`
  after each phase.
- `test_kernel()` against the clean-main baseline — which carries five
  pre-existing `DocumentMacro` "Rule C" failures that are not regressions.
- `test_base()`, `test_visual()`, `test_domain()` once per phase that changes a
  matcher, and after the 113-site migration.
- **Wall-clock before and after**, on `test_visual()` and `test_domain()`, since
  those are the closest thing to the real `@reference_case` workload. Tier 1
  emitting anything other than today's code would show up there.

## Landed so far

Phases 1 and 2, on `reference-pattern-gap`.

- `test_reference_rules()` 642 pass (from 473), `test_reference_eval()` 33,
  `test_reference_builder()` 30.
- `test_kernel()` 1139 pass / 3 fail / 2 error — the same five pre-existing
  `DocumentMacro` "Rule C" failures the baseline carries.
- `test_base()` 387, `test_visual()` 49534 / 1 broken, `test_domain()` 184679 / 5
  broken. No failures or errors.
- **No wall-clock cost.** `test_visual()` is 38.9 s on the branch against 39.6 s
  on a clean-main worktree — marginally faster, inside the noise. Tier 1 is
  untouched by construction: the gap check is a macroexpand-time question, and no
  pattern in the codebase contains a gap, so nothing that runs today takes a
  different path.

Not done, and deliberately: the builder still accepts `__` as an ordinary field
name. Rejecting it belongs in `ReferenceBuilder.jl`, which is **sealed**, and the
cost of leaving it is that `@reference(a.__.b)` builds a field literally named
`__` instead of saying it cannot. Worth fixing when that file is next opened.

## Done when

The vocabulary above is accepted by both matching DSLs, an ini key and its Julia
spelling answer identically, the arm words carry no disjunction in their names,
the 113 catch-alls are migrated behind a compiler error rather than silently, the
interpreter is the single normative matcher with codegen as a differential-tested
optimization, and the four package suites are green against a clean-main baseline
with no wall-clock regression.
