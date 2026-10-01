# The popup window

> **Kind:** procedure · **Status:** current · **Stands on:** [keyboard-and-mouse-guide.md](keyboard-and-mouse-guide.md)

A menu, the list of a dropdown field, a dialog, a tooltip and a context menu
each open in a small window of their own, not in a layer drawn over the window
you are looking at.

## It is a real window

Such a window behaves like any other window of the program: it has its own
place on the screen, and another program's window can cover it or sit behind
it. It is only as large as what it needs to show, up to a limit, so a
one-word tooltip is small and a long menu grows taller to fit its items.

## Where it stands

- A menu that a right click opens stands at the pointer.
- The list of a dropdown field opens below the field.
- A tooltip stands beside the part it describes.
- When nothing you clicked placed the window, such as a context menu or a
  tooltip that a command opened, it stands below the part instead, so it does
  not cover it.

## How it closes

- A menu, the list of a dropdown field, and a context menu close on Escape and
  on a click outside them, in the window under them or in another window.
- A tooltip closes when you move the pointer off the part it describes, and
  also on Escape, a click or a scroll. See [the tooltip](tooltip-guide.md).
- A dialog stays open until you click one of its buttons or click outside its
  card. While it is open, no other window of the program
  takes a click or a key.

See [the tooltip](tooltip-guide.md) and [the context menu](context-menu-guide.md)
for the two windows with keys of their own, and
[the keyboard and the mouse](keyboard-and-mouse-guide.md) for the full list of
keys.
