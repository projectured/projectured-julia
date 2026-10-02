# A short README for each released package

## 1. Goal

An item of Part R of
[release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md):
"Each registered package has a short README." The maintainers of General ask
for it, and for documentation "written for people". The owner said "continue"
after R31 on 2026-10-02. The same part also asks that the build guide name
`ProjecturedRegistry` where it says `<registry>`; this plan does that too.

## 2. Facts (2026-10-02, `main` at `2230f5217`)

- `build_package_release!` takes `readme(name)`, and writes its text to
  `<Name>/README.md`. `_format_projectured_package_readme` gives every package
  the same text, and that text says that the source of a package is
  `package/<Name>`, which holds only the name and the include list since the
  fold.
- GitHub shows `<Name>/README.md` as the page of the package folder; it is what
  a person sees from the registry entry of a package.
- 32 packages are released. Each domain, backend and adapter has a design
  document `documentation/package/<group>/<slice>/<slice>.md`, except
  `ProjecturedDataFrames`. `ProjecturedDatabase` and `ProjecturedDBCatalog`
  share one. The kernel, the platform and the umbrella have none of their own.
- The design documents open for developers ("This document says how …"), with
  links relative to their folder, which break in a README.
- `README.md` is part of the content of a package, so a change of the README
  gives the package a new version. No release exists yet.
- The registry is `ProjecturedRegistry`, in
  `https://github.com/projectured/ProjecturedRegistry` (R10). It is private
  until the owner makes it public.

## 3. The design

A README has four parts:

1. The name, and one sentence for a person who does not know ProjecturEd:
   what the package holds or does.
2. One sentence on ProjecturEd, and a link to the document that says more,
   on GitHub.
3. The install lines: add the registry, then `add Projectured <Name>`
   (`add Projectured` for the umbrella, the kernel and the platform), and a
   sentence on what the umbrella installs and loads, with a link to the
   own-project guide.
4. Where the source is, and the licence.

The sentence and the document of each package come from one table in
`ProjecturedProgram.jl`, `PROJECTURED_PACKAGE_READMES`. A released package
without an entry stops the build, and a test checks that every entry names a
document that exists.

## 4. Decisions

| # | Question | Decision |
| --- | --- | --- |
| M1 | Where the sentence of a package comes from. | The table, written for a user (the owner, 2026-10-02: "agree"). The other way was to cut the first sentence out of the design document: one source, but the cut is fragile, the sentence is written for a developer, and five packages have no document of their own. The test catches a package without an entry. |

## 5. Steps

- [x] **Step 1, the README.** The table, the text, the check that stops the
      build, and a test: every released package has an entry, every document
      exists, and the README of one package holds its sentence, the registry
      and the install line. Done: `PROJECTURED_PACKAGE_READMES` (32 entries)
      and `PROJECTURED_REGISTRY_URL`; the test also refuses an entry for a
      package that is not released. `ProjecturedDataFrames` links the package
      index, because it has no design document.
- [x] **Step 2, the guides.** The build guide names `ProjecturedRegistry` in
      the register step. The builder document says what the README holds. The
      release plan marks the item. Done; the build guide also shows the
      `registry` keyword of the build for a local registry.

## 6. Decisions made during the work

### 6.1 The check of Step B4

The release plan holds the results: the READMEs went into a local
`ProjecturedRegistry` with the 32 packages, and each package folder held its
README. The install line of a README, `add Projectured ProjecturedJSON
ProjecturedSDL` with the SDL backend added, installed and opened a window.
