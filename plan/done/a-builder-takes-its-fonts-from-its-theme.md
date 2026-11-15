# A builder takes its fonts from its theme

**Status:** done on 2026-11-07 on the branch `builder-fonts`, worktree
`projectured-julia-builder-fonts`. Not landed.

## 1. The problem

[type-rules.md](../../documentation/rule/type-rules.md) section 4 names six
builders that take an exact font as an argument. The plan
[the window has one table of font roles](../done/the-window-has-one-table-of-font-roles.md)
left them open, because each needs a design of its own. The owner asked to fix
them on 2026-11-07.

No caller passes a literal font to any of the six. Each font comes from a role of
a theme. Two different things are wrong:

- **A font beside a theme.** Five builders take a font keyword beside the theme
  that already gives that font, as `WidgetToGraphics(font; theme)` did. The owner
  decided for `WidgetToGraphics` that the fonts come only from the theme, and
  the same rule applies here.
- **Two themes for one text.** The Reference tab and the Selection tab draw one
  line at two sizes. The words take `InspectorTheme.font`, role `code`, 13 px.
  The italic "which is" at the end of a line takes `ReferenceTheme.aside_font`,
  role `document_code`, 14 px. No tab reads `ReferenceTheme.font`, because the
  inspector passes its own font to `ReferenceToText` and
  `ReferenceToHumanReadableText`.

## 2. The decisions

- **D1.** `ReferenceTheme` alone gives the font of a reference shown as text.
  Its roles are `code` and `code` in italic, because the Reference tab and the
  Selection tab are tool panels, and type-rules.md gives `code` to code in a tool
  panel. `InspectorTheme.font` goes. The inspector keeps the font and the colour
  of its headers.
- **D2.** `ReferenceToText` and `ReferenceToHumanReadableText` hold no `font`.
  They read `style.font`.
- **D3.** `ReferenceInspectorToText` holds no `font`. Its blank line takes the
  font of its reference style. `make_reference_inspector_projection` and
  `SelectionInspectorToText` take only `theme` and `reference_theme`.
- **D4.** `SyntaxCompoundToText` takes only `theme` for its styles. The keywords
  `decoration_font` and `ellipsis_style` go, because each one is a font beside
  the theme. No caller passes them.
- **D5.** `ConversationComposerToWidget` does not change. Its builder
  `make_conversation_composer_projection` takes only themes. Its `code_font`
  field holds the value of the theme, as 487 style fields in 37 files of
  `source/` do. This is the pattern that new-domain-guide.md describes.
- **D6.** type-rules.md section 4 says what is true after the change. The math
  builders, `MathToGraphics` and `MathConfig`, still take a `font` beside a
  theme. They are not in the six, and this plan does not change them.

The change that a person sees: in the Reference tab and the Selection tab, the
"which is" is 13 px, the size of the rest of its line.

## 3. The steps

- [x] **Step 1.** (Done, `572c16e5f`.) D1 to D3: the reference text and the inspector, their tests in
  `HelpThemeTest.jl`, and inspector.md.
- [x] **Step 2.** (Done, `e86d98db3`.) D4: `SyntaxCompoundToText`.
- [x] **Step 3.** (Done, `0de51ef21`.) D6: type-rules.md.
- [x] **Step 4.** (Done; the counts are in section 4.) Run the tests of the changed files, and compare the counts
  with `main` `8007b02c8`.

## 4. Notes

- **2026-11-07.** omnet-julia and inet-julia name none of the removed keywords
  and not `InspectorTheme`, so only projectured-julia changes.
- **2026-11-07.** The recorded compiled calls in
  `package/ProjecturedPlatform/precompile/projectured.txt` and
  `package/ProjecturedBuild/precompile/workload.txt` name `InspectorTheme` with
  three fields. A record of those calls is deferred, as in the last plan.
- **2026-11-07, step 4, the counts.** Main `8007b02c8` → the branch:
  `test_help_themes` 81 → 82. In it, the test of `ReferenceToText` gains a check
  that the projection has no `font` field (+1). The test of
  `ReferenceInspectorToText` loses its two size checks of `font` and the check
  of a fixed font, and gains the check of no `font` field (−2). The new testset
  "a line of an inspector draws at one size" adds 2. The same counts on both
  sides: `test_syntax_to_text` 339, `test_appearance_tab` 159,
  `test_appearance_file` 22, `test_tool_themes` 113,
  `test_text_and_syntax_themes` 21, `test_reference_inspector_text` 9,
  `test_tool_views` 19, `test_selection_inspector` 10, `test_documentation` 1.
  `test_style` fails twice on both sides, at `BookModule.jl:34`.
- **2026-11-07, step 4, the load.** Both sides warn that recorded calls no longer
  resolve, with the same counts: ProjecturedWorkflow 60 of 571, ProjecturedChart
  60 of 546, ProjecturedDBCatalog 2 of 2, ProjecturedFSM 2 of 19,
  ProjecturedResearch 77 of 510. The branch adds no warning.
