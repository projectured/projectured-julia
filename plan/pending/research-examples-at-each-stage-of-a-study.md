# Research examples at each stage of a study

Status: in progress on the branch `research-nothing`.

## 1. The request

"also make a nice research examples in various stages" (2026-10-22).

The one study example that exists, "The buffer of the access router", is a
finished study: it has decisions and an answer. A person who opens the examples
must also see a study at the start and in the middle of the work.

## 2. The design

Four new studies, each at one stage of the work, each on another subject, so the
examples also show that the domain is not about one kind of problem. The study
that exists is the fifth stage.

| Stage | Example | Study | What it holds |
| --- | --- | --- | --- |
| 1. Framed | `research_framed` | The channel plan of the office Wi-Fi | two questions, the second under the first, and a note as an attachment |
| 2. Grounded | `research_grounded` | The battery of the soil sensor | a question, three sources, three competing hypotheses with predictions, a decision that accepts two sources |
| 3. Planned | `research_planned` | Control traffic through the time-aware shaper | a question, two sources, two hypotheses with expectations, an experiment with its design, an analysis with a formula sheet, a decision that approves the experiment |
| 4. Contested | `research_contested` | Fairness of a new congestion control against CUBIC | results, evidence for and against the hypothesis, a new hypothesis from the evidence, and no decision about them yet |
| 5. Concluded | `research` | The buffer of the access router | the example that exists |

Rules that each example keeps, so it is a study that the editor could have made:

- The ids follow `make_research_id`: the letter of the kind and 1, 2, 3 in order.
- A status other than `:open` comes from a decision that names the item, and the
  last such decision gives it.
- Each link holds an item of the same study.
- The times grow in the order of the work, on days of their own for each study.
- The person and the assistant each make a part, as in real work.

## 3. The steps

1. [x] The four builders `make_research_<stage>_study_document_example()` in
   `example/domain/research/ResearchStageExample.jl`, exported by
   `ProjecturedResearchExample`.
   Done: a source whose address is not sure has no link; the links that stand are
   the arXiv entry of the fairness index and the DOIs of X-MAC and CUBIC. The
   numbers of each study agree: the current of the soil sensor gives 30 and 9
   days on 220 mAh, the shares 81 % and 19 % give a fairness index of 0.72, and
   the guard band is one frame of 1538 bytes at 1 Gb/s.
2. [x] The examples `research_framed`, `research_grounded`, `research_planned`
   and `research_contested` in `DomainExamples.jl` and the registry, and in the
   list of widget views that the navigation sweep skips.
   Done: they stand before `research` in both lists, in the order of the stages.
3. [x] A test that each stage example keeps the rules of section 2, in
   `ResearchDocumentTest.jl`; `test_printer`, `test_reader` and `test_repl` of
   the four examples.
   Done: `_find_research_study_faults` answers the faults as texts, and the five
   studies have none. `test_research()` 310 of 310; the printer, reader and REPL
   tests of the five research examples 173 424 of 173 424.
4. [ ] Pictures of the four outlines, and the guide of the domain names the
   examples.
