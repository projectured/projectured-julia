# `@reference_rules` — matching kept as an object

The reference grammar has two readings today: `@reference` builds a path,
`@reference_case` matches one where it stands. This plan adds the third —
`@reference_rules`, which keeps the same block of arms as a **value** that can be
stored, compared, printed, edited and applied later.

## Why

A configuration is a set of rules that says what things are to be, written before
the thing it configures exists. `@reference_case` cannot express that: it applies
at the point it is written and its arms are compiled away. What is needed is the
same block, held as data, applied whenever a reference turns up:

```julia
rules = @reference_rules begin
    buckets[2].capacity => 20
    buckets[i].capacity => 10 * i          # i is bound by the match
end

apply_reference_rules(rules, reference)    # what @reference_case would answer
```

The contract is exactly that last comment: **applying a rules object to a
reference gives what the same block written as `@reference_case` would have given
there.** That equivalence is the acceptance test of this feature.

## What it is

A new fragment `package/kernel/main/reference/ReferenceRules.jl`, included after
`ReferenceCase.jl`, whose patterns are the `PatStep`/`PatValue` AST that fragment
already parses. Nothing new is added to the grammar: `ReferenceSyntax.jl` parses
both DSLs into one `RefStep` AST, and the matching reading of it —
binders, `_`, typed binders, `^(…)` interpolation, `when(…)`, `prefix(…)`,
`name...`, `∅` — is what a rule's left-hand side is.

Three things distinguish a rules object from a compiled case:

1. **The pattern is data.** A rule holds its `Vector{PatStep}`, so two rule sets
   compare, print, and serialize.
2. **The answer is an expression**, evaluated against what the match bound.
   Identity is the expression; a compiled form beside it is a cache of the
   expression and never the thing that is compared, printed or stored. One
   construction makes the pair, so the two cannot be set apart.
3. **An answer may be rules.** Such an arm matches a *leading prefix* of what is
   asked, and the rules it answers with take the rest. That is what lets a set
   written about one place be applied at several places, differently:

```julia
node = @reference_rules begin
    queue.capacity => 100
    serviceRate    => 10.0
end

@reference_rules begin
    at_or_below(hosts[_]::WirelessHost) => ^(node)   # by kind, not by place
    linkDelay                           => ^(10ms)
end
```

An expression is evaluated against what its own pattern bound **and what the
prefixes above it bound**, and nothing else. Nothing from the site where the
rules were written is visible unless it was spliced in with `^(…)` at
construction, which keeps the object closed.

## Design decisions already made

- **Plural name.** `@reference_rules`, `ReferenceRules`,
  `apply_reference_rules`. "Case" is a construct noun that covers many arms;
  "rule" names one arm, so a block of them is rules.
- **First match wins**, in written order, like `@reference_case`. No match
  answers `nothing`. Appending one set to another therefore leaves the first in
  charge, and a set that must override is prepended — so ordinary concatenation
  is the override mechanism and no merge operation is needed.
- **Matching is interpreted, not compiled.** A rules object may be built at
  runtime (read from a configuration file, edited in the editor), where no macro
  ran, so matching cannot depend on macro-time codegen. See the risk below.
- **Its own arm vocabulary, symmetric and complete.** `prefix(P)` was measured
  before it was adopted, and it means the *opposite* of what this plan's
  delegation needs: `@reference_case`'s prefix matcher succeeds exactly when the
  **input runs out inside `P`** (`prefix(a.b.c)` answers for `a` and `a.b`, and
  declines `a.b.c` and `a.b.c.d`) — the input is an *ancestor* of the pattern.
  Delegation needs the other direction. Rather than overload one word,
  `@reference_rules` takes a fresh vocabulary naming where the **input** sits
  relative to the pattern; it covers the whole lattice of prefix relations and
  `prefix(…)` is rejected with a message pointing at the two replacements.

  | arm | holds when | leftover a rules answer receives |
  | --- | --- | --- |
  | `P` / `at(P)` | input **is** `P` | `∅` |
  | `below(P)` | input is strictly deeper | the leftover (non-empty) |
  | `at_or_below(P)` | `P` or deeper | the leftover, possibly `∅` |
  | `above(P)` | input is strictly shallower | `∅` |
  | `at_or_above(P)` | `P` or shallower | `∅` |

  `above(P)` is precisely `@reference_case`'s `prefix(P)`, so the conformance
  corpus still pins the two matchers against each other under the new name.
  `@reference_case` itself is sealed and unchanged.
- **The arm decides the leftover, not the answer.** Delegation is implicit — an
  arm whose answer is rules hands them the leftover its own form computed — but
  which leftover that is, is read off the arm, never off the answer. So an arm
  means the same thing whatever it answers.
