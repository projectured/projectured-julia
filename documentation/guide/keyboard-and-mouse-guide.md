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
| double click on a file in the Files pane | open that file |

A selection is a path into the data, so it survives a filter, a sort and a change somewhere else in the document.

Only a left click moves the selection. A right click opens the menu of the lit part, and leaves the selection where it was. See [the context menu](context-menu-guide.md) for the steps, the keys that add more menus, and the command that opens one with no pointer.

The part under the pointer is lit. In the text of a tree, such as a JSON document, the brackets around the part under the pointer are lit too: the innermost pair is orange, and each pair further out is grayer. When the view changes under a pointer that does not move, for example a list that scrolls or a popup that opens or closes, the light goes to the part that is now under the pointer. A tooltip comes once for each place where the pointer rests. It does not come again at the same place, and it does not come after a click, until the pointer moves. See [the pointer](pointer-guide.md) for more, [the tooltip](tooltip-guide.md) for the window a rest of the pointer opens, and [gestures](gestures-guide.md) for a double click, a sequence of keys and the rest of them in one place. A menu, a dropdown list, a dialog, a tooltip and a context menu each stand and close the same way; see [the popup window](popup-window-guide.md). See [drag and drop](dragging-guide.md) for how to drag a slider, a divider, a tab or a list element.

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

## Pages of a navigator

A navigator shows one part of a document at a time, its page, with Back,
Forward and Parent buttons and the address above it
([navigator.md](../package/platform/navigator/navigator.md)). These keys work on
every page, also where the page uses the same key.

| Key | What it does |
| --- | --- |
| Ctrl + Return | open the selected part as a page |
| Ctrl + [ | go back to the page before |
| Ctrl + ] | go forward to the next page |
| Ctrl + Up | go to the page that holds this page |
| the back and the forward side button of the mouse | go back, go forward |
| click on a name in the address | open that page |
| click on the arrow before a name in the address | the list of the other parts at the place of that name: type to narrow it, or a number to go to that element; Up and Down move the row, Enter or a click opens the row, Escape closes the list |
| click on **Names**, **Path** or **Types** in the bar | show the address as the next of the three views; Shift + click shows the one before |
| right click on a part of a page | **Open as a page** or **Open in a new tab** |
| double click on the number of a row of a data frame | open the row as a page: a form of its columns |

## Files

| Key | What it does |
| --- | --- |
| Ctrl + S | save the file of the focused tab |
| Ctrl + O | read that file again from disk |
| Enter on a file in the Files pane | open it |
| **Open** and **Save As** in the menu bar | a file outside the directory the Files pane lists |

## A tool in a tab

A new tab is empty. Type the name of a tool into it, and the tab becomes that tool:

| Name | The tool |
| --- | --- |
| `assistant` | a conversation with the AI assistant |
| `repl` | a read-eval-print loop: Julia code you type runs in the program |
| `explorer` | the explorer: the tree of the files of a folder |
| `log` | what the program says while it runs |
| `gestures` | the gestures of this session, and what each one did |
| `selection` | the selection of another document, as it changes |
| `reference` | a reference, taken apart into its steps |

The Insert key in an empty tab opens an insertion field instead: type the kind of document, and the tab holds a new one.

## See more of it, or less

| Key | What it does |
| --- | --- |
| Ctrl + plus, Ctrl + minus | zoom: make everything in the window larger or smaller |
| Ctrl + 0 | back to a zoom of 100% |
| Ctrl + Alt + plus, Ctrl + Alt + minus | make the text larger or smaller |
| Ctrl + Alt + 0 | back to the text size it started at |
| Ctrl + Alt + period, Ctrl + Alt + comma | make the icons larger or smaller |
| Ctrl + Alt + ], Ctrl + Alt + [ | make the space between things larger or smaller |
| Ctrl + comma | open the appearance tab |
| the chevron of a node | open or close that node |

A view that zooms by itself, such as a diagram, keeps Ctrl + plus and Ctrl + minus while the selection is in it.

The appearance tab opens with Ctrl + comma, with the palette button of the toolbar, or with View > Appearance. At its top are the zoom and six scales: text, icons, spacing, controls, corners and lines. Each has a minus, a plus and a reset button. Under them are the themes, in three groups: Editor, Tools and Documents. Click the chevron of a theme to open it. A theme shows its colors, its fonts and its sizes:

- Under each value, a line says what it draws, and the top of each theme says
  what the theme colors.
- Type the digits of a color, as `#rrggbbaa`.
- Step a size or the size of a font with the stepper at the right of its box, or with Up and Down. Step through the fonts with ‹ and ›.
- Choose a preset, if the theme has some, to change all of its values at once.

A change shows at once. Ctrl + Z in the window takes back a change of a theme; a step of the zoom or of a scale has its reset button instead. Save keeps the appearance for the next start, and Load reads the saved one back.

## The two lists

- **F1** opens the gesture help: every key that works where the selection is now, with what it does. It is a view of the same kind as the others, so it follows the selection while it is open. Help > Gestures opens it too.
- **Ctrl + Shift + P** opens the command palette: type a few letters of a command, and press Enter to run it. It finds a command that has no key of its own. Help > Command palette opens it too.

## The settings

The gear of the toolbar, or View > Settings, opens the settings of the editor in a tab: one switch or number for each setting, a button that resets it, and a line under it that says what the setting does; Reset all, Save and Load are under them. The top of each group says what the group sets. A change takes effect at once, and Ctrl+Z in the window takes it back. The palette has "Toggle partial render" and "Toggle repaint outline".
