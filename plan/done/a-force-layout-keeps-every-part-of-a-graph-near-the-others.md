# A force layout keeps every part of a graph near the others

## 1. The request

The owner, 2026-10-27, after the map of the Aloha study showed one box on an
empty pane: "let's fix the built-in layout". The map of a study with 41 items,
laid out by `FruchtermanReingoldLayout`, put S3, an item with no link, at the
origin, and the 38 linked items from x 6386 to 11486. Two more items with no
link went to (17221, 7201) and (9431, 13052).

## 2. Facts (triage, 2026-10-27)

- One layout call: 41 vertices, no constraint, no extent, border 0. So the
  drawing starts at the border, and its top-left box is an item with no link.
- **A body with no edge drifts out.** It feels the push `k²/rim` of every other
  body at any distance, and only the pull `0.02 · distance` to the centre. The
  two balance at about `k · sqrt((m - 1) / 0.02)`: about 45 k for 41 bodies.
- **A group spreads.** A tree of 40 boxes of 228 × 150 takes 5775 × 6952 px, about
  30 times the area of its boxes. Every box pushes every other box, however far.
- The reproduction is a plain `GraphGraph`: a binary tree of `n` vertices and
  one vertex with no edge, laid out by `layout_graph(FruchtermanReingoldLayout(),
  graph, sizes, [])`.

| n | box | the vertex with no edge | the tree |
| --- | --- | --- | --- |
| 2 | 228 × 150 | (2116, 1949) | x 0–548, y 0–503 |
| 11 | 228 × 150 | (0, 0) | x 1779–4656, y 3221–5555 |
| 40 | 228 × 150 | (0, 0) | x 1785–8516, y 4840–10836 |
| 40, no lone vertex | 228 × 150 | — | 5775 × 6952 |

## 3. The design

The paper has the remedy: its grid variant computes the push only between two
vertices closer than `2k`, `f_r(d) = (k²/d) · u(2k − d)`. This engine measures
distances between the rims of two bodies, so two bodies whose rims are more than
`2k` apart do not push each other. The pull to the centre then holds every part
of a graph near the others, and a group keeps the room of its neighbours only.
d3-force has the same model: a push with a largest distance and a pull to the
centre.

Not chosen: a layout of each connected part on its own, packed in rows after it,
as Graphviz does with `pack`. It places a lone vertex well, but the tree keeps
its 5775 × 6952 px, and a vertex that an edit adds to a kept layout still drifts.

## 4. Steps

### Step 1 — the push stops at 2k

- [x] `_simulate_forces!` in `source/domain/graph/FruchtermanReingoldLayout.jl`:
      two bodies whose rims are more than `2k` apart do not push each other.
      The header comment says so.
- [x] The reproduction after the change:

  | n | box | the vertex with no edge | the tree |
  | --- | --- | --- | --- |
  | 2 | 228 × 150 | (629, 615) | x 0–554, y 0–498 |
  | 11 | 228 × 150 | (58, 418) | x 0–1813, y 0–1916 |
  | 40 | 228 × 150 | (1241, 3901) | x 0–3477, y 0–4082 |
  | 40, no lone vertex | 228 × 150 | — | 3642 × 4323 |

  The map of the study of take 4 (41 items, three with no link): the ids span
  x 35–3585 and y 99–3054, so the map is about 3800 × 3700 px, from 17449 ×
  13101 before. In the window the map shows S3 at the top, with S2, E9 and E10
  in the same view.

### Step 2 — the tests

- [x] A testset in `test/domain/graph/projection/FruchtermanReingoldLayoutTest.jl`:
      a vertex with no edge lies within `2k` of the nearest box, and the drawing
      of a tree of 40 cards and one lone card covers less than 20 times the area
      of its cards. Before the change the lone card lay at least 4690 px from the tree,
      more than `2k` (410 px), and the drawing covered about 92 million px²,
      more than the bound of 28 million.
- [x] 2026-10-27: `test_graph()` 638 pass, `test_fsm()` 179, `test_process()`
      316, `test_research()` 382; no failure, no error.

### Step 3 — the guides and the map

- [x] `documentation/package/domain/graph/graph-layout.md`: the forces.
- [x] The map of the study of take 4 in the window: every box is near the
      others (a probe of the window, 2026-10-27: the dense middle holds the
      hypotheses, the evidence and their links). A map of 41 cards is about four times the width of a pane, so the
      take of the Aloha video moves across it; a zoom of the layout keeps the
      size of each box, so it can not fit the map into the pane.
