# Fragment of `WorkflowModule` — the theme of the page of the open workflows: its
# gap. The outline and the journal take the `OutlineTheme`.

"""
    WorkflowTheme

The gap of the page of the workflows of the open files.
The outline of a workflow and its journal take the sizes and the type of the
`OutlineTheme`, as every outline does.

`@theme` declares it, so `ScaledWorkflowTheme` holds each value times its scale,
and `WorkflowTheme()` is the default theme. The builder gives the page its styles
with `get_workflow_style`, from a theme scaled or not.
"""
@theme struct WorkflowTheme
    "The gap between the line of the page of the open workflows and its table."
    gap::Spacing = Spacing(6)
end

# The role of the mark that shows `state`: the colour of a state that is under
# way, settled well, settled badly or put aside. An open state has none.
_get_state_badge_role(state::Symbol) =
    state === :active ? :accent :
    state in (:done, :chosen) ? :success :
    state in (:dropped, :rejected) ? :error :
    state === :parked ? :warning : nothing
