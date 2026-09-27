# The web site: the title, and a page that a newcomer can follow

**Status (2026-09-27): in progress.** Every question has an answer (§4.1). The
owner said to implement the plan in worktrees, and to wait with every part that
needs the M/M/1/K video (S0), which is still being made. The work is on the
branch `web-site-title` of `projectured.github.io` and of `projectured-julia`,
in the worktrees `projectured.github.io-web-site-title` and
`projectured-julia-web-site-title`.

The video S11 about laziness is already on the page: another session added it
to `main` of the site as commit `839316e`, "Only what you look at is computed".

**Goal:** a visitor of `projectured.org` who does not know the project
understands in a few seconds what ProjecturEd is and what is different about
it. Then the page gives the evidence, the uses, and the way to try it, in that
order. The page stays a plain technical description, as the owner asked on
2026-09-19. It does not become a sales page.

**Repositories:**

- `projectured.github.io`: the page `index.html` and the social card
  `assets/og.png`.
- `projectured-julia`: only the texts that must stay the same as the title of
  the page. These are the tagline of the README, the slide deck and the drafts
  of the posts (§3.5).

## 1. The request

The owner, on 2026-09-27, about the title:

> I don't really like the title of the web page. I don't know what transform
> means there specifically. Perhapse it would be better to just use Edit becase
> it implied view.
>
> I came up with this: Edit arbitrary structured data - with an AI assistant

Then the owner gave a review of the page by ChatGPT, and said:

> let's discuss what we are going to do and what we don't do and why

The owner's answers to my four questions, and the request for this plan:

> for 1, I changed the repository to be public
> for 2, two new videos are coming, the M/M/1/K video will be the hero, another
> one video about laziness
> a table will take the edit soon enaough, I'll make sure that
> for 3, yes
> for 4, yes
>
> we should find the best title because that's very important. I need multiple
> candidates.
>
> let's write a plan

The owner also gave title ideas from two other AI agents. §3.2 lists them.

## 2. What exists

These facts were checked on 2026-09-27.

### 2.1 The page

The sections are in this order: hero, the idea, compared, capabilities (12
cards), AI (one spotlight and 6 cards), see it in action, videos (6 videos),
examples, catalog, lineage and status.

- **The title** is "View, edit and transform structured data — with an AI
  assistant." It is in `<title>`, in the `<h1>`, and in the meta tags
  `description`, `og:title`, `og:image:alt` and `twitter:title`. The `<title>`
  does not contain "Julia".
- **The social card** `assets/og.png` shows the old title in the picture. The
  repository has no source file for it.
- **The status notice** comes directly after the `<h1>`, before the text that
  says what ProjecturEd is. The section "Lineage & status" at the bottom says
  the same thing again, and it also names three limits.
- **The same picture twice:** the hero and "See it in action" both show
  `assets/assistant.jpg`.
- **The same point five times:** the hero text, the second row of "Compared",
  the card "An assistant on the same data", the head of the AI section and the
  card "One set of operations" all say that the assistant uses your operations.
- **No link to the source.** The only links to `projectured-julia` are the two
  links in the status notice. The navigation and the section "Lineage & status"
  link only to the Common Lisp source.
- **No way to try it.** The page has no install or quick start text.
- The caption of "See it in action" says that the editor draws every picture on
  the page.

### 2.2 Around the page

- **The repository `projectured-julia` is public** since 2026-09-27. The
  repository, the roadmap and the issues answer 200.
- **The README** has a quick start (`git clone`, `bin/projectured`), the list
  "What you can do with it" (11 items, each names code that exists), and the
  list "Status and limits".
- **A table does not take an edit yet.** The page and the README both say so.
  The owner makes a table cell take an edit soon.
- **Two new videos come.** S0, the M/M/1/K study, is the hero
  ([feature-video-screenplays.md](feature-video-screenplays.md)). S11 shows
  laziness ([lazy-list-video.md](lazy-list-video.md)). Three decisions of the
  screenplay plan apply to the site:
  - D11: the caption of S0 does not name the private product, and the text says
    that the code of the study is not in the public repository.
  - D12: no part of a video is made faster. S0 lasts about 10 min to 25 min.
  - D7: a wait for the model is never cut.
- **The framing (D3 of [documentation-rewrite.md](documentation-rewrite.md),
  2026-09-17):** ProjecturEd is an application first. The viewer, the editor and
  the assistant have equal weight. "Projectional editor" appears only in "How it
  works". §2.1 of that plan holds the approved texts, and says that the README,
  the web site, the deck and the posts use the same texts.
- **The Common Lisp README** already says that the repository is archived, and
  it points to the web site.

## 3. The title

The title is the `<h1>` of the hero. `<title>`, the meta tags and the social
card use the same words.

### 3.1 What the title must do

1. **Be true today.** Most views take edits, not all. A table does not take an
   edit yet. So a title must not say "every view" or "any view".
2. **Be clear to a newcomer in a few seconds.** Do not use a word that the
   reader must learn first: "projectional", "semantic", "domain".
3. **Say what is different.** Many tools can say "edit structured data". Few
   can say that one piece of data has several views, and that each edit goes to
   the data.
4. **Fit the hero.** The hero is the M/M/1/K video. In it, the assistant builds
   a study book: prose, a model, a configuration, a simulation run and a chart.
   The book is one document, and its parts are views of it.
5. **Keep the equal weight of D3,** or change D3 on purpose.
6. **Be short.** The `<h1>` has three lines. A search result shows about 60
   characters of `<title>`, and "ProjecturEd — " takes 14 of them.
7. **Use plain English.** No slogan that makes a promise, and no object that
   acts like a person.

The title does not need to carry everything. A sub-line under it says what
ProjecturEd is in plain words (§3.4). So the title can carry the one idea that
is different.

