# The work plan example: the plan of an agent with a step of every status, a step
# that waits for another one, and steps under a step, drawn with the view of a
# plan: its progress, and the tree of its steps.

function make_work_plan_document_example()
    WorkPlan("tasks"; title = "Fix the parser", steps = [
        WorkPlanStep("1", "Read the failing test"; status = :completed),
        WorkPlanStep("2", "Fix the parser"; status = :in_progress,
                     active_title = "Fixing the parser", priority = :high, children = [
            WorkPlanStep("2a", "Find the token that breaks the parse";
                         status = :completed),
            WorkPlanStep("2b", "Write the new rule"; status = :in_progress,
                         active_title = "Writing the new rule"),
            WorkPlanStep("2c", "Remove the old rule")]),
        WorkPlanStep("3", "Run the parser tests"; blocked_by = ["2"],
                     description = "The tests of the parser and of the editor."),
        WorkPlanStep("4", "Update the grammar notes"; status = :skipped, priority = :low,
                     reason = "The grammar did not change."),
        WorkPlanStep("5", "Measure the parse time"; status = :deferred, priority = :low,
                     reason = "The benchmark machine is busy.")])
end

# The step that waits for step 2, with its plan, for the catalog: its page shows
# its blocker as a link.
make_work_plan_step_document_example() = make_work_plan_document_example().steps[3]
