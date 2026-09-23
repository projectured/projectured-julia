# An evaluated form is parsed whatever its spacing

**Status (2026-09-23): IN PROGRESS.** Worktree
`../projectured-julia-evaluator-parse-spacing`, branch `evaluator-parse-spacing`,
from `main` at `185beeb3`. It follows `plan/done/evaluator-parses-forms.md`.

**Goal:** `1+1` and `1 + 1` both become a Julia document when they are
evaluated. Today only the second does: the rule of that plan compares the print
of the parsed document with the typed code character by character, so a
difference of spacing keeps the form a string.

## 1. Decisions

The owner decided D1 and D2 on 2026-09-23.

- **D1. The comparison ignores spacing.** The typed code and the print of the
  parsed document are compared token by token, and the spaces and line breaks
  between tokens are skipped. A space inside a string is part of a token, so a
  string whose content changed still keeps the form a string, and so does a
  comment, which is a token too. The form shows the spacing of the Julia
  notation after Enter: `1+1` shows as `1 + 1`.
- **D2. A recall shows the print.** Up recalls `1 + 1` after `1+1` was typed.
  The spacing is not important, so the history reads no `source`.
- **D3. The tokens come from `Base.JuliaSyntax.tokenize`**, the tokenizer of the
  parser that `Meta.parse` runs. No package dependency is added.

Measured on 2026-09-23 with the prints recorded by the first plan: the token
rule converts `1+1`, `1 +  2`, `f(a,b)`, code indented by four, and two
statements with blank lines between them. It keeps as strings the code with a
comment, a string whose content the printer would change, a lambda to which the
printer adds parentheses, and a docstring the printer reflows.

## 2. Steps

- [ ] **Step 1. The token comparison.** Replace the exact comparison in
  `_parse_evaluated_form!`. Tests: `1+1` becomes a `JuliaBinaryOperation`, a
  form with a comment stays a string, a form with `max(1,2)` now becomes Julia,
  the result is the same with the parse on and off.
- [ ] **Step 2. A form of several statements in the window.** The Julia domain
  prints a top-level block as `"\n  g(c)\n  h(d)\n"`. Check what the window
  draws for it. If it draws an empty first or last line, keep such a form a
  string until the printer of a block is fixed, and say so in the limits of
  the package document.
- [ ] **Step 3. The package document** says that spacing is ignored.
