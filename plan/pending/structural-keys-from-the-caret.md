# Structural keys from the caret

> **Status:** in progress. Written 2026-09-23.

A structural key typed from the text caret reaches the domain that owns its
meaning again. In JSON: a `,` after a string value, inside or after a number, or
after the closing brace of a nested object inserts the next entry, with no switch
to a structural selection. It is step 1 of the caret-only JSON video of
`feature-video-screenplays.md` (§8, F2 and F3).

## 1. The request and the owner's decisions (2026-09-23)

> so it is B, I agree
>
> for the comma issue: a projection induced part should always be mapped from the
> innermost input object, so in other words the projection step should be as late
> in the reference as possible.
>
> so yes to all three

| # | Decision |
| --- | --- |
| D1 | **B:** in the chain reader, a claim that no stage can carry is no claim. When a stage can not translate the operation an output stage made of a key, that stage and the stages before it read the raw key, as if nobody had claimed it. |
| D2 | **The latest step:** a part that a projection introduces (a delimiter, a separator, layout text) is mapped from the innermost input object whose projection printed it. The projection step stands as late in the reference as it can. |
| D3 | **A container declines `,` on its own closing delimiter,** so its parent answers the key. |

## 2. What the diagnosis showed

Probes over the `json_build` example, headless, with a real `Editor`
(`build/video/probe_json_caret.jl`, `probe_json_chain.jl`, `probe_json_close.jl`
of the worktree `feature-videos`):

- A `,` after `"Alice"│` (after `Right` or `End`) and a `,` in `30│` both answer
  nothing. The text stage claims the key as a character insert
  (`ReplaceStringRangeOperation`), the syntax stage carries it, and the JSON
  stage can not: the claim dies there. Read with the raw key, the JSON stage
  answers the object's `,` rule, a `CompoundOperation` that appends an entry.
- The June work (`plan/done/json-contextual-gestures.md`) gave the input stage a
  direct read of every key. The chain now has the `override` flag in its place,
  and the JSON `,` rules are not `override`. The documentation of `@gestures`
  keeps `override` for a key that can not be text in its context, which a `,`
  can be.
- A caret on a delimiter is recorded at the outermost JSON object. In
  `{"a": {"b": "x"}}`, the caret after `"x"` and the caret on the nested `}` are
  both a projection step at the root object, with a path into the whole syntax
  output (`children[1].children[2].close{0}`), and for layout positions a flat
  offset (`{12}`, `{24}`, `{25}`) inside a projection step of the syntax layer.
  The nested object's own selection holds nothing.

## 3. The design

### 3.1 D1, in the chain reader

`read_intent(::ChainingProjection, …)` in `source/projection/higherorder/Chaining.jl`
searches the stages from the output end for one that answers the raw key, then
carries that answer back. Today, when a stage translates the answer into nothing,
the chain answers nothing. With D1, that stage and the stages before it read the
raw key instead, and their answer is carried back from there. A key that some
stage carries is untouched; only a lost key changes.

### 3.2 D2, in the fallbacks that make a projection step

A projection step is made where a projection can not map a reference back: the
template fallback in `source/kernel/projection/ProjectionTemplate.jl`
(`read_intent(::Projection, ::RuleIoMap, ::ReplaceSelectionOperation)`) and the
flat-offset fallback of the syntax layer. Each wraps the position at the level
where the mapping failed. With D2, a level first finds the child whose output
holds the position and lets that child map it, so the step is made by the
innermost printer of the position, and each level above reroots it under its own
steps.

### 3.3 D3, in the JSON rules

The `,` rule of `JsonObject` and of `JsonArray` declines when the node's own
selection is a projection step on its closing delimiter. Bubbling then reaches the
parent entry and the parent container, whose `,` rule answers.

## 4. Steps

- [x] Step 0: the baseline, before any change, on the branch `feature-videos` at
      8023e48d (`build/suites/run_suites.sh before`, 8 GB caps, one process at a
      time):

      | Suite | Pass | Fail | Error | Broken |
      | --- | --- | --- | --- | --- |
      | `test_kernel` | 2059 | 3 | 3 | 0 |
      | `test_substrate` | 80438 | 3 | 2 | 1 |
      | `test_json` | 194 | 0 | 0 | 0 |
      | `test_xml` | 73 | 0 | 0 | 0 |
      | `test_yaml` | 47 | 0 | 0 | 2 |
      | `test_sql` | 649 | 0 | 0 | 0 |
      | `test_julia` | 133 | 0 | 0 | 0 |
      | `test_markdown` | 39 | 0 | 0 | 0 |
      | `test_rst` | 76 | 0 | 0 | 0 |
      | `test_math` | 173 | 0 | 0 | 0 |

      The failures of the kernel are the known Rule C cases of
      `DocumentMacroTest.jl` and one of `ReferenceEvalTest.jl:209`; those of the
      substrate are the known split-pane drags of `SplitPaneDragTest.jl`.

      Navigation with `check_reaches_all` (`build/suites/navigation.jl`):
      `json_example` 546 pass; `xml_example` 1450 pass, 37 fail; `julia_example`
      84 pass, 28 fail. There is no `sql_example`; the SQL suite runs its own
      navigation test.
- [x] Step 1: D1 in the chain reader, with a test of a key whose claim dies.
      `_read_chain_from` in `Chaining.jl`: when a step can not carry the answer
      of a later step, reading starts again at that step with the raw gesture. The
      testset `json/caret-only` of `test_json_construct()` builds
      `{"name": "Alice", "age": 30, "city": "W"}` with `Right` after a string and
      `,` after a number; `test_json_construct()` passes 21 with 2 broken, the two
      known empty containers. The docstring of the chain reader already promised
      this ("a `,` on a delimiter where the text edit would die becomes a JSON
      sibling insert"), and it gained the paragraph that states the rule.
- [ ] Step 2: D2 in the fallbacks, with a test that the caret after a nested value
      and on a nested closing brace is recorded at the nested node.
- [ ] Step 3: D3 in the JSON rules, with a test for `,` after a nested `}`.
- [ ] Step 4: the `json_build` live example builds its document with `Right` and no
      `Alt+Up`, and its test replays it.
- [ ] Step 5: the same suites after the change, compared with the baseline.
- [ ] Step 6: the documents: the chain reader, the `override` note of `@gestures`,
      and the JSON package guide say what holds now.
