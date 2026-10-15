# Work plan

> **Kind:** design · **Status:** current · **Stands on:** [tree.md](../tree/tree.md), [roster.md](../roster/roster.md), [widget.md](../widget/widget.md), [natural.md](../natural/natural.md)

The work plan slice of `ProjecturedPlatform` holds the plan of an agent as documents, with more states than "done" and "not done", and shows its progress and its steps. This document says what a plan and a step hold, why blocked is a relation and not a status, why a step holds a link to its plan, how the progress counts, and what the views show.

## How it works

### The documents

`WorkPlanStep(id, title; …)` is one step of a plan.

| Field | Meaning |
| --- | --- |
| `id` | the name of the step in its plan, which `blocked_by` of another step names |
| `title`, `description` | what the step does, in few and in more words |
| `active_title` | what a view shows while the step runs, such as "Writing the tests"; empty when the step gives none |
| `status` | one of the five statuses below |
| `priority` | `:high`, `:medium` or `:low` |
| `reason` | why the step has its status, such as why it was skipped |
| `blocked_by` | the ids of the steps of the same plan that this step waits for |
| `children` | the steps under this step, a `CellVector` of `WorkPlanStep` |
| `plan` | the link to the plan that holds the step; see below |

`WorkPlan(id; title, steps, text, uri)` is the plan. It has **one of three contents**, as the content of a plan of the Agent Client Protocol: its `steps`, a Markdown `text`, or the `uri` of a file that holds the plan. An empty content is none.

A plan is read only. No view of it takes an edit, because the next update of the agent replaces the plan.

### The statuses

`WORK_PLAN_STEP_STATUSES` is `:pending`, `:in_progress`, `:completed`, `:skipped` and `:deferred`. A step with another status, or another priority, is an `ArgumentError`.

**Blocked is no status.** A step is blocked when it is `:pending` and one of the ids in its `blocked_by` names a step of its plan, at any depth, that is not `:completed`. `is_work_plan_step_blocked(plan, step)` answers it. An id that names no step of the plan blocks nothing. A blocked step follows its blockers: it is free when the last of them completes, and nobody writes its state.

An agent gives no `:skipped` and no `:deferred` step now. The statuses are in the document for a reader of a plan that says so, such as a Markdown plan.

### A step holds a link to its plan

Blocked is a relation between the steps of one plan. The label, the icon, the facet and the page of a step get only the step: `format_tree_node_label(step)`, `compute_item_facet(step, …)`, and the page of a navigator. A document does not know its parent, because a document can sit in two places. So a plan gives its own steps a link, and only the plan sets it.

`WorkPlanStep.plan` holds the private `_WorkPlanLink` of its plan, or `nothing`. The plan keeps the same holder in its field `link`. The holder holds the plan and the `DocumentTree` of its steps. `is_walk_opaque` holds for it, so a walk of the documents does not go from a step into its plan, and a search finds each step once.

- The constructor `WorkPlan(…)` and `set_work_plan_steps!(plan, steps)` link every step at every depth. **Write the steps of a plan only through `set_work_plan_steps!`.**
- A step with no plan is never blocked. Its page shows the ids that it waits for with no link.
- A file keeps the id, the title and the content, and no link (`pred_arguments`). The constructors make the links again when the file is read.
- A copy of a plan has a link of its own, and its copied steps link to the copy. A step that a person copies alone belongs to no plan.

### The progress

`compute_work_plan_progress(plan)` counts the steps at every depth and answers a `WorkPlanProgress(total, pending, in_progress, completed, skipped, deferred, blocked)`. `pending` counts the blocked steps too, and `blocked` counts them again apart.

`describe_work_plan_progress(plan)` writes the counts. It always says how many of all the steps are completed, then each other count that is not zero: in progress, pending and not blocked, blocked, skipped, deferred. A plan with no steps says "no steps".

```julia
plan = WorkPlan("tasks"; title = "Release", steps = [
    WorkPlanStep("1", "Write the tests"; status = :completed),
    WorkPlanStep("2", "Fix the bug"; active_title = "Fixing the bug", status = :in_progress),
    WorkPlanStep("3", "Update the guide"; blocked_by = ["2"]),
    WorkPlanStep("4", "Port to Windows"; status = :deferred, reason = "no Windows machine")])

describe_work_plan_progress(plan)    # "1 of 4 completed, 1 in progress, 1 blocked, 1 deferred"
is_work_plan_step_blocked(plan, plan.steps[3])   # true; false after step 2 completes
```

### The views

`WorkPlanToWidget` prints a plan by its content: its steps, else its text, else its file. A plan with none shows its steps, which say "no steps".

