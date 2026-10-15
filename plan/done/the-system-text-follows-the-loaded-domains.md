# The system text follows the loaded domains

Status: done 2026-10-15, from the answer of the owner on that day. It
spans projectured-julia (the registry and the system text) and omnet-julia (the
IDE).

## 1. The ask

The assistant of the OMNeT++ IDE could not make a graph of vertices and edges.
The owner asked why, and then "yes, both" to the two fixes below. The second
half of the answer reads as the graph and JSON, both loaded in the IDE (my
reading; the owner can say otherwise).

## 2. The facts (2026-10-15)

- `ProjecturedGraph` is not in the dependency closure of `OmnetIde`, nor is
  `ProjecturedJSON`. So the graph domain never registers its names or its row of
  the renderer in the IDE, and `parse_natural_text(:json, …)` has no parser there.
- `EDITOR_SYSTEM`, one constant for every window, named `GraphGraph` and a JSON
  example all the same.
- The tests of the IDE ran in one process with every projectured-julia test
  package, which loads both domains, so they passed where the IDE fails.

## 3. The steps

- [x] 1. A domain registers one sentence with its names
  (`register_assistant_api!(declaration; description)`), and
  `describe_registered_assistant_api()` joins the sentences of the loaded
  domains. `make_domain_system()` puts them in the system text of every window
  after `EDITOR_SYSTEM`, which names only the verbs of the platform. The chart, the
  graph, the formula, the DataFrames adapter, the workflow and JSON register their
  sentences.
- [x] 2. `OmnetIde` depends on `ProjecturedGraph` and `ProjecturedJSON`, and its
  closure guard says why and counts 24.
- [x] 3. The tests: the registry keeps a sentence once; the documentation test
  checks the names of the domain paragraph; the prompt test of the IDE checks the
  whole text of each window; the IDE draws a graph and parses a JSON value through
  `execute_julia_code`; and the IDE tests run once in a process that loads only
  `OmnetIdeTest`, so a domain that the IDE does not load shows.

## What was found on the way

- The process that loads only `OmnetIdeTest` loads the graph and JSON domains now,
  through the closure of `OmnetIde`, and not `ProjecturedTest`; its prompt,
  documentation and verb tests pass there.
- The export guard (`test_exports`) failed on main since the landing of the plan
  `the-assistant-uses-the-whole-editor`: the exports of `ApplicationModule` and
  `NavigatorModule` were not in the order of their definitions. Both follow it now.

## Not in this plan

A sentence for a domain that registers neither names nor a format, such as NED
and INI, whose files the study verbs write as text.
