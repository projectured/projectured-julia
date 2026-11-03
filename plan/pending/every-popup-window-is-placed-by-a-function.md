# Every popup window is placed by a function

> **Status (2026-11-03):** pending, not approved. It starts after
> [ctrl-p-finds-a-file-by-its-name.md](../done/ctrl-p-finds-a-file-by-its-name.md),
> which makes the placement function and moves the context menu window to it.
> The owner chose this order on 2026-11-03 (Q11 of that plan).

## The goal

Every popup window of the editor stands where a placement function puts it, and
no popup has its own code for its place. Then one way of placement exists, and
the old code goes away.

## What changes

The first plan moves the context menu window. The other popups place their
windows with their own code now
([popup-window.md](../../documentation/package/platform/screen/popup-window.md)):

| Popup | Its place now | Its placement |
| --- | --- | --- |
| Tooltip | `TooltipWindowProjection` adds `offset` to the point, else below the part | beside the point, else below the part |
| Submenu of a menu item | `OpenPopupOperation` in the frame of the item; each reader on the way up moves the position (`map_operation_position`) | beside the item |
| List of a `WidgetSelect` | the same as a submenu | below the select |
| `WidgetDialog` | the backend chooses (`x = -1`), with a fixed size | in the center of the window of the part |

A submenu and the list of a select then name their part by a reference, and the
placement reads the box of the part, as the context menu does. So the position
that each reader moves on the way up is no longer needed for a popup.

## The steps

1. **The tooltip.** Its two places become placements. Test: `test_tooltip()`
   passes, and a tooltip near the right edge of the screen stays on the screen.
2. **The submenu and the list of a select.** Each opens with a placement that
   names its part. Tests: the menu and select tests of the widget slice, and the
   keys of a menu.
3. **The dialog.** It opens in the center of the window of its part. Test:
   `test_file_dialog()`.
4. **The old code goes.** `OpenPopupOperation` and its move by each reader go
   when no popup uses them, and `find_part_place` goes when no wrapper calls it.
   The documents `popup-window.md` and `screen.md` describe one way of
   placement. The naming guard and the layering guards of the slices that
   changed.

## Questions before it starts

The design of each step is open until the owner answers its questions, one at a
time, after the first plan lands.