- **`^(…)` means "from the construction site", on both sides of `=>`.** In a
  pattern it already interpolates a value to compare against; in an answer or a
  `when(…)` guard it is evaluated at construction and its **value** spliced into
  the stored expression. That is the only channel from the writing site into the
  object, which is what keeps the object closed. A nested rule set is spliced the
  same way: `=> ^(@reference_rules begin … end)`.
- **Free names in an answer resolve in `ReferenceModule`**, not at the
  construction site — the answer is compiled in the module that owns the fragment.
  Anything else (a unit, a domain constructor, a local) is spliced with `^(…)`.

## Implementation

1. **`ReferenceRules.jl`** — the fragment. A `ReferenceRules` holds an ordered
   vector of `ReferenceRule`s; a rule holds its arm form (`:at`, `:below`,
   `:at_or_below`, `:above`, `:at_or_above`), a pattern (`Vector{PatStep}`), an
   optional guard, and an answer that is either a `ReferenceRuleAnswer` (an
   expression plus its per-binding-set compiled cache) or a nested
   `ReferenceRules`.
2. **The matcher.** `apply_reference_rules(rules, reference)` walks the entries
   in order, matches each pattern against the reference, and on the first match
   evaluates the answer with the bindings — or, for a rules answer, recurses with
   the unmatched remainder and the bindings accumulated so far. This needs a
   *pattern interpreter* over `PatStep`/`PatValue`: the same semantics
   `_gen_path_match` / `_gen_prefix_match` generate code for, executed instead of
   emitted. Two primitives carry all five arm forms: `_consume` (match the
   pattern against a leading segment, answer the leftover) and `_match_above`
   (the input runs out inside the pattern — the mirror of `_gen_prefix_match`).
3. **`@reference_rules`** — parses the block with the existing `_parse_path` and
   value-pattern lowering (`ReferenceCase.jl`), then *quotes the pattern as
   data*: every `^(…)`, every `::T`, and every typed binder's type is evaluated
   at the construction site and the **value** stored, so a stored pattern holds
   no unevaluated expression. Answers and guards are stored as expressions with
   their `^(…)` sub-expressions likewise replaced by values. The compiled form is
   built on first use, keyed by the binding-name set (which a nested rule set
   cannot know until it is applied), with `Core.eval` + `Base.invokelatest`, or
   the world-age error will find you. Literals, spliced values and bare binder
   names never reach the compiler.
4. **The extension-step seam.** `match_reference_step` is a *codegen* seam and an
   interpreter cannot use it, so `.name(…)` patterns need an interpreted sibling,
   `match_reference_step_value(::Val{name}, step, argpats, bindings, match_value,
   match_path) -> bindings | nothing`, declared with its error default in this
   fragment (`ReferenceInterface.jl`, its natural home, is sealed) and exported.
   The kernel owns no extension step, so it registers none; `.point`, `.sample`,
   `.row` and `.proj` each need one line in the package that owns them before
   rules can be written over them, and the seam's error names exactly what is
   missing.
5. **Module wiring.** `include("ReferenceRules.jl")` after `ReferenceCase.jl` and
   export `ReferenceRules`, `ReferenceRule`, `ReferenceRuleAnswer`,
   `apply_reference_rules`, `match_reference_step_value`, `@reference_rules` —
   both in `package/kernel/main/reference/ReferenceModule.jl`, **which is a
   sealed file**, as is `ReferenceCase.jl` if the interpreter needs anything
   moved. Ask for explicit permission per file before touching either. (Granted
   for `ReferenceModule.jl`, include + exports + fragment inventory only;
   `ReferenceCase.jl` needed nothing — the interpreter reads its AST types and
   parser from the shared namespace, and adds the `==`/`hash`/`show` those data
   types now need beside itself.)
6. **Seal inventory.** Add `⬜ reference/ReferenceRules.jl` to the ordered list in
   `CLAUDE.md`, in its load position between `ReferenceCase.jl` and
   `ReferenceBuilder.jl`.

## The risk to design against

Two implementations of one matching semantics — the compiled one in
`ReferenceCase.jl` and the interpreted one here — will drift. This codebase has
paid for that before with near-copy projections.

Mitigate it with a **conformance test**, which is also the feature's contract: a
corpus of (pattern, reference) pairs, each written twice — once as a
`@reference_case` block, once as `@reference_rules` applied — asserting the two
answers are identical. Cover binders, `_`, typed binders, literals, `^(…)`,
`when(…)`, `prefix(…)` against `above(…)`, tail binds, `∅`, index and position
steps, extension steps, and paths with and without folded node types.

If the interpreter can instead be made the single source of truth that
`@reference_case` also compiles against, that is better than a conformance test —
but do not restructure the sealed matcher to get there without asking.

## Interaction with type narrowing

