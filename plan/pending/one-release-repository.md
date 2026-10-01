# One release repository with a folder for each package

## 1. Goal

The release copy of the packages is one git repository, `projectured/Projectured.jl`,
with one folder for each package, `<Name>/`. This is R23 of
[release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md),
which the owner decided on 2026-10-01: "I choose the single
projectured/Projectured.jl repository". It is the second item of "The work
toward the local registry" in Part R of that plan.

## 2. Facts (2026-10-01, `main` at `8013a1eed`)

- `build_package_release!` in `source/tool/builder/PackageRelease.jl` writes one
  repository for each package, `<output>/<Name>.jl`, with the package at its
  root (commit `6571ceed9`, 2026-09-29). It checks each repository for an
  uncommitted change, and it replaces every file of a changed repository but
  its `.git`.
- Before that commit, it wrote the form that Steps B1 and B4 tested: one folder
  for each package in `output`, the licence files at the root of `output` too,
  and one check for an uncommitted change in `output`. Step B4 registered each
  package with `register(joinpath(output, name); registry, repo)`, and
  LocalRegistry found the folder of the package in the repository by itself.
- AutoMerge of General does not apply the rule of the repository name to a
  package in a subdirectory (§3.3 of the release plan). Registrator takes the
  folder as `subdir=<Name>` in the comment `@JuliaRegistrator register`.
- `build_projectured_package_release!` gives each package a README through
  `readme`; its text says "this repository".
- `registry` of `build_projectured_package_release!` defaults to `"General"`.
- The test is `test_package_release()` in
  `test/tool/builder/PackageReleaseTest.jl`. The guides are
  `documentation/package/tool/builder/builder.md` ("The release copy") and
  `documentation/guide/build-guide.md` ("Release the packages").

## 3. The design

`output` is the working tree of the release repository:

```
Projectured.jl/          one git repository
  LICENSE                the licence files, also at the root
  ProjecturedKernel/     one folder for each package
    Project.toml
    README.md
    LICENSE
    src/ProjecturedKernel.jl
    source/kernel/…
  ProjecturedJSON/
  …
```

- **A package folder is the unit of a version.** A registry names a version by
  the tree of the folder. A package whose content did not change keeps its
  folder byte for byte, so its tree and its version stay.
- **The build changes only what it owns:** the folder of each changed package,
  and the licence files at the root. Another file at the root, such as a README
  or a CI workflow, stays as it is.
- **The last release is what the last commit of the repository holds.** An
  uncommitted change anywhere in `output` stops the build.
- **The README of a package** names the folder, not a repository.
- **`registry` keeps its default `"General"`.** A release for a local registry
  passes the name or the folder of that registry; the build guide says so.

## 4. Steps

- [x] **Step 1, the generator.** `build_package_release!` writes
      `<output>/<Name>/`, copies the licence files to the root, checks
      `output` once for an uncommitted change, and replaces the folder of each
      changed package. The digest no longer skips a `.git`. The README of
      `build_projectured_package_release!` names the folder. The docstrings
      follow.
      Done: the two private helpers of the repositories,
      `_get_release_repository` and `_replace_release_content!`, are gone; the
      build removes and copies the folder of a changed package, and copies the
      licence files to the root after every package passed.
- [x] **Step 2, the test.** `test_package_release()` checks the layout, the
      licence files at the root, the git history in one repository, a file at
      the root that the build does not own, and the refusal of an uncommitted
      change.
      Done: `test_package_release()` passes 45 of 45, and the release copy of
      this repository 93 of 93 (run with `environment/build` and the test file
      alone). After a change of `FakeTop`, `git status` of the release
      repository shows exactly `FakeTop/Project.toml` and
      `FakeTop/source/faketop/FakeTopCode.jl`; a `README.md` at the root stays.
      The guards find only the four argument findings of `main`.
- [ ] **Step 3, the guides.** `builder.md` and `build-guide.md` describe one
      repository; the registration names the folder, with LocalRegistry and
      with Registrator.
- [ ] **Step 4, the release plan.** The second item of Part R is done.

## 5. Decisions made during the work

(filled in as the work goes)
