# Drag and drop

> **Kind:** procedure · **Status:** current · **Stands on:** [pointer-guide.md](pointer-guide.md)

How to drag a slider, a divider, a tab and a list element, what a chart does
when you drag inside it, and how to stop a drag with no change.

## A slider

1. Press the thumb of the slider and move the pointer.
2. The thumb follows the pointer, even past either end of the slider: move far
   enough left or right, and the value stops at its lowest or its highest.
3. Release the button where you want the value. You can release over another
   part of the window; the value still sets where you dropped the pointer.

Press Escape before you release, and the slider goes back to the value it had
before the press.

## A divider between two panes

1. Press the thin line between two panes. The pointer turns into a resize
   cursor over it.
2. Move the pointer to make one pane larger and the other smaller.
3. Release the button to keep the new sizes.

Press Escape before you release, and both panes go back to the size they had
before the press.

## A chart

- **Drag inside the plot** to draw a rectangle. Release it, and the chart zooms
  to that rectangle. A rectangle too small to be a real drag does nothing, so
  an ordinary click does not zoom.
- **Hold Shift and drag** to pan the chart instead: the data moves under the
  pointer, and the window you see moves with it.

Press Escape before you release, and the chart goes back to the view it had
before the drag. A pan that Escape stops goes back the same way.

## A tab

- **Click a tab** with no movement to select it, exactly as a click on anything
  else does.
- **Press a tab and move the pointer** a few pixels to start a drag. A
  rectangle shows where the tab would land: over another group of tabs, it
  covers that whole group; near the edge of a window or a group, it covers
  half of it, for a new group beside it.
- **Release the button** to drop the tab where the rectangle shows. The tab
  moves into that group, or into a new group that the drop makes.

Press Escape before you release, and the tab stays where it was, with no
rectangle and no move.

## A list that offers it

Some lists let you drag one of their elements to another place in the same
list. Press the element, move the pointer to where you want it, and release.
The element moves to the place under the pointer. Press Escape before you
release to leave the list as it was.

## While you drag

The part under the pointer lights during a drag the same way it does
otherwise. Drag a slider's thumb over a button elsewhere in the window, and the
button lights, exactly as it would if you moved the pointer there with no
drag on at all.

See [the pointer](pointer-guide.md) for the light that marks the part under
it, and [the keyboard and the mouse](keyboard-and-mouse-guide.md) for the full
list of keys and clicks.
