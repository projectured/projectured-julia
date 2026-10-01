# The keyboard and the mouse

> **Kind:** procedure · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md)

The keys and the clicks that work everywhere, and the two ways to see the rest: F1 lists what works where the selection is now, and Ctrl+Shift+P runs a command by its name.

## Where the keys come from

A key press goes to the view under the selection, and each view says which keys it takes. So the list below is what holds in most views, and a domain adds its own. **F1 is the true list**: it shows the keys that work where the selection is at that moment, in that view.

## Move and select

| Key | What it does |
| --- | --- |
| arrow keys | move the selection by one position |
| Ctrl + Home, Ctrl + End | the first and the last position of the document |
| Alt + arrow keys | move the selection over whole parts, not positions |
| Alt + click | select the part under the pointer as a whole |
| right click | open the menu of the part under the pointer, at the pointer; the selection stays where it was |
| F2, while a menu is open | add the menu of the part around it |
| Shift + F2, while a menu is open | show one menu fewer |
| rest the pointer | a tooltip says what the thing under it is |
| click | put the selection where you click |
| double click on a file in the navigator | open that file |

A selection is a path into the data, so it survives a filter, a sort and a change somewhere else in the document.

Only a left click moves the selection. A right click opens the menu of the lit part, and leaves the selection where it was. See [the context menu](context-menu-guide.md) for the steps, the keys that add more menus, and the command that opens one with no pointer.

The part under the pointer is lit. In the text of a tree, such as a JSON document, the brackets around the part under the pointer are lit too: the innermost pair is orange, and each pair further out is grayer. When the view changes under a pointer that does not move, for example a list that scrolls or a popup that opens or closes, the light goes to the part that is now under the pointer. A tooltip comes once for each place where the pointer rests. It does not come again at the same place, and it does not come after a click, until the pointer moves. See [the pointer](pointer-guide.md) for more, [the tooltip](tooltip-guide.md) for the window a rest of the pointer opens, and [gestures](gestures-guide.md) for a double click, a sequence of keys and the rest of them in one place. A menu, a dropdown list, a dialog, a tooltip and a context menu each stand and close the same way; see [the popup window](popup-window-guide.md).

## Change

| Key | What it does |
| --- | --- |
| a character key | type into the selected string, number or name |
| Backspace, Delete | remove the character before or after the caret |
| Ctrl + Delete | remove the selected part |
| Insert | insert a new element beside the selected one |
| Enter | finish the part you are typing |
| Escape | leave what you are typing, or close the window |
| Ctrl + Z | take the last change back |
| Ctrl + Y, Ctrl + Shift + Z | put it back |

Which of these a domain takes is the domain's own decision, and F1 says so. `Ctrl + Z` works where a program installs a history; the application installs one around each file and one around the window.

## The clipboard

| Key | What it does |
| --- | --- |
| Ctrl + C | copy the selected part |
| Ctrl + X | cut it |
| Ctrl + N | note it: keep it for a later paste, without changing the document |
| Ctrl + V | paste |
| Ctrl + Shift + V | paste a copy |

The clipboard holds a part of the data, not text, so a paste puts a structure back. Where a text conversion exists, the system clipboard carries the text of it.

## Tabs and panes

| Key | What it does |
| --- | --- |
| Ctrl + T | a new tab |
| Ctrl + W | close the focused tab |
| Ctrl + Shift + D | duplicate the focused tab |
| Ctrl + Page Down, Ctrl + Page Up | the next or the previous tab |
| Ctrl + Tab, Ctrl + Shift + Tab | the next or the previous group of tabs |
| F2 | put the caret in the name of the tab, Escape leaves it; while a tooltip or a menu is open, F2 goes to it |

## Files

| Key | What it does |
| --- | --- |
| Ctrl + S | save the file of the focused tab |
| Ctrl + O | read that file again from disk |
| Enter on a file in the navigator | open it |
| **Open** and **Save As** in the menu bar | a file outside the directory the navigator lists |

## A tool in a tab

A new tab is empty. Type the name of a tool into it, and the tab becomes that tool:

| Name | The tool |
| --- | --- |
| `assistant` | a conversation with the AI assistant |
| `repl` | a read-eval-print loop: Julia code you type runs in the program |
| `explorer` | the file navigator |
| `log` | what the program says while it runs |
| `gestures` | the gestures of this session, and what each one did |
| `selection` | the selection of another document, as it changes |
| `reference` | a reference, taken apart into its steps |

The Insert key in an empty tab opens an insertion field instead: type the kind of document, and the tab holds a new one.

## See more of it, or less

| Key | What it does |
| --- | --- |
| Ctrl + plus, Ctrl + minus | make the text larger or smaller |
| Ctrl + 0 | back to the size it started at |
| the chevron of a node | open or close that node |

## The two lists

- **F1** opens the gesture help: every key that works where the selection is now, with what it does. It is a view of the same kind as the others, so it follows the selection while it is open.
- **Ctrl + Shift + P** opens the command palette: type a few letters of a command, and press Enter to run it. It finds a command that has no key of its own.
