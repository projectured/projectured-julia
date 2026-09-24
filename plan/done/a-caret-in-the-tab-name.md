# A caret in the tab name

> **Status:** done. Written and implemented 2026-09-24, on the branch `feature-videos`.

`F2` puts the caret in the name of the focused tab, and typing edits the name.
But the tab bar draws no caret while you edit, so you can not see where the next
character goes. `plan/done/pane-layout.md` deferred this ("the caret in a tab
name"). The owner found it again in the feature videos (S1: `F2` names the
pane of the picture) and chose option B on 2026-09-24:

> option B

| Option | What it is |
| --- | --- |
| A | The tab bar draws the caret itself, a bar at a character of the name. |
| **B (chosen)** | The tab bar draws the name that you edit through a text view, as `WidgetText` draws a plain value. The text domain draws the caret, so it looks like every other caret, and a selection range can come later. |

## 1. What is there

- `F2` answers `make_pane_title_caret_operation`: the selection of the tree
  becomes `…tabs[i]::PaneTab.title::PrimitiveString.value{k}`. The rules of the
  pane (`_title_edit` in `PaneGestures.jl`) give each key to the title document
  and re-root its answer. The keys work; only the drawing is missing.
- `PaneToWidget.jl` gives a widget only the routing prefix of the selection
  (`_index_prefix`): the tabbed pane gets `selector_element_pairs[i]`, and the
  caret position in the name is lost.
- `WidgetTabbedPane` holds one `WidgetTabPage` for each tab, whose `selector`
  is the name as a string. The printer of the tab bar draws each name with
  `_push_text!`, a plain text with no caret.
- `WidgetText` draws a plain value through a text view
  (`_make_plain_text_view`): a `TextBlock` of one span whose caret comes from the
  selection of the widget, drawn with a `TextToGraphics` of its own. The caret is
  a `GraphicsRect` 2 pixels wide.
- A key in the name keeps its route. The tab bar routes a key to the content of
  tab `i`; the content holds no selection, so it answers nothing, and the rules of
  the pane edit the name. The text view only draws; it reads no key.

## 2. The design

1. **The pane passes the title caret whole.** When the selection of a group is a
   caret in the name of tab `i`, the group gives its tabbed pane the path
   `selector_element_pairs[i]::WidgetTabPage.selector::String{k}` in place of the
   routing prefix. The backward map answers the title caret for that path, so
   the pair of maps stays whole.
2. **The tab bar draws the edited name through a text view.** The printer of
   `WidgetTabbedPane` reads its stored selection. When it is a caret in the name
   of tab `i`, it draws that name with a text view of one span in the style of
   the tab text, with the caret at `k`, in place of the plain text. Every other
   name stays a plain text.
3. **An empty title.** The tab shows a stand-in name (the title of the content,
   or `untitled`), and `F2` puts the caret at 0. The caret stands before the
   stand-in, as it does before a hint, and the first key replaces it.

## 3. Steps

- [x] Step 1: the pane passes the title caret, and maps it back. A test in
      `PaneRenameTest.jl`: after `F2` the tabbed pane holds the caret path.
      `PaneToWidget.jl`: `_forward_selection!` takes the routing as an argument,
      and the group gives `_get_group_routing`, which keeps a live title caret
      whole. The pane passes the caret only while the group's selection is live:
      the path that a widget gets carries no live or dormant state, so a dormant
      caret would draw as a live one. A group that lost the focus therefore shows
      no caret in a name. `test_pane_rename()` passes 23.
- [x] Step 2: the tab bar draws the edited name through a text view. A test in
      `PaneRenameTest.jl`: after `F2` the tab bar draws a caret at the end of the
      name, and it moves when you type; after `Escape` it is gone.
      `WidgetToGraphics.jl`: `_find_tab_name_caret` reads the caret from the
      stored selection of the tabbed pane, and `_print_tab_name_view` draws that
      name through a `TextBlock` of one span with a `TextToGraphics` of its own,
      in the style of the selected tab. The view is made once for each tabbed
      pane and holds an empty string while no name has the caret.
      `test_pane_rename()` passes 26.
- [x] Step 3: check it in the real window, and run the tests of the pane, the
      tab strip and the widget layer.
      A probe take of the application (`build/video/probe_tabname_app.mp4`)
      shows `|untitled` after `F2` on an unnamed tab, then `Pi|` and `Pic|` while
      typing. `test_substrate` passes 80445 (the baseline and the 7 new checks),
      with the known failures at the same places; `test_application` 297,
      `test_console_backend` 83.
