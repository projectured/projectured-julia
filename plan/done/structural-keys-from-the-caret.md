# Structural keys from the caret

> **Status:** done. Written and implemented 2026-09-23, on the branch `feature-videos`.

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

As built (Step 2): the template child delegations use one helper,
`_map_child_backward`. When a child can not map a position of its own output and
its wiring prints parts of its own (a node wiring), the helper makes the child's
own introduced step, and the parent prepends its path as for any other answer.
The `SubNodeSlot` delegation keeps its own handling, because a sub-node shares
the input of its parent. The syntax layer is not changed: a caret in the
indentation of a line stays a flat offset at the level that widens the
indentation. That level prints the widened spaces, so the rule of D2 already
holds there.

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
- [x] Step 2: D2 in the fallbacks, with a test that the caret after a nested value
      and on a nested closing brace is recorded at the nested node.
      `_map_child_backward` in `ProjectionTemplate.jl`. The probe
      (`build/video/probe_json_close.jl`) over `{"a": {"b": "x"}}`, with `Right`
      from `x│`:

      | Press | The caret | `,` adds an entry to |
      | --- | --- | --- |
      | 1 | `.entries[1].value·proj(JsonObjectToSyntaxNode, ·proj(SyntaxCompoundToText, {12}))`, after `"x"` | the nested object |
      | 2, 3 | `·proj(JsonObjectToSyntaxNode, ·proj(SyntaxCompoundToText, {24}))`, `{25}`, the indentation before the nested `}` | the root |
      | 4 | `.entries[1].value·proj(JsonObjectToSyntaxNode, .close{0})`, before the nested `}` | the nested object (D3 changes this) |
      | 5 | `·proj(JsonObjectToSyntaxNode, ·proj(SyntaxCompoundToText, {27}))`, after the nested `}` | the root |
      | 6 | `·proj(JsonObjectToSyntaxNode, .close{0})`, before the root `}` | the root |

      The testset `json/caret-only` builds `{"a": {"b": "x", "c": 1}}` with a `,`
      after `"x"` and `Right`; `test_json_construct()` passes 23 with 2 broken.
      `test_json` 194 pass; `test_kernel` 2059 pass, 3 fail, 3 error, as the
      baseline. Navigation: `json_example` 546 pass; `xml_example` 1462 pass,
      37 fail, where the 37 unreached positions are the same as in the baseline and
      the 12 more positions it now enumerates are all reached; `julia_example` 84
      pass, 28 fail, the same 28 positions.
- [x] Step 3: D3 in the JSON rules, with a test for `,` after a nested `}`.
      The syntax slice has `is_on_closing_delimiter(selection)`: the selection is
      an introduced step whose output path starts at a closing delimiter field
      (`close` of `SyntaxNode` and `SyntaxLeaf`, `closing_delimiter` of
      `SyntaxDelimitation`). The `,` rules of `JsonObject` and `JsonArray` answer
      `nothing` there, so bubbling reaches the parent. In the probe, press 4 (the
      nested `}`) now adds the entry to the root, and press 6 (the root `}`)
      answers nothing, because the root has no parent container. The testset
      `json/caret-only` also builds `{"a": {"b": "x"}, "c": 1}` with four presses
      of `Right` from `"x"│`, and `[[1], 2]` with one `Right` after the `1`;
      `test_json_construct()` passes 27 with 2 broken, `test_json` 194.
- [x] Step 4: the `json_build` live example builds its document with `Right` and no
      `Alt+Up`, and its test replays it.
      `_jb_up(n)` is gone; `_jb_leave(n)` presses `Right` `n` times, from the last
      value past the indentation of the next line and past the closing `}` or `]`:
      5 after a string (the first press leaves the string), 4 after a number. The
      caret then stands after the brace, at the root, and the `,` is the root's.
      A bool can not be left this way (F7 of `feature-video-screenplays.md`): it is
      whole-selected, a plain arrow navigates the tree, and `End` answers nothing.
      So `"meta"` is typed with its bool before its number, and the built document
      differs from `make_json_document_example()` in that order only. The new
      `test_json_build_live()` of `ProjecturedVideoTest` replays the timeline
      headless: no key uses `Alt`, all 215 keys answer an operation, and the
      content is the example document with that order; 3 pass.
- [x] Step 5: the same suites after the change, compared with the baseline.
      `build/suites/run_suites.sh after`, on the branch rebased on `main` at
      cc041a4f: every suite has the counts of the baseline (kernel 2059/3/3,
      substrate 80438/3/2/1, json 194, xml 73, yaml 47 + 2 broken, sql 649, julia
      133, markdown 39, rst 76, math 173), and the failures of the kernel and the
      substrate are at the same six and five places. The navigation of Step 2 and
      the construct and replay tests of Steps 3 and 4 also pass after the rebase.
- [x] Step 6: the documents: the chain reader, the `override` note of `@gestures`,
      and the JSON package guide say what holds now.
      `higher-order-projections.md` and `projection.md` (the chain reader drops a
      claim that no step can carry), `projection-system.md` (the introduced step
      stands at the innermost node; a caret on a node's own delimiter is that
      node's selection), `domain-anatomy.md` (the second path of an edit),
      `json.md` (the key table and two design decisions), and the comments of
      `Gestures.jl` and `GestureBinding.jl`, which said that a claimed key never
      reaches the document.
