# The suites of main pass again

**Status (2026-10-13): IN PROGRESS, step 1.** The owner asked to record these failures in a
plan, and then to start step 1 with the type-in of item 7. Item 7 has its origin.

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
   that is not Julia gives that object alone, so it differs from the `Expr` of the text.
2. **`test_external_agent_turn`, 50 failures and 29 errors; `test_assistant_overview`, 1
   failure and 1 error** (`AssistantOverviewTest.jl:154`). The test sets: "the events of the
   agent become parts", "the turn says that the agent starts until its session is open", "a
   second turn sends only what came since the last answer", "a turn that never reached the
   agent is in the next prompt", "an agent that needs a sign-in gives a request, and a retry
   starts it", "a question of the agent is a form, and its values go back", and "a question of
   the agent is the turn of the person".
3. **`test_interface_api`, 2 failures** (`InterfaceApiTest.jl:46` and `:49`). The test counts
   32 declared names where it expects 31. The docstring of `WidgetProgressRing` has no line
   that starts with "Use it to".
4. **`test_mcp_log_pane`, 1 failure** (`McpLogTest.jl:55`). The pane draws no separate texts
   `x = 1` and `x + 1` for code of two lines.
5. **`test_parse_markdown_blocks`, 1 failure** (`ConversationParsingTest.jl:48`). A fenced code
   block of the language `unknownlang` gives no `TextBlock` that holds that word.
6. **The position walk of the atomic example `widget/progress_bar/graphics`, 1 failure**
   (`NavigationTest.jl:180`). The walk reaches no state.
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
   `a5a408b83` (35803, 74477 and 44289 tests).
8. **`test_application`, 2 failures and 2 errors.**
   - "the Evaluator button opens an evaluator, and Enter evaluates what is typed"
     (`ApplicationTest.jl:1066` and `:1077`): the window draws no separate text `x + 1` for a
     form of two lines.
   - "Up and Down in the evaluator recall its history through the window" (`:1114`): the form
     shows `a = 1` where `b = 2\nb + 1` is expected.
   - "a closed assistant and a closed Files pane come back as they were" (`:1462`): the greeting
     prints as the representation of a `TextBlock`, so the word "Ollama" is not found.
9. **`test_catalog_coverage`, 1 failure** (`CatalogCoverageTest.jl:223`). Eleven document types
   have no entry in the catalog: `FilteredText`, `FindBarView`, `GraphicsRect`,
   `HighlightedText`, `ScrollLayout`, `TaskGroupDocument`, `TaskGroupList`, `TerminalDocument`,
   `TextGutter`, `WidgetProgressBar` and `WidgetProgressRing`. The test failed in the same way
   on 2026-10-01, with another list.
10. **`test_window_wrappers`, 2 failures, only after other tests in the same process**
    (`WindowWrappersTest.jl:116` and `:128`). Both assert that the gesture log of the session
    grows after Ctrl+T. The log keeps 20 entries, so the assertion fails when earlier tests
    filled it. Alone, the test passes.

A hypothesis, not checked: items 4 and the first two tests of item 8 all miss a separate text
for the second line of code. The change "a run of a compound is one entry on its line"
(`a9cf7bbaa`) is a candidate origin.

## 2. The steps

- [ ] **Step 1: the origin of each failure.** For each item of §1 with no known origin, find the
  commit that made it fail, by a bisect in a detached worktree, and write it into §1.
- [ ] **Step 2: a fix or a mark for each item**, one commit each. The fix is in the code, or in a
  test that asserts a fact that changed on purpose, or a `@test_broken` with the reason in a
  `# @broken:` comment (testing-guide.md). Items 1, 9 and 10 are likely changes of the test:
  item 1 skips a document that is not Julia, item 9 adds the catalog entries or the
  exclusions, and item 10 asserts the newest entry and not the length of the log.
- [ ] **Step 3: the check.** Run each test of §1 again. Each shows no unmarked failure.
