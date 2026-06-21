# ProjecturEd presentations

Slide decks about ProjecturEd, written in [Marp](https://marp.app/) Markdown
so they version-control cleanly and render to HTML / PDF / PPTX.

## Decks

- [`projectured-overview.md`](projectured-overview.md) — the most important
  features of the editor (showcase audience). One feature per slide.

## Rendering

Install the Marp CLI once:

```sh
npm install -g @marp-team/marp-cli
```

Then export:

```sh
# HTML (self-contained, open in any browser)
marp presentation/projectured-overview.md -o overview.html

# PDF
marp presentation/projectured-overview.md --pdf -o overview.pdf

# PowerPoint
marp presentation/projectured-overview.md --pptx -o overview.pptx

# Live preview while editing
marp -s presentation/
```

The [Marp for VS Code](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode)
extension gives an inline live preview as well.

## Extending a deck

Slides are separated by `---`. To add one, append a new block:

```md
---

## My new feature

<span class="tag">short qualifier</span>

- Point one.
- Point two.

<span class="muted">relevant/source/path.jl</span>
```

Conventions used in `projectured-overview.md`, reusable as you grow it:

- A centered **section divider** slide before a topic uses `<!-- _class: lead -->`.
- `<span class="tag">…</span>` — a pill caption under the heading.
- `<span class="muted">…</span>` — dimmed source-path / footnote line.
- `<div class="grid">…</div>` — a two-column bullet block.
- Shared theme + colors live in the front-matter `style:` block at the top of
  the deck; edit there to restyle every slide at once.

## Accuracy

The overview deck is grounded in the guides and source. When the project
gains features that are currently forthcoming (e.g. undo/redo, versioning,
live collaboration), update the corresponding slide so claims stay honest —
see [`../guide/roadmap.md`](../guide/roadmap.md).
