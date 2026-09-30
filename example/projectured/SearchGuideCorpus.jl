# Fragment of `ProjecturedExample` — questions of the guides of this repository,
# each with the section that answers it.
#
# `SCALE_SEARCH_QUESTIONS` names a guide; these name a section, as
# `guide#heading`, so a ranking of the parts of the guides is measured where the
# answer is and not only in which file. The sentences are what a person asks,
# and they avoid the words of the heading where a person would.

"""
    GUIDE_SEARCH_QUESTIONS

Questions of the guides, each with the section that answers it, as
`guide#heading`.
"""
const GUIDE_SEARCH_QUESTIONS = SearchQuestion[
    SearchQuestion(("what must the name of a function start with", "",
                    ["rule/naming-rules#Functions"], :guide, :guide)),
    SearchQuestion(("a test is known to fail for now; how do I say so in the test", "",
                    ["guide/testing-guide#Marking known-failing tests"], :guide, :guide)),
    SearchQuestion(("check that the screen changes when the data behind it change", "",
                    ["guide/testing-guide#Reactivity: does the output follow the input?"], :guide, :guide)),
    SearchQuestion(("test one example on its own", "",
                    ["guide/testing-guide#Testing a single example"], :guide, :guide)),
    SearchQuestion(("a key press does nothing; find which projection drops it", "",
                    ["guide/debugging-guide#Bisecting the pipeline (a keystroke declines — which stage?)"],
                    :guide, :guide)),
    SearchQuestion(("save a picture of what an example shows", "",
                    ["guide/debugging-guide#Writing a single screenshot"], :guide, :guide)),
    SearchQuestion(("may a comment say how the code looked before a change", "",
                    ["rule/code-quality-rules#2. A comment says what is, never what was"], :guide, :guide)),
    SearchQuestion(("how many arguments may a function take without keywords", "",
                    ["rule/code-quality-rules#4. Arguments: three positional, then names"], :guide, :guide)),
    SearchQuestion(("the first thing to write when I add support for a new file format", "",
                    ["guide/new-domain-guide#Step 1: Define the document types"], :guide, :guide)),
    SearchQuestion(("what happens between a key press and the new picture on the screen", "",
                    ["design/concepts#What happens when you press a key"], :guide, :guide)),
    SearchQuestion(("when is a computed value computed again", "",
                    ["kernel/cell#Invalidation"], :guide, :guide)),
    SearchQuestion(("remove what the person has selected", "",
                    ["kernel/selection#Clearing selection"], :guide, :guide)),
    SearchQuestion(("how does a selection on the screen go back to the document", "",
                    ["kernel/selection#How the reader translates the selection backward"], :guide, :guide)),
]
