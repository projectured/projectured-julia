# Plan: Automated screenshot generation and guide injection

## Context

Four of 27 examples already have screenshots in `image/` (json, widget, table, julia). `README.md` shows these four in a 2×2 table; `guide/examples-tour.md` links to the `image/` directory but embeds no images inline. The goal is:
1. A Julia function that generates PNG screenshots for **all 27 examples** automatically in a single step.
2. A second Julia function that injects image references into the affected guide files idempotently.

Both functions live alongside the existing `run_example`/`write_image_example` helpers in `example/src/Examples.jl` and are exported from `ProjecturedExample`. Users run them from the REPL — no `tools/` scripts, no Makefile, no shell glue.

---

## Constraints and key facts

- `write_image_example(name, path; width, height)` writes PNG directly when `path` ends in `.png` (SDL backend in `program/src/backend/Sdl.jl`). No BMP intermediate, no external conversion tool required.
- Existing images are 960×640 pixels — the new screenshots should match.
- Naming pattern in `image/`: `{example-name}-example.png` (hyphens, not underscores, e.g. `json_sorted` → `json-sorted-example.png`).
- The 27 examples are defined in `example/src/Examples.jl:11–49` as `const examples = [...]`.
- Functions are invoked from the REPL with `using ProjecturedExample` (picks up `Projectured` transitively).

---

## Step 1 — `generate_screenshots` function in `example/src/Examples.jl`

Add and export a new function next to `write_image_example`:

```julia
"""
    generate_screenshots(; width=960, height=640,
                          image_dir=joinpath(@__DIR__, "..", "..", "image"))

Generate a PNG screenshot for every example in `examples` into `image_dir`.
Filename pattern: `{example-name-with-hyphens}-example.png`. One failure does
not abort the batch.
"""
function generate_screenshots(; width=960, height=640,
                              image_dir=joinpath(@__DIR__, "..", "..", "image"))
    mkpath(image_dir)
    for ex in examples
        safe_name = replace(ex.name, "_" => "-")
        png = joinpath(image_dir, "$safe_name-example.png")
        @info "Generating $(ex.name)..."
        try
            write_image_example(ex, png; width=width, height=height)
            @info "  ✓ $png"
        catch e
            @warn "  ✗ $(ex.name): $e"
        end
    end
end
```

Export from `example/src/ProjecturedExample.jl` alongside the other example helpers.

Key design choices:
- Underscore → hyphen in filename (matches existing convention: `julia_example` → `julia-example.png`).
- `try/catch` per example so one failure doesn't abort the whole batch.
- PNG is written directly by the SDL backend — no external tool, no intermediate BMP.
- `width=960, height=640` matches existing four screenshots.

---

## Step 2 — `update_guide_screenshots` function in `example/src/Examples.jl`

Add and export a second function in the same file. Idempotent — running it again produces no diff.

```julia
"""
    update_guide_screenshots(; repo_root=joinpath(@__DIR__, "..", ".."))

Inject `![...](...)` image references into the guide files and `README.md`.
Idempotent: re-running produces no changes once images are in place.
"""
function update_guide_screenshots(; repo_root=joinpath(@__DIR__, "..", ".."))
    _update_examples_tour(joinpath(repo_root, "guide", "examples-tour.md"))
    _update_domain_guides(joinpath(repo_root, "guide", "document"))
    _update_readme(joinpath(repo_root, "README.md"))
end
```

The three private helpers handle the three guide regions described below. Export `update_guide_screenshots` from `ProjecturedExample`.

### 2a — `guide/examples-tour.md`

The file has six `##` sections, each with a header like:
```
## 1. JSON (`run_example("json")`)
```

After each such header (and the blank line following it), insert the screenshot if not already present:
```markdown
![JSON example](../image/json-example.png)
```

Pattern to match: `r"^## \d+\. \w+ \(`run_example\(\"(\w+)\"\)`\)"` → captures example name. Skip insertion if the very next non-blank line is already `![...](../image/{name}-example.png)`.

Also update the preamble (line 5) from the link-only reference to a proper description now that images are embedded inline.

### 2b — `guide/document/*.md` domain guides

Eight files: json.md, xml.md, text.md, syntax.md, graphics.md, widget.md, workbench.md, collection.md.

Map each filename to the corresponding example name (e.g. `json.md` → `json`, `workbench.md` → `workbench`). Insert a screenshot block at the top of the file, **after the first `#` heading and its introductory paragraph**, if not already present:

```markdown
![JSON example](../../image/json-example.png)
```

Detection: if any `![` line already exists in the first 15 lines, skip.

### 2c — `README.md`

Currently shows 4 screenshots in two `| A | B |` tables. Expand to show all 6 tour examples (json, syntax, widget, table, julia, workbench) in a **3×2 grid**. Replace the existing screenshot table block (lines 35–41) with:

```markdown
## Screenshots

| JSON editor | Widget forms | Table view |
|---|---|---|
| ![JSON example](image/json-example.png) | ![Widget example](image/widget-example.png) | ![Table example](image/table-example.png) |

| Syntax tree | Julia AST | Workbench |
|---|---|---|
| ![Syntax example](image/syntax-example.png) | ![Julia AST example](image/julia-example.png) | ![Workbench example](image/workbench-example.png) |
```

---

## Step 3 — Document in `guide/debugging.md`

Add a section "## Generating all screenshots" that documents the REPL workflow:

```julia
using ProjecturedExample
generate_screenshots()        # writes PNGs into image/
update_guide_screenshots()    # injects ![...] references into guides + README
```

- Output goes to `image/` as PNG files (one step, no extra tools).
- Both functions accept keyword overrides (`width`, `height`, `image_dir`, `repo_root`).

---

## Files created / modified

| File | Action |
|---|---|
| `example/src/Examples.jl` | Modified — add `generate_screenshots` and `update_guide_screenshots` (+ private helpers) |
| `example/src/ProjecturedExample.jl` | Modified — export the two new functions |
| `guide/examples-tour.md` | Modified — inline `![...]` after each of 6 `##` headings |
| `guide/document/json.md` | Modified — add screenshot near top |
| `guide/document/xml.md` | Modified — add screenshot near top |
| `guide/document/text.md` | Modified — add screenshot near top |
| `guide/document/syntax.md` | Modified — add screenshot near top |
| `guide/document/graphics.md` | Modified — add screenshot near top |
| `guide/document/widget.md` | Modified — add screenshot near top |
| `guide/document/workbench.md` | Modified — add screenshot near top |
| `guide/document/collection.md` | Modified — add screenshot near top |
| `README.md` | Modified — expand screenshot table from 4 to 6 examples |
| `guide/debugging.md` | Modified — add "Generating all screenshots" section |

---

## Verification

From a Julia REPL started with `julia --project=.`:

```julia
using ProjecturedExample

# 1. Generate all screenshots (PNG written directly by the SDL backend)
generate_screenshots()

# 2. Run guide injection
update_guide_screenshots()

# 3. Verify idempotency
update_guide_screenshots()   # second call produces no further changes
```

Then from the shell:

```bash
# 4. Confirm images exist
ls -1 image/*-example.png | wc -l   # should be 27

# 5. Inspect guide changes
git diff guide/ README.md

# 6. Spot-check that image paths resolve
# Open guide/examples-tour.md in a markdown previewer
```