- **A plan of steps** shows a line of its progress, a bar filled to the share of the completed steps, and the tree of its steps. The tree is a `DocumentTree` titled "Steps", whose root is the plan. The link of the plan keeps it, so its open nodes stay when the plan draws again.
- **A plan with a text** shows the text as prose, through `make_prose_document` of the natural slice.
- **A plan with a file** shows a button with the path. A press answers `OpenFileOperation(path)`. A prefix `file://` of the `uri` is dropped, and nothing else of a URI is read.

The path `steps[i]…` of the plan is the path `children[3].child.root.steps[i]…` of the view. A part that the view builds after the print takes its paths from the layout. The tree document takes its part and no more, because its root is the plan.

**The node of a step.** The label is the active title while the step is in progress and has one, else the title, then " · " and the status, or "blocked by step 2, 3" with the blockers that are not completed. The label of a plan is its title, else "Plan", then " · " and its progress.

| Node | Icon |
| --- | --- |
| a plan | `:list` |
| pending | `:circle` |
| in progress | `:loader` |
| completed | `:circle_check` |
| skipped | `:skip_forward` |
| deferred | `:circle_pause` |
| blocked | `:stop` |

**The page of a step.** `WorkPlanStepToWidget` shows its title, its state and its priority, the active title, its description, its reason and the steps that it waits for. A line whose fact is empty does not show. Each blocker is a button that answers `OpenPageOperation(plan, steps[i]…)`, with the plan of the step and the path of the blocker in it. A navigator whose content is the plan, or that has the plan on the address of its page, opens it as a visit, and Back returns. An id that names no step, and a step with no plan, show the id with no link.

### The facet

A roster of steps has one facet, `blocked`. `status` and `title` are fields of `WorkPlanStep`, and a facet with the name of a field of its own type is an `ArgumentError`, so a key `status` reads the field.

```julia
Roster(CollectionItems(plan.steps); columns = ["title", "status", "blocked"])
```

### Who makes a plan

The assistant makes the plans of an agent: `apply_agent_event!` writes an `AgentPlanUpdate` into a `WorkPlan` with the id of the update. A step keeps its document from one update to the next by its id, and the assistant writes only the fields that changed, so a view keeps its open steps ([assistant.md](../assistant/assistant.md)).

## How it fits

The slice uses the collection, layout, natural, projection, roster, serialization, style, tree and widget slices of the platform. It loads after `systemprocess` and before `assistant`. It names no agent: the assistant slice fills it from the events of the kernel.

## Design decisions

- **Blocked is a relation.** It follows the status of the blocker, so nobody writes it and it can not go stale.
- **The plan sets the link.** Each view of a step needs its plan to answer "blocked". The link is the least data that gives it, and it stays out of the walk and out of the file.
- **Skipped and deferred are in the document.** The Markdown plans of a repository say which steps a person skipped or deferred. A later reader of them fills the two statuses, and the kernel and the protocol carry no such status.
- **A plan is not edited.** The agent owns it.

The plan with the steps and the alternatives is [the-assistant-shows-the-work-of-its-agent.md](../../../../plan/pending/the-assistant-shows-the-work-of-its-agent.md).

## Limits

- **No agent gives `:skipped` or `:deferred` now.** Only a step that a program builds has them.
- **A copy that converts the kind of the cells keeps the link of the original.** `copy_document(K, plan)` makes no link of its own. No test covers it.
- **A blocker names a step of the same plan.** A step can not wait for a step of another plan.
- **A plan of a text or a file has no progress.** Only the steps are counted.
- **The column `plan` of the assistant list shows the first plan that has steps.**

## Layer structure

The slice is the folder [source/platform/workplan/](../../../../source/platform/workplan/), and `WorkPlanModule` is its module.

```
workplan/WorkPlanModule.jl       (WorkPlanModule): the module, its exports and its include order
    ├─ WorkPlanDocument.jl       : WorkPlanStep, WorkPlan, the link, the nodes of a tree, the facet
    ├─ WorkPlanProgress.jl       : the blocked steps, the progress, the words for it
    ├─ WorkPlanToWidget.jl       : the view of a plan
    └─ WorkPlanStepToWidget.jl   : the page of a step
```

## Tests

`test_work_plan()` in `ProjecturedPlatformTest`, in `test/platform/workplan/WorkPlanTest.jl`:

- the progress counts the steps at every depth, and the words of the progress;
- a blocked step is free when its blocker completes;
- the three contents of a plan;
- a file keeps the plan, and a copy links its steps to the copy;
- in a real `Editor`, the tree of the steps follows a status, and a double click opens a step;
- a link on the page of a step opens the step that it waits for;
- a roster of the steps has the facet `blocked`.
