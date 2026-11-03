# Fragment of `WidgetModule` — the placement of a window at the top of what the
# shell of a window holds, below its bands.

"""
    make_shell_top_placement(reference; width_share = 0.5, minimum_width = 480,
                             maximum_height = 480, gap = 8) -> Function

The placement at the top center of what the `WidgetShell` of the window of the
part at `reference` holds, a reference from the screen: below the menu bar and
the toolbar of the window, `width_share` of the width of that content wide and at
least `minimum_width`, and as high as the content of the window up to
`maximum_height`, as `make_part_top_placement` places at a part. A window with no
shell places at the part itself.

Use it as the `placement` of a list that belongs to the whole window, such as the
command palette and the search of a file by its name; it takes the reference of
the part that opens the list.
"""
function make_shell_top_placement(reference; keywords...)
    context -> begin
        content = _find_window_shell_content(context.screen, reference)
        make_part_top_placement(something(content, reference); keywords...)(context)
    end
end

# How many documents down the content of a window the search for its shell goes:
# the wrappers of a window, such as the clipboard and the focus cycle, and the
# shell.
const _SHELL_SEARCH_DEPTH = 6

# The reference of the content of the shell of the window that `reference`, a
# reference from `screen`, starts in, or `nothing` when that window holds no shell.
function _find_window_shell_content(screen, reference)
    screen isa ScreenDocument && reference isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    (length(steps) >= 2 && steps[1] == FieldReferenceStep("windows")) || return nothing
    window = try_evaluate_reference(screen, extend_reference(EmptyReference(), steps[1], steps[2]), nothing)
    window isa WindowDocument || return nothing
    found = search_references(window.content, document -> document isa WidgetShell;
                              maxdepth = _SHELL_SEARCH_DEPTH, descend = _is_shell_search_step, limit = 1)
    isempty(found) && return nothing
    extend_reference(EmptyReference(), steps[1], steps[2], FieldReferenceStep("content"),
                     get_reference_steps(strip_reference_types(first(found)))...,
                     FieldReferenceStep("content"))
end

# The search for a shell enters a document that a field holds, and no collection,
# so it reads no lazy part of a window.
_is_shell_search_step(_, child) = child isa Document && !is_element_collection(child)
