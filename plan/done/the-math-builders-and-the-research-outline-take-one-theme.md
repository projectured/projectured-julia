# The math builders and the research outline take one theme

**Status:** done on 2026-11-07 on the branch `math-research`, worktree
`projectured-julia-math-research`. Not landed.

## 1. The problem

The owner asked on 2026-11-07 to fix the two items that the plan
[a builder takes its fonts from its theme](../done/a-builder-takes-its-fonts-from-its-theme.md)
left open.

- **The math builders take values beside their theme.**
  `MathToGraphics(; measure, theme, style, font, slanted, ink, hint)` and
  `MathConfig(; theme, measure, font, slanted, ink, hint, selection_wash)` take
  each font and each color as a keyword beside `MathTheme`, which already gives
  them. A value given as a keyword replaces the value of the theme. No caller
  passes any of these keywords.
- **No code reads `ResearchTheme`.** The outline of a study draws every text
  with the shared outline kit, so its theme is `OutlineTheme`. No view asks for
  `ResearchTheme`, so the appearance tab does not show it either. Its file also
  holds `_get_status_badge_role`, which the outline row and the explorer use.

## 2. The decisions

- **D1.** `MathToGraphics(; measure, theme, style)` and `MathConfig(; theme,
  measure)` take every font and every color from the theme. The owner decided
  that the fonts of a builder come only from its theme. A color beside the theme
  has the same form, so `ink` and `hint` go with `font` and `slanted`, and
  `MathConfig` also loses `selection_wash`.
- **D2.** `ResearchTheme` and `ScaledResearchTheme` go.
  `_get_status_badge_role` moves to `ResearchToWidget.jl`, beside the badge that
  uses it.
- **D3.** type-rules.md section 4 says that no builder takes a font beside its
  theme. math.md shows the new signature.

Nothing changes on the screen.

## 3. The steps

- [x] **Step 1.** (Done, `742fb47ec`.) D1 and the math part of D3.
- [x] **Step 2.** (Done, `2af8db6fe`.) D2.
- [x] **Step 3.** (Done; the counts are in section 4.) Run `test_math`, `test_research`, `test_documentation` and
  `test_style` on the branch and on `main` `c1b1f6e0e`, and compare the counts.

## 4. Notes

- **2026-11-07.** omnet-julia and inet-julia name none of the removed keywords
  and not `ResearchTheme`, so only projectured-julia changes.
- **2026-11-07.** The recorded compiled calls of `ProjecturedResearch` and
  `ProjecturedBuild` name `ResearchTheme`. A record of those calls is deferred,
  as in the last two plans.
- **2026-11-07, step 3, the counts.** The same on `main` `c1b1f6e0e` and on the
  branch: `test_math` 215, `test_research` 386, `test_documentation` 1.
  `test_style` fails twice on both sides, at `BookModule.jl:34`.
- **2026-11-07, step 3, the load.** The recorded calls of `ProjecturedResearch`
  that no longer resolve go from 77 to 82 of 510. The five more are the five
  recorded calls that name `ResearchTheme`. The other warnings are the same on
  both sides: ProjecturedWorkflow 60 of 571, ProjecturedChart 60 of 546,
  ProjecturedDBCatalog 2 of 2, ProjecturedFSM 2 of 19.