### 3.2 The candidates

| # | Title | From | For | Against |
| --- | --- | --- | --- | --- |
| T1 | Edit any structured data — with an AI assistant. | the owner | Clear. True: about twenty kinds of data, and any Julia value by reflection. Keeps D3. 48 characters. | Does not say what is different. Many tools claim this, and many add "with AI" now. |
| T2 | One structure, many editable views — with an AI assistant. | another agent; the owner likes it | Says what is different, in six words. True: "many" is not "all". Fits the hero: the study book is one structure with many views. | "Structure" is abstract, so the sub-line must say "data". 58 characters. The form "One structure. Many editable views. — with …" puts a dash after a full stop; a comma reads better. |
| T3 | Edit the structure, not the text. | the footer of the page today | Short. Sets ProjecturEd apart from a text editor and from an assistant that writes text. Already on the page. | No AI and no views. "Structure" is abstract. |
| T4 | Edit the data, not the text — in many views, with an AI assistant. | mine: T3 and T2 together | "Data" is clearer than "structure". Has the difference, the views and the AI. | 67 characters: long for a search result. Three parts, so less easy to remember. |
| T5 | Your data, its views, your programs and an AI assistant — on one structure. | mine, from "an environment where data, views, programs and AI operate on the same structure" | Fits the hero best: the video shows data, views, a program run and the assistant. | A list of four nouns. "On one structure" is abstract. 75 characters. |
| T6 | The data is the source. Every view is computed from it. | the head of "The idea" today | Plain, true, and it is the core idea. | No edit and no AI. It explains the mechanism before the reader knows why it matters. |
| T7 | The assistant edits your data, not a text copy of it. | mine, from the approved introduction | Clear and true. The difference is strong for a reader who knows AI tools. | Puts the AI first, which changes D3. Says nothing about views. |
| T8 | Give the AI the application, not the source code. | another agent | Strong and short. | A command to the reader, as in a sales page. It can be read as false: the assistant writes Julia source code and runs it. Puts the AI first, which changes D3. |
| T9 | A semantic environment for humans and AI assistants. | another agent | Short. | "Semantic" has many meanings: the semantic web, semantic search. "Environment" does not say what the program does. The reader can not guess the product. |
| T10 | One structure, seen every way — and editable every way. | the first page, before 2026-09-19 | Has rhythm. The review liked it. | "Every way" is false: not every view takes edits. No AI. The owner replaced it on 2026-09-19. |

