# The CI workflow of the release repository (R31)

## 1. Goal

Item R31 of [release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md),
Part R: "The release copy writes a workflow that runs `Pkg.test` for each
package with coverage. The CI of Part P stays as the check of the development
repository." The owner started it on 2026-10-02 ("yes").

## 2. Facts (2026-10-02, `main` at `a1a608045`)

- `build_package_release!` writes one folder for each package into the release
  repository, and the licence files at its root. It owns nothing else there.
  It already takes two functions of the caller: `readme(name)` and
  `tests(name)`.
- A released package has no `[sources]`: it reaches its siblings through a
  registry. A push to the release repository comes before the registration of
  its new versions, so a CI job that adds the siblings from the registry would
  test the last registered release, not the commit, and a new `[compat]` bound
  would not resolve.
- So a job develops the folders of the siblings into one environment and runs
  `Pkg.test` there, as repositories with many packages do (Makie, for one).
  The sandbox of `Pkg.test` keeps a developed folder only when the manifest of
  the environment reaches it (see 6.1).
- `Pkg.test(name)` needs every released package that `name`, its
  `test/Project.toml` and its support packages in `test/support/` depend on,
  and theirs in turn. A support package names a released sibling without
  `[sources]` (R30), so that sibling must be developed too.
- `Pkg.test` refuses a package without `test/runtests.jl`; such a package gets
  no job. Today every one of the 32 released packages has its tests (R30).
- The code of a released package is in `src/`, `source/` and, for the
  umbrella, `ext/`.
- The CI of the development repository (Part P) uses `actions/checkout@v7`,
  `julia-actions/setup-julia@v3`, `julia-actions/cache@v3`,
  `julia-actions/julia-processcoverage@v1` and `codecov/codecov-action@v7`
  with OIDC, `SDL_VIDEODRIVER=offscreen` and 180 minutes for a job.
- `PROJECTURED_JULIA_COMPAT` is `"1.11"`: every released package says it runs
  on Julia 1.11.
- The release repository is private until the owner makes it public (Part R).
  A private repository pays for its minutes of GitHub Actions; a public one
  does not.

## 3. The design

- **The generator** takes a third function, `workflow(jobs)`, and writes its
  text to `.github/workflows/CI.yml` at the root of the release repository,
  which the build then owns too. `jobs` holds one `(name, develop, coverage)`
  for each package with a `test/runtests.jl`, in the order of the release:
  `develop`, the folders of the packages that its test needs, itself included,
  dependencies first; `coverage`, its code folders. The generator computes both
  from the folders as the release leaves them, so a package that did not
  change and keeps its old tests gets the closure of those tests.
- **The workflow of this repository** (`ProjecturedProgram.jl`) has one job
  for each package and Julia version. A job develops `develop` into a new
  environment, runs `Pkg.test(name; coverage = true)`, and sends the coverage
  of `coverage` to Codecov with the name of the package as its flag. It runs on
  a push to `main`, on a pull request and by hand.

## 4. Open decisions

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| D1 | The Julia versions of the matrix. | `1.11` and `1`: the packages promise 1.11, and only a test on it keeps that promise true. It doubles the jobs, 64 for a push; while the repository is private, that costs minutes of the owner's account. With `1` alone, 32 jobs. On 1.11 the kernel suite fails 2 more assertions today, the garbage-collector test of `CellTest.jl:97-98` (a fault of `main` on 1.11), so the 1.11 jobs that run it are red until it is fixed or marked. |

## 5. Steps

- [x] **Step 1, the generator.** The keyword `workflow`, the closure and the
      coverage folders of each job, the file at the root, the docstring. A
      test with the made packages: the jobs, their order, a package without
      tests, a release that keeps an unchanged folder. Done: the jobs come from
      the folders after the copy (`_write_release_workflow`), and
      `_collect_release_test_closure` reads the package, its test project and
      each support package. The fixture also checks a sibling that only a
      support package names. `test_package_release()` 60 of 60.
- [x] **Step 2, the workflow of this repository.** Its text, the constant of
      D1, and a test: the YAML parses, it has one job for each released
      package, and each job's `develop` holds the packages that its test
      project names. Done: `_format_projectured_release_workflow` and
      `PROJECTURED_CI_JULIA_VERSIONS` (`["1.11", "1"]` until D1 is decided).
      The test reads the text, because the builder has no YAML parser; PyYAML
      parsed the generated file by hand: 32 packages, 2 versions, the folded
      `run` lines join into one command each. The umbrella develops 31 folders.
- [x] **Step 3, the check.** Generate the release copy of this repository under
      `/var/tmp`, and run the commands of the workflow for three jobs, each in
      an empty compiled cache: `ProjecturedKernel`, `ProjecturedJSON` and the
      umbrella, whose test needs almost every package. The coverage files must
      appear in the folders that the job names. Done on 2026-10-02 with
      `/var/tmp/r31/job.sh`: the `run` lines of the generated YAML, a fresh copy
      of the release, an empty compiled cache, no network:
      - `ProjecturedKernel`, Julia 1.13: 4129 pass, 1 fail (`RoutedChangeTest`,
        a fault of `main`); 99 coverage files in `src` and `source`.
      - `ProjecturedKernel`, Julia 1.11: also the 2 assertions of D1.
      - `ProjecturedJSON`, Julia 1.13: 225 of 225, 11 folders developed.
      - The umbrella, Julia 1.13: 86 folders; `test_integration()` gives exactly
        the faults of `main` (6 fail, 4 error), in 60 minutes. No coverage file
        in its folders: see 6.3.
- [ ] **Step 4, the guides.** The build guide says that the release repository
      tests itself, and what the owner turns on: the Codecov app for
      `projectured/Projectured.jl`. The release plan marks R31.

## 6. Decisions made during the work

### 6.1 A job develops the support packages too

The first check failed for `ProjecturedJSON` and the umbrella before any test
ran: "Could not use exact versions of packages in manifest, re-resolving", then
"ProjecturedPDF has no known versions". The sandbox of `Pkg.test` keeps the
versions of the environment only for the packages that it reaches through the
environment's manifest. Only `test/Project.toml` names a support package, by
`[sources]`, so a released sibling that only a support package needs
(`ProjecturedPDF` for `ProjecturedJSONExample`) was dropped and resolved again
from the registry. A job now also develops the folders of its support packages,
and the JSON job passed by hand, 225 of 225.

### 6.3 The test of the umbrella does not load the umbrella

The released test of `Projectured` is `ProjecturedTest` with
`test_integration()`, and `ProjecturedTest` loads `ProjecturedAll`, not
`Projectured`. So its job writes no coverage file in `Projectured/`: the
release tests the flat namespace and never the umbrella. This came with R30;
the coverage of this workflow shows it. Open: a fix is a question for the owner.

### 6.2 What the coverage of a job holds

`Pkg.test(name; coverage = true)` writes coverage for every file under the
folder of `name`, its `test/support/` included. The job sends only `src`,
`source` and `ext` to Codecov, so the coverage is of the code of the package.
