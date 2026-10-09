# Fragment of `WorkflowModule` — the theme of the outline of a workflow: the texts
# of a question and of the parts of an entry, and the gaps.

"""
    WorkflowTheme

The fonts, the colors and the gaps of the outline of a workflow: the question of
a decision, and the time, the author and the kind of an entry. The state of a
node is a badge, which takes the colours of its role from the widget theme.

`@theme` declares it, so `ScaledWorkflowTheme` holds each value times its scale,
and `WorkflowTheme()` is the default theme. The builder gives each projection of
the outline its styles with `get_workflow_style`, from a theme scaled or not.
"""
@theme struct WorkflowTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The mark of a decision before its question."
    question_text::ThemeText = TextRole(:heading; weight = 700)
    "The time and the kind of an entry, the date of the last entry of a node, and the word before a reason."
    muted_text::ThemeText = TextRole(:text_muted)
    "The author of an entry that the assistant wrote."
    assistant_text::ThemeText = TextRole(:info_text; weight = 700)
    "The author of an entry that the person wrote."
    person_text::ThemeText = TextRole(:text; weight = 700)
    "The vertical gap between the parts of a node."
    gap::Int = 6
end

# The role of the badge that shows `state`: the colour of a state that is under
# way, settled well, settled badly or put aside; an open state has none.
_get_state_badge_role(state::Symbol) =
    state === :active ? :accent :
    state in (:done, :chosen) ? :success :
    state in (:dropped, :rejected) ? :error :
    state === :parked ? :warning : nothing
