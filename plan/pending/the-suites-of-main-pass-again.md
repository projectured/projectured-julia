# The suites of main pass again

**Status (2026-10-14): IN PROGRESS.** The owner asked to record these failures in a plan, and
then to start step 1 with the type-in of item 7. Items 1, 3, 6, 7 and 10 are fixed, and items 2 and 4 pass on
`main` with no change of their own.

**Goal:** each failure of §1 is fixed, or marked with `@test_broken` and its reason, so that a
suite on `main` shows no unmarked failure.

## 1. The failures

The retest of step 5 of [strict-document-types.md](strict-document-types.md) found them on
`main` at `c345fe385`, on 2026-10-13. A detached worktree at `c345fe385` with that step reverted
gives the same count for each, so none comes from it. A commit is named where the origin is
known; elsewhere the origin is not found yet.

1. **`test_julia_expression`, 1 failure** (`JuliaExpressionTest.jl:31`, "every Julia example
   becomes the Expr of its own text"). The test takes every function named
   `make_julia_*_document_example`. The new `make_julia_code_document_example` (`fba0f2f7b`)
   gives a `WidgetScrollPane` around a `JuliaBlock`. `make_julia_expression` of a document
   that is not Julia gives that object alone, so it differs from the `Expr` of the text. **Fixed (`88ae7630a`, step 2):**
   the test skips an example that is no Julia document. 80 of 80.
2. **`test_external_agent_turn`, 50 failures and 29 errors; `test_assistant_overview`, 1
   failure and 1 error** (`AssistantOverviewTest.jl:154`). The test sets: "the events of the
   agent become parts", "the turn says that the agent starts until its session is open", "a
   second turn sends only what came since the last answer", "a turn that never reached the
   agent is in the next prompt", "an agent that needs a sign-in gives a request, and a retry
   starts it", "a question of the agent is a form, and its values go back", and "a question of
   the agent is the turn of the person". **Passes on `main` at `08fffddb2`** (2026-10-15): the whole
   `test_platform`, which runs `test_conversation`, gives 152605 passes, 7 broken and no
   failure.
3. **`test_interface_api`, 2 failures** (`InterfaceApiTest.jl:46` and `:49`). The test counts
   32 declared names where it expects 31. The docstring of `WidgetProgressRing` has no line
   that starts with "Use it to". **Fixed (`564cf4394`, step 2):** the ring is a name of the
   vocabulary on purpose, so the test counts 32, and its docstring has the line. 138 of 138.
4. **`test_mcp_log_pane`, 1 failure** (`McpLogTest.jl:55`). The pane draws no separate texts
   `x = 1` and `x + 1` for code of two lines. **Only after other tests:** alone, the test
   passes, 14 of 14, at `a9cf7bbaa`, its parent, `c345fe385` and `7e31ba460` (2026-10-14). The
   failure came in the run of the whole `test_platform`, so an earlier test of that run leaves
   a state that the pane reads. A bisect over commits can not find it; a search over the
   order of the tests can. **Passes on `main` at `08fffddb2`** (2026-10-15) in the whole
   `test_platform` too, so no search is needed.
5. **`test_parse_markdown_blocks`, 1 failure** (`ConversationParsingTest.jl:48`). A fenced code
   block of the language `unknownlang` gives no `TextBlock` that holds that word. **Fails alone on
   `main` at `5a74db9d9`** (2026-10-15). **Origin: `ba1957607`** (2026-10-12, found by a bisect from
   `5d4c1269e`, 10 steps), "conversation, assistant: a part and the body of a draft are
   lines". The change is on purpose: the fenced text is now a block of lines. The helper
   `_cp_flat` of the test reads only the spans directly in a block, so it reads an empty
   string: a change of the test, to `get_flat_string`.
6. **The position walk of the atomic example `widget/progress_bar/graphics`, 1 failure**
   (`NavigationTest.jl:180`). The walk reaches no state: Ctrl+Home, the seed of the walk,
   gives `nothing`. **Origin: `8389450e8`** (2026-10-06, found by a bisect from `5d4c1269e`,
   10 steps), "example: the progress ring, and a bar whose value is not known". The atom
   `progress_bar` of the catalog uses `make_widget_progress_bar_document_example`, which from
   that commit stacks two bars in a `VerticalLayout`, where the seed finds no selection. The
   atoms `separator` and `skeleton` have an atom function of their own for the same reason
   (`make_widget_separator_atom_document_example`). **Fixed (`2c0ca015f`, step 2):** the atoms
   `progress_bar` and `progress_ring` make one widget each; the examples keep their layouts.
   `test_catalog` of each entry passes, 1723 and 1720 tests.
7. **The type-in of the atomic example `text/line/graphics`, 1 failure** (`TypeinTest.jl:639`,
   in `test_catalog_typeins`). Backspace at the start of the first string of the second line,
   `.elements[2].elements[1].content{0}`, gives `ReplaceTextRangeOperation(⌶{7:12})`, and the
   walk expects no edit there. **Origin: `a3489a00e`** (2026-10-11, found by a bisect from
   `5d4c1269e`, 11 steps), "text: Enter breaks a line, and Backspace or Delete at a line
   boundary joins two". The change is on purpose: N10 of
   [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md) makes
   Backspace at the start of a line cover the break and the indentation of the lower line, and
   that plan left "the sweep is pending". So the walk keeps a rule that changed: a change of
   the test. `test_catalog` of Markdown, RST and math passes on `main` at
   `a5a408b83` (35803, 74477 and 44289 tests). **Fixed (`b811e2ed0`, step 2):** the walk
   expects the join at a line boundary of a block of lines and asserts it without evaluating
   it. Delete at the end of "alpha" makes the same join; an older `@test_broken` mark for the
   value/chrome seam hid it, and it now passes. `test_catalog_typeins`: 102 passes and 2
   broken, from 100, 1 failure and 3 broken. `test_typeins` stays 5148 and 20 broken.
8. **`test_application`, 2 failures and 2 errors.**
   - "the Evaluator button opens an evaluator, and Enter evaluates what is typed"
     (`ApplicationTest.jl:1066` and `:1077`): the window draws no separate text `x + 1` for a
     form of two lines.
   - "Up and Down in the evaluator recall its history through the window" (`:1114`): the form
     shows `a = 1` where `b = 2\nb + 1` is expected.
   - "a closed assistant and a closed Files pane come back as they were" (`:1462`): the greeting
     prints as the representation of a `TextBlock`, so the word "Ollama" is not found.
   **All four fail alone on `main` at `5a74db9d9`** (2026-10-15, with no network).
   **Origin of the first two: `86a16ec8f`** (2026-10-12, found by a bisect, 4 steps), "text:
   TextToGraphics lays out lines only". The form of the evaluator holds its code in a
   `PrimitiveString`, and `PrimitiveStringToTextBlock` drew the value as one run, which after
   Shift+Enter held a `'\n'`. Step 7 of
   [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md) names
   `PrimitiveToText` among the producers that give lines, and its guard walks the examples as
   they are made, where no primitive string holds a break. **Fixed (step 2):** the projection
   gives a line for each line of the value. **The greeting: origin `ba1957607`**, as item
   5 (found by a bisect from `62ee4b4da`, where the test came, 10 steps). The test read the
   part with `string`, which gives the representation of a block of lines. **Fixed (step
   2):** it reads the flat string of the part. `test_application` 379 and 2 broken, no
   failure.
9. **`test_catalog_coverage`, 1 failure** (`CatalogCoverageTest.jl:223`). Eleven document types
   have no entry in the catalog: `FilteredText`, `FindBarView`, `GraphicsRect`,
   `HighlightedText`, `ScrollLayout`, `TaskGroupDocument`, `TaskGroupList`, `TerminalDocument`,
   `TextGutter`, `WidgetProgressBar` and `WidgetProgressRing`. The test failed in the same way
   on 2026-10-01, with another list. The atoms of `2c0ca015f` (item 6) cover the two progress
   widgets. On 2026-10-14 the list has ten names: the nine others and `Roster`, which is new. On 2026-10-15
   (`5a74db9d9`) it has 14: the task pages of `02d2b2525` add `TaskDocument`, `TaskStream`,
   `TaskStreamLines` and `ACTaskExecution`. A name with the prefix `AC` is a name of the cell
   layout of `TaskExecution`, which the stem of the test does not take off. **Decided by the owner, 2026-10-15:** "ideally all
   testable documents should be in the atomic catalog, that's an automated test suite
   primarily, not an end user concept". Each type that a test can make gets an atom, also a
   part of a page. A cell layout of a document counts as its document by the schema name
   (`get_document_schema_name`). Only a type that no test can make goes on the list of
   exclusions, with its reason. **Decided by the owner, 2026-10-15:** the 14 types of
   the failing test now; the 36 older types of `_NO_ATOM` in a later step. **Built:** the
   test counts a type under its schema name, and 10 atoms pass the catalog:
   `widget/find_bar`, `layout/scroll`, `roster/roster`, `terminal/terminal`, and `task/`
   `task`, `group`, `group_list`, `execution`, `stream` and `stream_lines`. A task atom
   comes from one build step that has not run, so a test starts no process. **Held back:**
   the atoms of `HighlightedText`, `FilteredText` and `TextGutter` fail the catalog testers
   about 1300 times, because a single-step projection of the catalog has no recursion for
   the text or the marks that they hold, the reason that marks the layouts broken; the atom
   of `GraphicsRect` fails twice with `getindex(nothing)`. **New on `main`:** `AgentWork`,
   `AssistantWork`, `DocumentTree`, `SystemProcess`, `SystemProcessTree`, `WorkPlan` and
   `WorkPlanStep` have a printer and no atom (2026-10-15).
10. **`test_window_wrappers`, 2 failures, only after other tests in the same process**
    (`WindowWrappersTest.jl:116` and `:128`). Both assert that the gesture log of the session
    grows after Ctrl+T. The log keeps 20 entries, so the assertion fails when earlier tests
    filled it. Alone, the test passes. **Fixed (`aa99356da`,
    step 2):** both assert that `count` grows and that the newest entry is Ctrl+T. 47 of 47,
    also after 25 entries filled the log, where the length stays 20.

A hypothesis, checked and wrong for item 4: items 4 and the first two tests of item 8 all miss
a separate text for the second line of code, and the change "a run of a compound is one entry
on its line" (`a9cf7bbaa`) was a candidate origin. Item 4 passes alone at that commit and
after it. The first two tests of item 8 can depend on the order of the tests in the same way.

## 2. The steps

- [ ] **Step 1: the origin of each failure.** For each item of §1 with no known origin, find the
  commit that made it fail, by a bisect in a detached worktree, and write it into §1.
- [ ] **Step 2: a fix or a mark for each item**, one commit each. The fix is in the code, or in a
  test that asserts a fact that changed on purpose, or a `@test_broken` with the reason in a
  `# @broken:` comment (testing-guide.md). Items 1, 9 and 10 are likely changes of the test:
  item 1 skips a document that is not Julia, item 9 adds the catalog entries or the
  exclusions, and item 10 asserts the newest entry and not the length of the log.
- [ ] **Step 3: the check.** Run each test of §1 again. Each shows no unmarked failure.