The two other variants of T9 ("a semantic environment for collaborative
human–AI work", "semantic application environment for humans and AI") have the
same faults as T9.

### 3.3 My recommendation

**The owner chose T2 on 2026-09-27**, in the form "One structure, many editable
views — with an AI assistant." My recommendation, from before the choice:

- **Shortlist:** T2, T4 and T5, with T1 as the control.
- **My first choice is T2.** It carries the one idea that no other tool has, in
  six words. It is true today. It fits the M/M/1/K hero, because the study book
  is one structure that the person and the assistant edit in many views. The
  sub-line removes the weak point: it says "data" where T2 says "structure".
- **T7 and T8** are good heads for the AI section, not for the page. They put
  the AI first, and D3 gives the three roles equal weight. My version for the AI
  section is T7. T8 can be read as false.
- **Do not use T9 or T10**, for the reasons in the table.

### 3.4 The sub-line

One sub-line goes under any of the titles. It is the first sentence of the hero
text, and it uses the approved words of §2.1 of the documentation rewrite:

> ProjecturEd is an application to view and edit structured data: JSON, XML,
> Markdown, SQL, Julia code, math, charts and more. Most views take your edits,
> and an AI assistant edits the same data with the same operations as you. It
> is written in Julia.

### 3.5 How to choose

The owner chose T2 without the render of the shortlist. The steps below stay as
the method for a later change of the title.

1. Render each title of the shortlist in the real hero: the `<h1>` with its
   three lines, the sub-line and the hero picture. Make one picture at desktop
   width and one at phone width, in the light and the dark theme.
2. The owner compares the pictures side by side and chooses.
3. Optional: show only the hero to two or three people who do not know the
   project. Ask them what the program does. Compare their answers with the
   sub-line.

### 3.6 What the chosen title changes

§2.1 of the documentation rewrite says that the README, the web site, the deck
and the posts use the same texts. So the new title changes these places:

- `index.html`: `<title>`, `<h1>`, and the meta tags `description`,
  `og:title`, `og:description`, `og:image:alt`, `twitter:title` and
  `twitter:description`.
- `assets/og.png`: draw it again.
- The first line of `README.md` in `projectured-julia`.
- The description of the GitHub repository. The owner changes it, because `gh`
  is not signed in on this machine.
- `presentation/projectured-overview.md`: the title slide.
- The drafts of the posts in §9 of the documentation rewrite.

The tagline "an application to view, edit and transform structured data" also
starts the introduction of the README. Take "transform" out there too, because
that was the reason for this plan.

## 4. Decisions

### 4.1 The owner's answers of 2026-09-27

| # | Decision |
| --- | --- |
| W1 | The repository `projectured-julia` is public. The page can link to it, and it can have a "Try it" section. |
| W2 | The hero is the M/M/1/K video (S0). A second new video shows laziness (S11). Until S0 exists, the hero keeps its picture. |
| W3 | A table cell takes an edit soon. The owner does this work. Until then, the page does not say or show that a table takes an edit. |
| W4 | The status notice becomes one short line at the top. The full text goes to "Lineage & status" at the bottom. |
| W5 | The meta description contains "projectional editor" and "Julia". The hero keeps "projectional editor" out, as D3 says. |

The second answers, the same day:

> for 1, I chose T2 for title
> for 2, yes
> for 3, An assistant on the same data, Domains nest, Composable projections,
> Four backends. Why? because AI is a hot topic and remaing 3 combines in
> multiplicative way
> for 4, yes
> for 5, yes
> for 6, the M/M/1/K study showing the complex UI with assistant and all,
> another one with the Julia evaluator perhaps

| # | Decision |
| --- | --- |
| W6 | The title is T2: "One structure, many editable views — with an AI assistant." |
| W7 | The hero shows S0 as a poster with a play control. The caption gives the length. No autoplay and no excerpt. |
| W8 | The four large cards are "An assistant on the same data", "Domains nest", "Composable projections" and "Four backends". The reason: AI is a topic that readers look for, and the other three multiply: each domain goes through each chain of projections to each backend. The text over the four cards says that they multiply. So the card "An assistant on the same data" stays, and only the card "One set of operations" goes away as a duplicate. |
| W9 | The social card is an HTML template that a headless browser renders. The owner answered "yes" to a question with two choices; I read it as my recommendation. |
| W10 | The new title also replaces the approved tagline in the README, the deck and the posts (§3.6). |
| W11 | The pictures of "The idea" are a still of the M/M/1/K study, with the complex window and the assistant, and perhaps a still of the Julia evaluator. They replace the picture of one document in two views. |
| W12 | "Lineage & status" does not show the original picture of the loops (Q8). The owner, the same day: "we don't need the original picture in the lineage". It does not link to it either. |

The last answers, the same day:

> for Q9, yes
> for Q10, no keep the still for the rotating example too, it's fancy and easy
> to understand, the video is long and maybe skipped
> for Q11, dashed arc labelled "conversation" and explained in the text
>
> I accept the rest

| # | Decision |
| --- | --- |
| W13 | The hero poster is an early frame of S0: the request to the assistant. The still in "The idea" is the last frame: the finished study with its chart (Q9). |
| W14 | "The idea" also has a still of the rotating vector, because it is easy to understand and a visitor can skip the long video (Q10). The still shows only the evaluator and the picture pane, so it is not the same picture as the poster of the video, which is the whole window. |
| W15 | The picture of the loops gets a dashed arc from the human loop to the assistant loop, over the editor, with the label "conversation". The caption explains it (Q11, §7.4c). |
| W16 | The owner accepts the rest: the social card as an HTML template (W9), and the rows R1 to R14 of §4.2. |

### 4.2 The review: what we do and what we do not do

The rows below were my recommendations. The owner accepted them (W16).

| # | Point of the review | What we do | Why |
| --- | --- | --- | --- |
| R1 | A hero around "one structure, many views"; "projectional editor" as the main identity | The title of §3. "Projectional editor" stays in "The idea" and in the meta description. | D3, and W5. |
| R2 | The status notice before the product | Do it (W4). | |
| R3, R4 | One data with several views, as the main picture | "The idea" gets the picture of the three loops (§7) and the stills of W11. Not two sections. | The loops show the idea with the names that the code uses. The stills show it in the program. |
| R5 | Put the AI after the projection story | Do not change the order. Delete the card "One set of operations" (W8). | The idea already comes before the AI section. Only the hero puts AI first. |
| R6 | A section "What can you use it for?" | Do it, from the README list "What you can do with it". | Each item of that list names code that exists. The review's list has items that nobody checked. |
| R7 | Too many cards of equal size | Four large cards, and the others in a smaller grid. | The owner chose the four (W8). |
| R8 | The result first, then the mechanism | Only where the result is a fact. | The approved text has one: "Parts of a document that are not on the screen cost nothing". Do not add a claim without a measurement. |
| R9 | A demo video under the hero | The hero is S0 (W2). The table demo of the review waits for W3. | |
| R10 | A head "Build with ProjecturEd" over the examples and the catalog | Do it. | It shows where the page changes from the user to the developer. |
| R11 | A way to try it | Do it: a "Try it" section and a link in the hero (W1). | |
| R12 | The search identity | "Julia" goes into `<title>` and the meta text. "Projectional editor" goes into the meta description (W5). | The Common Lisp README already points to the site. Quickdocs is not our site. |
| R13 | Plain words in the headings | Some. See the list below. | |
| R14 | A structure of 15 sections | Do not do it. Use the order of §5. | It has more sections than the page has now, and some of them repeat each other. |

The headings (R13):

- "Four backends" becomes "A window, a terminal or a browser". Not
  "headlessly": the word is not plain.
- "Domains nest" becomes "One document, many kinds of data". Not "freely".
- "A selection is a path" stays. "Selections understand structure" writes about
  a selection as if it could think.
- "Edits are operations" becomes "An edit keeps the data well formed". The card
  already says this.
- "The conversation holds documents" becomes "A reply can hold a table, a
  formula or code". Not "live".
- "One set of operations" goes away. It is one of the duplicates of §2.1.

### 4.3 What we do not do

- **No "every view" or "any view".** It is false until every view takes edits.
- **No hand-made picture of the program.** Every screenshot and every video
  comes from the editor. A diagram of a concept, such as the loops of §7, can be
  drawn by hand, because it does not claim to show the program. The caption
  "every picture on this page is" drawn by the editor goes away with "See it in
  action" in Step 1.
- **No "semantic" and no "environment" in the title.** A reader can not tell
  what the program does from these words.
- **No sales voice.** No "revolutionize", no "unlock", no benefit that was not
  measured. The review agrees in its own last section.
- **No excerpt of S0 in the hero.** D7 and D12 of the screenplay plan say that
  a take is not cut and not made faster.

## 5. The order of the page

1. Hero: the title, the sub-line, one short status line, the S0 video (a
   picture until it exists), and the links "Try it", "GitHub" and "See the
   idea".
2. The idea, with the picture of the three loops (§7) and the stills of W11.
3. What you can do with it.
4. Compared.
5. Capabilities: four large cards, then the other cards.
6. AI.
7. Videos, with S11 when it exists.
8. Try it.
9. Build with ProjecturEd: the examples and the catalog.
10. Lineage and status.

"See it in action" goes away. Its picture moves to the AI section when S0
replaces it in the hero.

## 6. Open questions for the owner

Every question has an answer (W6 to W16 in §4.1).

| # | Question | My recommendation |
| --- | --- | --- |
| Q1 | Which title? | Answered: T2 (W6). |
| Q2 | S0 lasts 10 min to 25 min. How does the hero show it? | Answered: a poster and a play control (W7). |
| Q3 | Which four capabilities are large? | Answered (W8). |
| Q4 | How is the social card made? | Answered: an HTML template in `assets/og/` of the site, rendered by a headless browser (W9). |
| Q5 | Does the new title also replace the approved tagline in the README, the deck and the posts (§3.6)? | Answered: yes (W10). |
| Q6 | Which pictures go in "The idea"? | Answered: a still of S0 and perhaps a still of the evaluator (W11). |
| Q7 | The loops of §7: three in a row, or a triangle around the data? | Answered: three separate loops in a row, with synchronization points and no data (§7.4a). |
| Q8 | Does the original picture go into "Lineage & status"? | Answered: no (W12). |
| Q9 | The hero poster and the still of "The idea" both come from S0. Which frames? | Answered: an early frame and the last frame (W13). |
| Q10 | The page already has a video of the evaluator ("The rotating vector, form by form"). Is a still of it in "The idea" still needed? | Answered: yes (W14). |
| Q11 | The assistant also reads the words of the person. Does the picture draw a synchronization point from you to the assistant? | Answered: a dashed arc labeled "conversation", explained in the caption (W15). |

No question is open.

## 7. The picture of the three loops

### 7.1 The original

The Common Lisp ProjecturEd has a picture with the title "Human-Computer
Communication". It has two loops of read, eval and print, and the two loops
touch:

- **The loop of the person:** Read with the eye, Eval in the head, Print with
  the hand.
- **The loop of the computer:** Read from the keyboard and the mouse, Eval on
  the document, Print to the screen.

The screen feeds the eye, and the hand feeds the keyboard. So the two loops make
one cycle.

The owner asked on 2026-09-27:

> which shows the original idea of projectured lisp, should we add it but extend
> it first by adding a third participant the AI assistant. The AI agent also has
> its own loop, and there could be the data in the center

### 7.2 Why the picture goes on the page

- **The words of the picture are the words of the code.** A projection is a
  printer and a reader. So the picture explains "The idea" with the names that a
  developer finds later in the source.
- **It adds the assistant without a separate story.** The assistant is a third
  participant in the same cycle, not a feature beside the editor.
- **It connects the Julia version to the original.**

### 7.3 The design: three loops in a row, the data in the middle

The loops go from left to right: the person, the editor, the assistant. They do
not make a triangle. The person and the assistant never talk directly: a request
to the assistant is a gesture into the conversation, and the conversation is a
document in the editor. A triangle draws a direct line that does not exist.

The middle loop is the editor. It meets the person on its left side and the
assistant on its right side, so its Eval can not be outside, as in the original.
The Eval goes to the center: an operation changes the data. So the data is in
the center of the picture, as the owner suggested. This is also true to the
original, where the computer evaluates on the document.

```text
              the view                          the result as text
   ┌────── Read ◀────────── Print ──────────▶ Read ──────┐
   ▼                          ▲                          ▼
 Eval    the person      Eval: an operation      the assistant    Eval
   │                      changes the DATA                        │
   ▼                          ▲                          ▼
   └─────▶ Print ─────────▶ Read ◀────────── Print ◀─────┘
              a gesture                          a tool call
                            the editor
```

| Loop | Read | Eval | Print |
| --- | --- | --- | --- |
| The person | the view, with the eyes | in the head | a gesture: a key or a click |
| The editor, for the person | a gesture: the reader makes an operation | the operation changes the data | the printer makes the view |
| The editor, for the assistant | a tool call: its Julia code runs and makes an operation | `evaluate_operation(editor, operation)` changes the data, as it does for a key | the result as text |
| The assistant | the result as text | in the model | a tool call with Julia code |

The code supports each row. The printer and the reader are the two functions
of a projection. The description of the code tool in
`source/kernel/tool/DefaultTools.jl` tells the model to change the data with an
operation that `evaluate_operation(editor, operation)` runs.

The caption says the one idea of the picture: the person and the assistant are
two users of the same editor. Each reads a print of the data and sends edits
back through the editor. A request to the assistant goes through the center
too, because the conversation is a document.

### 7.4 How the picture is drawn

- **An inline SVG.** Its text and its icons use the colors of the page, so it
  follows the light and the dark theme (§7.4b).
- **No clip art from the original.** Nobody recorded where its icons come from.
  A new drawing avoids the question of their licences.
- **A second layout for a phone.** At phone width, the three loops go one above
  the other. The page has two SVG elements, and CSS shows one of them.
- **The labels are text in the SVG,** so a screen reader and a search engine
  can read them. The figure has a text alternative that says the cycle in
  words.
- **The editor does not draw it.** Curved arrows and icons cost more in the
  editor than the picture is worth. §4.3 allows a diagram of a concept.

### 7.4a The owner's correction of §7.3 (2026-09-27)

The owner compared version 1 (§7.3) with a picture from another agent, and
answered:

> for 1, it's not true, a human is reading with her eye not by print_document
> which is the printer of the editor, the agent LLM is reading the tokens on its
> input from the tool call or from the human, same issue
> for 2, data is not needed, this is better
> for 3, maybe we could have those better icons
> for 4, they are separate processes with synchronization points

So the design of §7.3 is replaced. Version 2 has these properties:

- **Three separate loops.** Each one turns clockwise: Read, Eval, Print. The
  Read of one loop is not the Print of another; each participant reads with its
  own means.
- **Synchronization points between the loops,** as arrows with a direction:
  "the view" and "keys and clicks" between you and ProjecturEd, "tool results"
  and "tool calls" between ProjecturEd and the assistant.
- **No data in the center.** The center of the editor loop is the mark of
  ProjecturEd and its name.
- **An icon at each step, from the Lucide font** of the repository
  (`asset/font/lucide.ttf`, ISC licence): eye, brain and pointer for you;
  keyboard, settings and monitor for ProjecturEd; file-text, bot and code for
  the assistant. The page must carry a credit line for Lucide.

The generator of both versions is a Python script with `fontTools`. The
request of the person to the assistant is not drawn yet (§6, Q11).

### 7.4b Version 5, accepted (2026-09-27)

The owner then gave a third version, made by the other agent (`/tmp/repl.svg`),
and said:

> I don't really like the icons for input/output of the AI agent but the rest is
> good, maybe you want to tune the colors

Then the owner asked for a human face in place of a brain, and for icons that
are centered in their discs. The owner accepted version 5:

> it's good enough fold it in the plan

Version 5 keeps the layout of the owner's version:

- three loops in a row, each one a clockwise band from Read to Eval to Print;
- a tinted disc with an icon at each step;
- the name of the loop in its center;
- a two-way arrow between two loops, with the labels "user interaction" and
  "tool calls".

| Loop | Color | Read | Eval | Print |
| --- | --- | --- | --- | --- |
| Human | blue `#5b82ff` | `eye` | `face-slightly-smiling` | `pointer` |
| Editor | green `#36ad80` | `keyboard` and `mouse` | `settings` | `monitor` |
| AI Assistant | amber `#e3a236` | `scan-text` | `bot` | `square-terminal` |

The icon names are glyph names of the Lucide font.

What version 5 changes in the owner's version, and why:

- **The arrowheads are shapes, not SVG markers.** The owner's file used
  `markerUnits="strokeWidth"` on a band 18 wide, so Chrome and librsvg drew each
  head about 216 px wide.
- **The two-way arrows point both ways.** In the owner's file, the start head
  was reversed twice, by a reversed path and by
  `orient="auto-start-reverse"`, so both heads pointed right.
- **Each band ends in a head that is visible.** In the owner's file, the head
  into Print was under the Print disc, and the bottom band had a gap.
- **The text and the icons use the colors of the page,** so the picture follows
  the dark theme. A disc is the color of its loop at 18 % to 22 % opacity. The
  owner's file had a white background and fixed colors.
- **No title inside the picture.** The heading of the section says it, and a
  title in the picture shrinks to about 12 px at phone width.
- **New icons for Read and Print of the assistant, and a face for Eval of the
  human,** as the owner asked.

**A fact found on the way:** the Lucide font stores a box for each glyph that
always starts at (0, 0). The real outline starts elsewhere, for example at
(42, 167) for `eye`. An icon centered on the stored box is off by up to 4 px in a
disc of 104 px. The generator measures the outline with `BoundsPen`. On the
rendered pixels, every icon of version 5 is within 0.5 px of the center of its
disc.

**Not changed:** the label "user interaction" is vague; "the view · keys and
clicks" says what passes. The owner kept the labels of the owner's version.

**Not done:** the layout for a phone (§7.4). At 343 px the text of this layout is
about 7 px high, so a phone needs the three loops one above the other (Step 4).

**The generator.** It makes version 6 byte for byte: version 5 and the arc of
§7.4c. It needs `fontTools`.
Step 4 puts it into the site repository as `tool/make-repl-loops.py`, and runs it
with the font of a `projectured-julia` checkout beside the site:

```sh
python3 tool/make-repl-loops.py ../projectured-julia/asset/font/lucide.ttf repl-loops.svg
```

```python
"""Draw the three read-eval-print loops of the web site as one SVG.

Usage: python3 make-repl-loops.py <lucide.ttf> <output.svg>

The icons are glyphs of the Lucide font (ISC licence) that ProjecturEd uses.
Text and icons take the colors of the page (--ink, --ink-soft, --ink-faint,
--sans), so the picture follows the light and the dark theme.
"""
import math
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

R = 150            # radius of a loop
NODE = 52          # radius of the disc behind a step icon
BAND = 16          # width of an arrow band
HEAD = 30          # length of the head of a band
CY = 250
CENTERS = (230, 750, 1270)
VIEW = (40, -66, 1420, 492)   # x, y, width, height
ANGLE = {"Read": 90, "Eval": -30, "Print": -150}
LOOPS = [
    ("human", ("Human", "Loop"), {"Read": ["eye"], "Eval": ["face-slightly-smiling"], "Print": ["pointer"]}),
    ("editor", ("Editor", "Loop"), {"Read": ["keyboard", "mouse"], "Eval": ["settings"], "Print": ["monitor"]}),
    ("ai", ("AI Assistant", "Loop"), {"Read": ["scan-text"], "Eval": ["bot"], "Print": ["square-terminal"]}),
]
LINKS = ("user interaction", "tool calls")
CONVERSATION = "conversation"

STYLE = """
  .repl-loops { --loop-human: #5b82ff; --loop-editor: #36ad80; --loop-ai: #e3a236; }
  .repl-loops text { font-family: var(--sans, system-ui, -apple-system, "Segoe UI", sans-serif); text-anchor: middle; fill: var(--ink, #15181d); }
  .repl-loops .loop-title { font-size: 28px; font-weight: 700; }
  .repl-loops .stage { font-size: 19px; font-weight: 700; }
  .repl-loops .link-label { font-size: 18px; font-weight: 600; fill: var(--ink-soft, #545b66); }
  .repl-loops .icon { fill: var(--ink, #15181d); }
  .repl-loops .band { fill: none; stroke-width: 16; }
  .repl-loops .band.human { stroke: var(--loop-human); }  .repl-loops .band-head.human { fill: var(--loop-human); }
  .repl-loops .band.editor { stroke: var(--loop-editor); } .repl-loops .band-head.editor { fill: var(--loop-editor); }
  .repl-loops .band.ai { stroke: var(--loop-ai); }        .repl-loops .band-head.ai { fill: var(--loop-ai); }
  .repl-loops .node.human { fill: var(--loop-human); fill-opacity: .18; }
  .repl-loops .node.editor { fill: var(--loop-editor); fill-opacity: .18; }
  .repl-loops .node.ai { fill: var(--loop-ai); fill-opacity: .22; }
  .repl-loops .sync { fill: none; stroke: var(--ink-faint, #8a919c); stroke-width: 5; }
  .repl-loops .sync-head { fill: var(--ink-faint, #8a919c); }
  .repl-loops .conversation { fill: none; stroke: var(--ink-faint, #8a919c); stroke-width: 4; stroke-dasharray: 12 10; stroke-linecap: round; }
"""
DESCRIPTION = (
    "Three separate read-eval-print loops in a row: the human, the editor and the AI assistant. "
    "The human reads with the eyes, decides, and acts with the hand. The editor reads the keyboard and the mouse, "
    "evaluates, and prints to the screen. The AI assistant reads text, the model decides, and it prints a tool call. "
    "The human and the editor meet at the user interaction; the editor and the AI assistant meet at the tool calls. "
    "A dashed arc over the editor joins the human and the AI assistant: the conversation.")


def make_icon(glyphs, name, cx, cy, size):
    """The glyph `name`, centered on (cx, cy), with its larger side equal to `size`."""
    path = SVGPathPen(glyphs)
    glyphs[name].draw(path)
    # The box that the font stores for a glyph starts at (0, 0), so measure the outline itself.
    bounds = BoundsPen(glyphs)
    glyphs[name].draw(bounds)
    x_min, y_min, x_max, y_max = bounds.bounds
    width, height = x_max - x_min, y_max - y_min
    scale = size / max(width, height)
    tx = cx - scale * (x_min + width / 2)
    ty = cy + scale * (y_min + height / 2)
    return (f'<path class="icon" transform="translate({tx:.2f} {ty:.2f}) scale({scale:.5f} {-scale:.5f})" '
            f'd="{path.getCommands()}"/>')


def get_point(cx, theta):
    t = math.radians(theta)
    return (cx + R * math.cos(t), CY - R * math.sin(t))


def make_band(cx, start, end, loop):
    """A clockwise band on a loop from angle `start` down to angle `end`, which ends in a wide head."""
    t = math.radians(end)
    dx, dy = math.sin(t), math.cos(t)
    x1, y1 = get_point(cx, end)
    xs, ys = get_point(cx, end + math.degrees(HEAD * 0.8 / R))
    x0, y0 = get_point(cx, start)
    nx, ny = -dy, dx
    bx, by = x1 - dx * HEAD, y1 - dy * HEAD
    w = BAND * 1.25
    head = f"M{x1:.1f} {y1:.1f} L{bx + nx * w:.1f} {by + ny * w:.1f} L{bx - nx * w:.1f} {by - ny * w:.1f} z"
    return (f'<path class="band {loop}" d="M{x0:.1f} {y0:.1f} A{R} {R} 0 0 1 {xs:.1f} {ys:.1f}"/>'
            f'<path class="band-head {loop}" d="{head}"/>')


def make_sync(x0, x1, y):
    """A two-way arrow between two loops."""
    h, w = 16, 9
    return (f'<path class="sync" d="M{x0 + h * 0.8:.1f} {y} H{x1 - h * 0.8:.1f}"/>'
            f'<path class="sync-head" d="M{x0} {y} L{x0 + h} {y - w} L{x0 + h} {y + w} z"/>'
            f'<path class="sync-head" d="M{x1} {y} L{x1 - h} {y - w} L{x1 - h} {y + w} z"/>')


def make_conversation(x0, x1, y, rise):
    """A dashed two-way arc over the editor, from the loop of the human to the loop of the assistant."""
    c0, c1 = (x0 + 100, y - rise), (x1 - 100, y - rise)
    h, w = 16, 9
    heads = []
    for (tip_x, tip_y), (from_x, from_y) in (((x0, y), c0), ((x1, y), c1)):
        dx, dy = tip_x - from_x, tip_y - from_y
        n = math.hypot(dx, dy)
        dx, dy = dx / n, dy / n
        bx, by = tip_x - dx * h, tip_y - dy * h
        heads.append(f'<path class="sync-head" d="M{tip_x:.1f} {tip_y:.1f} L{bx - dy * w:.1f} {by + dx * w:.1f} '
                     f'L{bx + dy * w:.1f} {by - dx * w:.1f} z"/>')
    # the dashed line stops short of each tip, so the dash does not show through the head
    s0 = (x0 + (c0[0] - x0) * 0.1, y + (c0[1] - y) * 0.1)
    s1 = (x1 + (c1[0] - x1) * 0.1, y + (c1[1] - y) * 0.1)
    peak = y - rise * 0.75
    return (f'<path class="conversation" d="M{s0[0]:.1f} {s0[1]:.1f} C{c0[0]:.1f} {c0[1]:.1f} {c1[0]:.1f} {c1[1]:.1f} '
            f'{s1[0]:.1f} {s1[1]:.1f}"/>' + "".join(heads) + make_text((x0 + x1) / 2, peak - 14, CONVERSATION, "link-label"))


def make_text(x, y, content, cls):
    return f'<text x="{x:.1f}" y="{y:.1f}" class="{cls}">{content}</text>'


def make_svg(glyphs):
    gap = math.degrees((NODE + 12) / R)
    parts = []
    for cx, (loop, title, steps) in zip(CENTERS, LOOPS):
        parts.append(make_band(cx, ANGLE["Read"] - gap, ANGLE["Eval"] + gap, loop))
        parts.append(make_band(cx, ANGLE["Eval"] - gap, ANGLE["Print"] + gap, loop))
        parts.append(make_band(cx, ANGLE["Print"] - gap + 360, ANGLE["Read"] + gap, loop))
        for stage, theta in ANGLE.items():
            x, y = get_point(cx, theta)
            parts.append(f'<circle class="node {loop}" cx="{x:.1f}" cy="{y:.1f}" r="{NODE}"/>')
            names = steps[stage]
            if len(names) == 1:
                parts.append(make_icon(glyphs, names[0], x, y, 46))
            else:
                # a keyboard and a small mouse, centered together
                parts.append(make_icon(glyphs, names[0], x - 13, y, 42))
                parts.append(make_icon(glyphs, names[1], x + 25, y + 4, 24))
            parts.append(make_text(x, y + NODE + 26, stage, "stage"))
        parts.append(make_text(cx, CY + 8, title[0], "loop-title"))
        parts.append(make_text(cx, CY + 42, title[1], "loop-title"))
    reach = R * math.cos(math.radians(30)) + NODE + 14
    for a, b, label in zip(CENTERS, CENTERS[1:], LINKS):
        x0, x1 = a + reach, b - reach
        parts.append(make_sync(x0, x1, CY + 20))
        parts.append(make_text((x0 + x1) / 2, CY - 2, label, "link-label"))
    parts.append(make_conversation(CENTERS[0] + 108, CENTERS[-1] - 108, CY - 170, 150))
    x, y, w, h = VIEW
    return (f'<svg class="repl-loops" viewBox="{x} {y} {w} {h}" role="img" aria-labelledby="repl-loops-title" '
            f'xmlns="http://www.w3.org/2000/svg">\n'
            f'<title id="repl-loops-title">{DESCRIPTION}</title>\n<style>{STYLE}</style>\n'
            + "\n".join(parts) + "\n</svg>\n")


if __name__ == "__main__":
    font_path, output_path = sys.argv[1], sys.argv[2]
    with open(output_path, "w") as output:
        output.write(make_svg(TTFont(font_path).getGlyphSet()))
```

### 7.4c The conversation arc (W15)

The assistant also reads the words of the person. The owner chose to show this
as a dashed arc from the human loop to the assistant loop, over the editor,
with the label "conversation", and to explain it in the text.

- The arc points both ways: the person asks, and the assistant answers.
- It is dashed and gray, as the synchronization arrows are gray, so it does
  not compete with the three loops.
- Its ends stand clear of the Read discs and of the heads of the bands.

The caption under the picture:

> You, ProjecturEd and the AI assistant each run a loop of their own: read,
> evaluate, print. The loops meet at synchronization points. You and the editor
> meet at the screen, the keyboard and the mouse. The editor and the assistant
> meet at tool calls and their results. The dashed arc is the conversation: you
> ask the assistant in plain words, and it answers. The conversation is a
> document in the editor too, so these words also pass through the editor.

Version 6 is version 5 with this arc. The generator of §7.4b makes it.

### 7.5 The original picture in "Lineage & status"

The original picture does not go into "Lineage & status", and the section does
not link to it (W12). The section keeps its text and its links to the Common
Lisp editor.

## 8. Steps

The work goes in a git worktree of `projectured.github.io`, as a sibling in
`workspace/`. Each step is one commit, with explicit paths. A push publishes
the live site, so each push waits for the owner's word.

### Step 1: the changes that do not depend on the title

- [x] The status line at the top (W4). Move the full text to "Lineage &
      status", and make its limits agree with "Status and limits" of the README.
- [x] Links to `projectured-julia`: in the navigation, in the hero, and in
      "Lineage & status".
- [x] Take "transform" out of the meta text. Add "projectional editor" and
      "Julia" to the meta description (W5).
- [x] Delete "See it in action" (the picture is the same as the hero picture).
- [x] Delete the card "One set of operations", a duplicate of §2.1 (W8).
- [x] The headings of R13.
- [x] The head "Build with ProjecturEd" over the examples and the catalog.

      **Done** as site commit `13bb2fe`. The status section is now "Status &
      lineage", with the heading "Under development, and the successor of a
      Common Lisp editor." The hero eyebrow links "under development" to it.
      The footer got a "Source" cell. The card grid got a CSS rule that lets
      the last card fill its row, because the AI section now has five cards
      and an empty cell showed the grid color. A headless browser can not
      scroll to an anchor here, so the review renders a copy of the page that
      hides every other section.

### Step 2: "Try it" and "What you can do with it"

- [x] A "Try it" section from the quick start of the README: what it needs
      (Julia 1.11 or later, SDL2 and SDL_ttf), the three commands, the assistant
      (Ollama or `ANTHROPIC_API_KEY`), and the binary (`bin/build_projectured`).
- [x] A section "What you can do with it", from the README list. Keep the items
      that a newcomer understands without a link.

      **Done** as site commit `c3606b5`. "Uses" keeps six of the eleven
      items of the README. It leaves out the MCP client, because a newcomer
      does not know the word, and the other backends, because a large card
      says it. It also leaves out undo, the fault barrier and the tools by
      name, which are details. The navigation dropped "Compared" to keep its
      length; the section stays on the page.

### Step 3: the capabilities

- [x] The four large cards of W8, then the other cards in a smaller grid. The
      text over the four says that the last three multiply.
- [x] The card about incremental update says the result first, with the words
      of the approved text (R8).

      **Done** as site commit `a7622ef`. The incremental card now has the heading
      "Only what you look at is computed", the title of the video S11, and it
      links to that video. The rule that lets the last card fill its row does
      not apply to the large grid, which has two columns.

### Step 4: the picture of the three loops (version 5, §7.4b)

- [x] Put the generator of §7.4b into the site repository as
      `tool/make-repl-loops.py`.
- [x] Add a phone layout to the generator: the three loops one above the
      other, with vertical two-way arrows. CSS shows one of the two SVG
      elements.
- [x] Add the dashed arc "conversation" of §7.4c to both layouts.
- [x] Put both SVG elements and the caption of §7.4c in "The idea". The owner
      reads a render at desktop width and at phone width before the commit.
- [x] A still of the rotating vector in "The idea": the evaluator and the
      picture pane only (W14).
- [x] A credit line for the Lucide icons (ISC licence) in the footer.

      **Done** as site commit `5b60017`. The generator of §7.4b became
      `tool/make-repl-loops.py` of the site, with two changes:

      - a tall layout for a phone: the three loops one above the other, the
        two-way arrows vertical between them, and the conversation arc on the
        right with its label turned along it. The text of the tall layout is
        a little larger, because a phone scales it down more.
      - an output mode for `index.html`: it puts both layouts between
        `<!-- repl-loops:begin -->` and `<!-- repl-loops:end -->`, with a
        comment that names the Lucide licences. CSS shows the tall layout
        below 641 px.

      The wide layout draws version 6: a pixel comparison found 91 pixels
      that differ, all in the label "conversation", which moved by half a
      pixel. Two of the icons (`monitor` and the terminal shape) come from
      Feather under the MIT licence, so `assets/Lucide-ISC.txt` of the site
      holds the whole licence file of the font, with both notices. The still
      of the rotating vector is the frame at 95 s, cut to the evaluator and the
      picture pane: it shows the forms from the ring on, and it is not the
      poster frame.

### Step 5: the title T2

- [x] Change every place of §3.6 in `index.html`, with the sub-line of §3.4.
- [x] Draw `assets/og.png` again from an HTML template in `assets/og/` (W9).
- [x] In `projectured-julia`: the first line of the README, the introduction
      (take "transform" out), the title slide of the deck, and the post drafts.
      This is one commit in that repository.
- [x] Give the owner the new description of the GitHub repository.

      **Done** as site commit `f862b6e` and projectured-julia commit
      `79ddc44a`.

      - `<title>` and the meta titles read "ProjecturEd — one structure, many
        editable views, with an AI assistant". The `<h1>` keeps its three
        lines. The text column of the hero was 52ch wide, so the heading broke
        into six lines, as the old one did; the column is now 60rem wide, and
        the lede keeps its own width of 44ch.
      - `og:url`, `og:image` and `twitter:image` name `https://projectured.org`.
        `projectured.github.io` answers 301 to `http://projectured.org/`: the
        redirect goes to `http`, which is the setting "Enforce HTTPS" of
        GitHub Pages, for the owner.
      - The social card has the eyebrow "A projectional editor, written in
        Julia", the title, and `projectured.org`. `assets/og/og.html` says how
        to render it again.
      - In projectured-julia: the first line of the README, its introduction,
        the description and the title slide of the deck, both post titles and
        the first sentence of each post. §2.1 of the documentation rewrite
        keeps the approved texts as a record, with a note.
        `plan/pending/nlnet-application.md` also quotes the old framing, in
        its brief for the application; it is another plan, so it is not
        changed here.
      - The documentation guard (`julia test/suite/documentation.jl`) passes on
        the branch.
      - The description proposed for the GitHub repository: "One structure,
        many editable views — with an AI assistant. A projectional editor
        written in Julia: view and edit structured data, and a generic user
        interface for Julia programs." The website field: `https://projectured.org`.

### Step 6: the videos (after S0 and S11 exist)

- [ ] S0 in the hero, with a poster and a play control (W7). The poster is an
      early frame (W13). The caption follows D11 of the screenplay plan. The
      assistant picture moves to the AI section.
- [ ] A still of the last frame of S0 in "The idea" (W11, W13).
- [x] S11 in the Videos section. The card about incremental update links to it.
      S11 came from another session (site commit `839316e`); the link is in `a7622ef`.

### Step 7: after a table takes an edit (W3)

- [ ] Take "a table does not take an edit yet" out of "Lineage & status".

### Step 8: the review

- [ ] Render the page with a headless browser at desktop width and at phone
      width, in the light and the dark theme. Read every section.
- [ ] Request every link of the page and check that each one answers 200.
- [ ] The owner reads the page. The owner says when it is pushed.
- [ ] Move this plan to `plan/done/`.

## 9. Risks

- **The texts drift apart.** If only the site gets the new title, the README,
  the deck and the posts keep the old one. §3.6 lists every place.
- **A claim goes stale.** The page says what is true today. When the code
  changes (W3), the page must change too. Step 7 is for that.
- **A private name in the hero.** S0 comes from a private application. D11 of
  the screenplay plan applies to the caption and to the text of the page.
- **A long hero video.** Most visitors do not play a video of 10 min or more. So
  the poster and the title must say what the video shows without the video.
