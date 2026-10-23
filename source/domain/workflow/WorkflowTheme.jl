# Fragment of `WorkflowModule` — the theme of the catalog of workflows: its quiet
# texts and its gaps. The outline and the journal take the `OutlineTheme`.

"""
    WorkflowTheme

The font, the quiet text and the gap of the catalog of the workflows of a folder.
The outline of a workflow and its journal take the sizes and the type of the
`OutlineTheme`, as every outline does.

`@theme` declares it, so `ScaledWorkflowTheme` holds each value times its scale,
and `WorkflowTheme()` is the default theme. The builder gives the catalog its
styles with `get_workflow_style`, from a theme scaled or not.
"""
@theme struct WorkflowTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The time of the last entry and the name of the file of a workflow in the catalog."
    muted_text::ThemeText = TextRole(:text_muted)
    "The gap between the bar of the catalog and its table."
    gap::Spacing = Spacing(6)
end

# The role of the mark that shows `state`: the colour of a state that is under
# way, settled well, settled badly or put aside. An open state has none.
_get_state_badge_role(state::Symbol) =
    state === :active ? :accent :
    state in (:done, :chosen) ? :success :
    state in (:dropped, :rejected) ? :error :
    state === :parked ? :warning : nothing
