# Fragment of `GestureHelpModule`.
#
# The decorator that opens the **command palette** over a content pipeline.
#
# **Printer** — the inner output, as it is.
#
# **Reader** — the inner reader comes first, and the palette gesture is read only
# when it declines. The gesture answers the open of a list that a person types
# into (`WidgetChoiceList`), in the context menu window: a popup window of its own
# at the top center of the window, below its bands. The list takes the keys while
# it is open, and a key that it does not answer goes on to the window under it.
#
# **Which commands it lists.** The decorator asks the inner reader with
# `CollectIntents`, the route that a keystroke takes, so a row can come from any
# stage of the chain, and its operation is rooted back through every stage above,
# at the input of this decorator. A row whose operation is `nothing` can not run
# now, and the list leaves it out; F1 lists it. The choice of a row is an edit of
# the part that the list belongs to, the input of this decorator, so the context
# menu window lifts its operation from there through the readers above, as if the
# key of the binding fired.
"""
    COMMAND_PALETTE_GESTURE

The gesture that summons the palette: Ctrl+Shift+P. F1 already opens the help
window, which is the palette's read-only twin.
"""
const COMMAND_PALETTE_GESTURE = KeyDownPattern(:p; modifiers = [:ctrl, :shift])

"""
    is_command_palette_gesture(event) -> Bool

True when `event` is the gesture that summons the palette.
"""
is_command_palette_gesture(event) = matches_gesture_pattern(COMMAND_PALETTE_GESTURE, event)

"""
    ToggleCommandPaletteOperation()

Open the palette: what the palette gesture does, for a command that has no key.
The command sends it with a route into the content of the decorator, as
`read_rooted_operation` sends an operation, and the decorator finds it in the
answer of its inner reader. It names no place, so it travels up a chain as it is.
An open palette closes on Escape, as every popup does.
"""
struct ToggleCommandPaletteOperation <: Operation end

OperationModule.is_self_contained_operation(::ToggleCommandPaletteOperation) = true
OperationModule.describe_operation(::ToggleCommandPaletteOperation) = "open the command palette"

"""
    CommandPaletteDecoratorProjection(; inner)

Decorator over `inner`, a content pipeline. The palette gesture opens a list that
a person types into, of the commands that work where the selection is, at the top
center of the window. Typing narrows the list by the letters in order
(`find_letter_matches`), Return runs the chosen command and Escape closes the
list. The list opens in the context menu window, so the editor needs the
`context_menu` wrapper, which `build_editor` has by default.
"""
struct CommandPaletteDecoratorProjection <: Projection
    inner::Any
end

CommandPaletteDecoratorProjection(; inner) = CommandPaletteDecoratorProjection(inner)

@iomap struct CommandPaletteDecoratorIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer ────────────────────────────────────────────────────────────────

function print_document(p::CommandPaletteDecoratorProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    CommandPaletteDecoratorIoMap(p, input, Cell(@computation inner_iomap.output), inner_iomap)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::CommandPaletteDecoratorProjection, recursion, change::Intent,
                     iomap::CommandPaletteDecoratorIoMap)
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    # A command that asks for the palette comes up from the content as an answer.
    child.operation isa ToggleCommandPaletteOperation &&
        return Intent(change.gesture, _open_command_palette(p, recursion, iomap))
    child.operation isa Operation && return child
    change.route === nothing && is_command_palette_gesture(change.gesture) &&
        return Intent(change.gesture, _open_command_palette(p, recursion, iomap))
    return child
end

read_intent(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

"""
    make_command_palette_list(rows) -> WidgetChoiceList

The list of the palette over `rows`, the `GestureRow`s of the commands that work
where the selection is: each row that can run, as a choice with its description
and its key, matched by the letters in order over its description and its
domain, the description first. The choice of a row answers its operation.
"""
function make_command_palette_list(rows)
    runnable = GestureRow[row for row in rows if row.operation !== nothing]
    # The domain comes first in the text that a query matches, so a letter in the
    # description, the name part, counts more.
    texts = String[string(row.domain, " ", row.description) for row in runnable]
    starts = Dict(text => length(row.domain) + 2 for (text, row) in zip(texts, runnable))
    WidgetChoiceList(; prompt = "Command", placeholder = "type a command",
                     empty = "No command works here", fills_offer = true,
                     find = query -> WidgetChoice[_make_command_choice(runnable[index])
                                                  for index in find_letter_matches(query, texts;
                                                                                   name_start = text -> starts[text])],
                     choose = row -> row.operation)
end

_make_command_choice(row::GestureRow) =
    WidgetChoice(row.description; value = row, note = isempty(row.gesture) ? nothing : row.gesture)

# The open of the list of the commands that work here, at the top center of the
# window, below its bands. The rows come from the reader, asked where a keystroke
# would go.
function _open_command_palette(p::CommandPaletteDecoratorProjection, recursion,
                               iomap::CommandPaletteDecoratorIoMap)
    answer = read_intent(p.inner, recursion, Intent(CollectIntents()), iomap.inner_iomap)
    rows = collect_gesture_rows(answer isa Intent ? answer.operation : answer)
    make_choice_list_operation("Commands", make_command_palette_list(rows);
                               placement = make_shell_top_placement)
end

# ── Reference mapping ──────────────────────────────────────────────────────

map_reference_forward(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

"""
    command_palette = true

The wrapper of `build_editor` that makes Ctrl+Shift+P open the list of the
commands that work here, in a popup window at the top center of the window:
typing narrows the commands, Return runs the chosen one and Escape closes the
list. It is off by default. It acts around the help of F1.
"""
function wrap_editor!(::Val{:command_palette}, layer::Symbol, argument, parts::EditorParts)
    parts.projection = CommandPaletteDecoratorProjection(; inner = parts.projection)
    parts
end

get_wrapper_layers(::Val{:command_palette}) = (:container => 50,)
