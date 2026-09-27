# The web site: the title, and a page that a newcomer can follow

**Status (2026-09-27): pending, not started.** The owner chooses the title
(§3) first. The implementation starts only when the owner says so.

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

This is my recommendation. The choice is the owner's.

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

### 4.2 The review: what we do and what we do not do

The owner answered the four questions and did not comment on the other rows.
So the rows below are my recommendations, and the owner can change any of them
before Step 1.

| # | Point of the review | What we do | Why |
| --- | --- | --- | --- |
| R1 | A hero around "one structure, many views"; "projectional editor" as the main identity | The title of §3. "Projectional editor" stays in "The idea" and in the meta description. | D3, and W5. |
| R2 | The status notice before the product | Do it (W4). | |
| R3, R4 | One data with several views, as the main picture | One picture in "The idea", drawn by the editor: one document in two views that both take edits. Not two sections. | The page says that the editor draws every picture, so a hand-made diagram breaks that claim. |
| R5 | Put the AI after the projection story | Do not change the order. Delete the duplicates of §2.1. | The idea already comes before the AI section. Only the hero puts AI first. |
| R6 | A section "What can you use it for?" | Do it, from the README list "What you can do with it". | Each item of that list names code that exists. The review's list has items that nobody checked. |
| R7 | Too many cards of equal size | Four large cards, and the others in a smaller grid. | My four: several views of one data; edits are operations, for you and for the assistant; only what is on the screen is computed; your own domain. |
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
- **No hand-made diagram.** Every picture on the page comes from the editor.
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
2. The idea, with the picture of one document in two views.
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

| # | Question | My recommendation |
| --- | --- | --- |
| Q1 | Which title? | T2 (§3.3). Render the shortlist first (§3.5). |
| Q2 | S0 lasts 10 min to 25 min. How does the hero show it? | A poster that tells the story alone, and a play control. The caption gives the length. No autoplay and no excerpt (§4.3). |
| Q3 | Which four capabilities are large? | The four of R7. |
| Q4 | How is the social card made? | An HTML template in `assets/og/` of the site, rendered by a headless browser. Then the next change of the title is one edit and one command. |
| Q5 | Does the new title also replace the approved tagline in the README, the deck and the posts (§3.6)? | Yes, so that the texts stay the same everywhere. |
| Q6 | Which two views go in the picture of "The idea"? | JSON beside a sorted view of the same data, because the page already says that a sorted view takes edits. Test first that both take edits in the application. After W3, a table can replace the sorted view. |

## 7. Steps

The work goes in a git worktree of `projectured.github.io`, as a sibling in
`workspace/`. Each step is one commit, with explicit paths. A push publishes
the live site, so each push waits for the owner's word.

### Step 1: the changes that do not depend on the title

- [ ] The status line at the top (W4). Move the full text to "Lineage &
      status", and make its limits agree with "Status and limits" of the README.
- [ ] Links to `projectured-julia`: in the navigation, in the hero, and in
      "Lineage & status".
- [ ] Take "transform" out of the meta text. Add "projectional editor" and
      "Julia" to the meta description (W5).
- [ ] Delete "See it in action" (the picture is the same as the hero picture).
- [ ] Delete the duplicates of §2.1: the card "One set of operations", and the
      card "An assistant on the same data" in the capabilities.
- [ ] The headings of R13.
- [ ] The head "Build with ProjecturEd" over the examples and the catalog.

### Step 2: "Try it" and "What you can do with it"

- [ ] A "Try it" section from the quick start of the README: what it needs
      (Julia 1.11 or later, SDL2 and SDL_ttf), the three commands, the assistant
      (Ollama or `ANTHROPIC_API_KEY`), and the binary (`bin/build_projectured`).
- [ ] A section "What you can do with it", from the README list. Keep the items
      that a newcomer understands without a link.

### Step 3: the capabilities

- [ ] Four large cards (Q3), then the other cards in a smaller grid.
- [ ] The card about incremental update says the result first, with the words
      of the approved text (R8).

### Step 4: the picture of "The idea"

- [ ] Test in the application that both views of Q6 take edits.
- [ ] Draw the picture with the editor, and put it in "The idea".

### Step 5: the title (after Q1)

- [ ] Render the shortlist in the real hero (§3.5). The owner chooses.
- [ ] Change every place of §3.6 in `index.html`.
- [ ] Draw `assets/og.png` again (Q4).
- [ ] In `projectured-julia`: the first line of the README, the introduction
      (take "transform" out), the title slide of the deck, and the post drafts.
      This is one commit in that repository.
- [ ] Give the owner the new description of the GitHub repository.

### Step 6: the videos (after S0 and S11 exist)

- [ ] S0 in the hero, with a poster and a play control (Q2). The caption follows
      D11 of the screenplay plan. The assistant picture moves to the AI section.
- [ ] S11 in the Videos section. The large card about incremental update links
      to it.

### Step 7: after a table takes an edit (W3)

- [ ] Take "a table does not take an edit yet" out of "Lineage & status".
- [ ] If the owner wants it: the picture of "The idea" shows JSON and a table.

### Step 8: the review

- [ ] Render the page with a headless browser at desktop width and at phone
      width, in the light and the dark theme. Read every section.
- [ ] Request every link of the page and check that each one answers 200.
- [ ] The owner reads the page. The owner says when it is pushed.
- [ ] Move this plan to `plan/done/`.

## 8. Risks

- **The texts drift apart.** If only the site gets the new title, the README,
  the deck and the posts keep the old one. §3.6 lists every place.
- **A claim goes stale.** The page says what is true today. When the code
  changes (W3), the page must change too. Step 7 is for that.
- **A private name in the hero.** S0 comes from a private application. D11 of
  the screenplay plan applies to the caption and to the text of the page.
- **A long hero video.** Most visitors do not play a video of 10 min or more. So
  the poster and the title must say what the video shows without the video.
