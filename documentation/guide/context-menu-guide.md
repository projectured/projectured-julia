# The context menu

> **Kind:** procedure · **Status:** current · **Stands on:** [pointer-guide.md](pointer-guide.md)

The menu that a right click opens on the part under the pointer, how to see
the menus of the parts around it, and the command that opens one with no
pointer.

## Open it

1. Move the pointer over the part. The part lights.
2. Click the right button. The menu of the nearest part that has one opens at
   the pointer.
3. Click an item to run it, or press Escape to close the menu.

The selection does not move. Each item of the menu acts on the part under the
pointer, not on what was selected before the click.

## See the menus of the parts around it

While the menu is open:

- Press F2 to add the menu of the part around it. The added menu starts with a
  line that names its part.
- Press Shift+F2 to go back to one fewer.
- When the window itself has a menu, it is the last one F2 reaches, after every
  part around the one you clicked.

## Open it with no pointer

1. Select a part that has a menu.
2. Open the command palette (Ctrl+Shift+P) and type "Show the context menu".
3. Press Enter. The menu opens below the part.

This only runs where the selected part has a menu; elsewhere the command does
nothing.

See [the pointer](pointer-guide.md) for the light that marks the part under it,
and [the keyboard and the mouse](keyboard-and-mouse-guide.md) for the full list
of keys.
