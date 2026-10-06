# The theme of the panes of tasks.

"""
    TaskTheme

The sizes, the gaps and the colours of the pane of a group of tasks and of the
Tasks pane. `@theme` declares it, so `ScaledTaskTheme` holds each value times
its scale, and `TaskTheme()` is the default theme. `build_task_graphics_entry`
gives each pane its styles with `get_task_style`, from the scaled theme of the
appearance.
"""
@theme struct TaskTheme
    "The width and the height of a button of a pane of tasks: Run all, Stop, Run again."
    button_size::ControlSize = ControlSize(Point2D(0, 30))
    "The space between the stacked parts of a pane: the summary, the table and the detail."
    stack_gap::Spacing = Spacing(8)
    "The space between a heading and the badge beside it, and between the buttons of a row."
    inline_gap::Spacing = Spacing(10)
    "A result that did what was expected of it: `DONE`, `PASS`, `KEEP`."
    success_color::StyleColor = ColorRole(:success_text)
    "A result that was skipped or stopped: `SKIP`, `CANCEL`."
    info_color::StyleColor = ColorRole(:info_text)
    "A result that needs a look: `FAIL`, and an `INSERT` or an `UPDATE` that changed a store."
    warning_color::StyleColor = ColorRole(:warning_text)
    "A result that went wrong: `ERROR`."
    error_color::StyleColor = ColorRole(:error_text)
    "A task that runs."
    running_color::StyleColor = ColorRole(:accent_text)
    "A task that waits, and a value that says little."
    muted_color::StyleColor = ColorRole(:text_muted)
end
