# The pointer

> **Kind:** procedure · **Status:** current · **Stands on:** [keyboard-and-mouse-guide.md](keyboard-and-mouse-guide.md)

What the program shows where the pointer sits: the shape it takes, the part that lights, the brackets of a tree that light around it, and the tooltip that a rest brings.

This holds in every window the program opens, not only the main one. A popup, a menu and a dialog light their own parts the same way.

## The pointer takes the shape of what a press does

Move the pointer over a part of the program. Its shape says what a press there does:

- A double arrow over the edge of a column of a table, and over the divider of a split pane. A press there drags the width or the size.
- An I-beam over text you edit: a text field, a text area or a text document. A press there puts the caret.
- A pointing hand over a button and over a tab. A press there runs the action, or opens the tab.
- An open hand over a tab of a pane that lets you drag its tabs.
- The arrow everywhere else.

During a drag, the pointer keeps the shape of the drag wherever it goes, also over other parts and outside the window, until you release the button or press Escape:

- The double arrow while you drag the edge of a column or a divider.
- The arrow while you drag a slider or a chart.
- While you drag a tab: a closed hand where a group takes the tab, and a crossed circle where no group takes it.

## The part under the pointer lights

Move the pointer over a button, a menu item, or a row of a list, a table or a tree. The part lights while the pointer is on it or on a part inside it. Move the pointer away, and the light goes with it.

The light only shows where the pointer is. It never changes the size or the place of a part, and it does not select anything: a click still does that.

## The brackets of a tree light too

In the text of a JSON document, or of another tree, move the pointer onto a value. The brackets that hold it light as well: the pair closest to the value is the brightest, and each pair further out is a little grayer, until a bracket far enough from the pointer keeps its usual gray.

Try it on the document `[1, [2, 3]]`:

1. Move the pointer onto the `2`. The brackets of `[2, 3]` light bright.
2. Look at the brackets of the outer array. They light too, a shade between bright and the usual gray.
3. Move the pointer onto the `1`. The brackets of the outer array light bright instead, and the brackets of `[2, 3]` go back to their usual gray.

## The light follows what is under the pointer

The light shows the part under the pointer, not only the place the pointer last moved to. When a list scrolls under a pointer that stays still, or when a window opens or closes there, the light moves on its own to the part that the pointer now sits on.

## Rest the pointer to see a tooltip

1. Stop the pointer over a part.
2. Wait about half a second. A small window opens near the part and says what it is.
3. Move the pointer off the part. The window closes.

A tooltip comes once for each place where the pointer rests. It does not come again at the same place, and it does not come after a click, until the pointer moves to a new place. Escape, a click and a scroll also close the window.

## The right button opens the menu of the lit part

A right click opens the menu of the part that is lit, at the pointer. The part does not have to be selected first: the left click still does that, and the right click leaves the selection where it was.

See [the keyboard and the mouse](keyboard-and-mouse-guide.md#move-and-select) for the full steps, including F2 and Shift+F2 for a menu with more than one part in it, and for the command palette, which can open the same menu with no pointer at all.