There is a sibling plan, `reference-case-type-narrowing.md`, making `::T` narrow
a match where the reference carries a type. `@reference_rules` inherits whatever
the matcher does, so the interpreter must implement the same rule the compiled
matcher ends up with. If both plans are in flight, whichever lands second adopts
the other's semantics and extends the conformance corpus with typed patterns.

## Tests

A new `package/kernel/test/reference/ReferenceRulesTest.jl`, included from
`package/kernel/test/ProjecturedKernelTest.jl` beside its siblings (lines 64-65),
exporting `test_reference_rules` and aggregated by `test_kernel()` (line 143).

- the conformance corpus above;
- first-match-wins, and no match answering `nothing`;
- concatenation as override, in both orders;
- an answer that is rules: the prefix is stripped and the rest asked of them,
  nested at least two deep;
- bindings from an outer prefix visible in an inner answer;
- `^(…)` splicing a value from the construction site, and a rules object still
  answering correctly after the spliced variable changes (it was a value, not a
  reference to one);
- equality, `show`, and round-tripping through serialization, none of which may
  depend on the compiled form.

## What the corpus found

Two constructs cannot be conformed, and both are recorded as their own tests
beside the corpus rather than quietly dropped.

- **A repeated binder crashes `@reference_case`.** `_gen_path_match` generates
  the *rest* of a pattern before the step in front of it, and passes the
  *incoming* `bound` set down, so in `a.field(n).field(n)` the later occurrence
  is the one that emits the `let n = …` binder and the earlier one — which runs
  first — emits `h.name == n` against a variable bound only in the inner scope.
  Every input reaching that step dies with an `UndefVarError`. Same shape inside
  a single step (`items{i:i}`), since `_gen_step_match` generates its value
  patterns inside-out too. The interpreter reads a pattern left to right, so the
  later occurrence compares against what the earlier one bound, which is what
  both DSLs document. **This is a latent bug in a sealed file** — reported, not
  fixed.
- **An above-arm with a guard over a binding the input never reached.** The
  empty path is above everything, so the arm holds without ever reaching its
  index step and the guard then reads a binding that was never made. Both DSLs
  raise there, so that corpus entry runs over the non-empty paths only.

The serialization test also earned its place immediately: caching the compiled
*function* in the answer put a closure type on the wire, and Julia 1.12 reads it
back as a world-age error ("access to binding `ReferenceModule.#62#63` in a world
prior to its definition world … will error in future versions"). The compiled
form is now a **method** of one module-level generic, keyed by a `Val` of a name
derived from the expression and the binding-name set, and what the answer caches
is that name. The method table is the cache, content-addressed, so a rule set
that crosses a process boundary finds no method for its key and compiles it
again — verified by writing a rules object (with its answers already compiled)
from one process and applying it in another.

## Verification

Run from the repo root environment, memory-capped under `systemd-run`.

- `test_reference_rules()`, `test_reference_eval()`, `test_reference_builder()`.
- Then `test_kernel()`; this fragment is additive, so `test_base()`,
  `test_visual()` and `test_domain()` should be untouched — run them once to
  confirm that.

**Result.** `test_reference_rules()` 424 pass; `test_reference_eval()` 7;
`test_reference_builder()` 30; `test_kernel()` 895 pass / 3 fail / 2 error, where
those five are the known pre-existing `DocumentMacro` "Rule C" failures — the
same five, subtest for subtest, on a clean-main worktree. `test_base()` 387 pass,
`test_visual()` 49534 pass / 1 broken, `test_domain()` 184679 pass / 5 broken, no
failures or errors. Also clean under `--depwarn=error`.

## Left open

- **The pattern AST is not exported.** `PatStep`, `PatValue` and their subtypes
  are the shape of a rules pattern, so building or inspecting one outside the
  kernel — the configuration-read-from-a-file case this feature exists for —
  needs them public. Only the macro path works today. That is ~16 more names on
  `ReferenceModule`'s sealed export list.
- **`match_reference_step_value` is declared in this fragment**, not in
  `ReferenceInterface.jl` where a layer's open generics belong
  ([AR-INTERFACE-DECLARES-ONLY](../../documentation/architecture-requirements.md#ar-interface-declares-only));
  that file is sealed. The error default stays here either way, beside the DSL
  that first reaches it, as `match_reference_step`'s does in `ReferenceCase.jl`.
- **No extension step registers the interpreted seam yet.** `.point`, `.proj`,
  `.sample` and `.row` each need one method in the package that owns them before
  a rules pattern can name them; until then the seam's error says so. The kernel
  owns none of them, and the toy step in the test proves the seam.

## Done when

`@reference_rules` builds an object whose patterns are data and whose answers are
expressions, `apply_reference_rules` answers exactly what the equivalent
`@reference_case` block answers across the conformance corpus, rules-as-answer
delegation works with nested bindings, the fragment is included, exported and
listed in `CLAUDE.md`, and `test_kernel()` is green against a clean-main
baseline. **Done.**
