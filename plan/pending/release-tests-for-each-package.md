# The tests of each released package (R30)

## 1. Goal

Each registered package has a `test/runtests.jl` that passes when `Pkg.test`
runs it on the installed package alone. The maintainers of General ask for it,
because `Pkg.test` and PkgEval run each package alone and do not find the
`Projectured*Test` packages. This is R30 of
[release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md),
and the next item of "The work toward the local registry" in its Part R. The
owner asked for this plan on 2026-10-01, and accepted every recommendation
of §3 the same day: "I agree with your decisions, start implementing".

## 2. Facts (2026-10-01, `main` at `6519a5abd`)

**The packages.**
- The release holds 32 packages. 28 of them have a test package
  (`ProjecturedJSON` → `ProjecturedJSONTest`, `Projectured` → `ProjecturedTest`).
- `ProjecturedConsole`, `ProjecturedMCP`, `ProjecturedPDF` and `ProjecturedWeb`
  have no test package. Their tests are in the umbrella suite `ProjecturedTest`
  (`test/projectured/backend/`, `test/projectured/editor/`).

**What a test package needs.** A test package depends on example packages and
on the test packages below it, and the registry holds none of them. The
closure of these unregistered packages is wide:
- `ProjecturedFaultExample` depends on `Projectured` and on `ProjecturedExample`,
  which depends on every domain example, on `ProjecturedOllama` and on
  `ProjecturedAnthropic`.
- `ProjecturedPlatformTest` depends on `ProjecturedFaultExample`, and on the
  domains JSON, Julia and XML: five of its test files use them.
- `ProjecturedSDLTest` and `ProjecturedODBCTest` depend on `ProjecturedExample`.

So the test of `ProjecturedJSON` needs 25 unregistered packages and 24 of the
registered ones. The narrow cases are `ProjecturedKernel` (2 unregistered, 1
registered) and the adapters Anthropic, Ollama, OpenRouter and DataFrames (3
or 4 unregistered).

**Size.** The folders that the unregistered closure of one package includes
hold 4.1 to 5.3 MB (in this repository, `test/` is 4.7 MB and `example/` is
1.1 MB). A copy for each package gives about 130 MB in the release
repository. Pkg downloads the whole folder of a package, `test/` included, so
each user who adds a package also downloads its tests. On 2026-09-29 the whole
release copy, without tests, was 35 MB.

**Time.** In the CI-like run of 2026-10-01: `test_kernel()` 156 s,
`test_platform()` 423 s, a domain 10 to 45 s, the umbrella `ProjecturedTest`
2166 s. `test_integration()` is the part of the umbrella suite that only the
umbrella can run.

**Pkg.**
- A package declares its test dependencies in `[extras]` and `[targets]`, or
  in `test/Project.toml`.
- With `[extras]`, Pkg copies the `[sources]` of the package into the test
  project.
- The code of Pkg 1.13 makes the paths of `[sources]` in a test project
  absolute, from the folder of that project (`abspath!` in
  `Operations.jl`). That suggests that `test/Project.toml` can name a package
  inside the package folder by a path. Nothing proves it yet, on 1.13 or on
  1.11, the oldest Julia of the release.

**The environment.** The CI of Part P runs every test package with
`SDL_VIDEODRIVER=offscreen` and with no network. They pass, except the known
failures of the umbrella suite.

## 3. Decisions

The owner accepted each recommendation on 2026-10-01.

| # | Question | Decision |
| --- | --- | --- |
| T1 | What does the release test of a package run? | The suite of its test package, unchanged (`test_json()` for `ProjecturedJSON`), so that the release runs the tests of the development repository. A second, smaller suite for the release would be a second thing to keep. |
| T2 | How does the release test get the code of the unregistered packages? | The release copy writes each one into the test folder of the package as a package of its own, `test/support/<Name>/`, and `test/Project.toml` names it by `[sources]`. If Step 0 shows that Pkg does not read those `[sources]`, `runtests.jl` includes the copied files as modules instead. Registering the test and example packages is no choice: the maintainers of General refuse them, and R34 moves the packages to General later. |
| T3 | Make the closure narrow first? | Yes, in the development repository and before the generator: `ProjecturedFaultExample` must not depend on `Projectured` or `ProjecturedExample`, and the five domain files of `ProjecturedPlatformTest` move up to the test packages of their domains. Each test package then needs the packages below it only, which `CLAUDE.md` already says of them. It is a change to the test layout with its own plan; measure the closure and the size again after it. |
| T4 | How large can the test folder of a package be? | Decide after T3, with the numbers. |
| T5 | What does the test of `Projectured` run? | `test_integration()`, not the whole umbrella suite: the other parts are the tests of the other packages, and the whole suite takes 36 minutes. |
| T6 | Console, MCP, PDF and Web, which have no test package? | A test package for each, with its tests moved out of `ProjecturedTest`, as T3 does for the platform. Until then, a `runtests.jl` that loads the package and checks one call. |
| T7 | The environment of a release test? | `runtests.jl` sets `SDL_VIDEODRIVER=offscreen` when it is not set. A test that needs the network or a database already passes without them, as the CI of Part P shows. |

## 4. Steps

- [x] **Step 0, the prototype.** By hand, under `/var/tmp`: give the release
      copy of `ProjecturedKernel` a `test/` folder with `ProjecturedKernelTest`
      and `ProjecturedKernelExample` in `test/support/`, a `test/Project.toml`
      that names them by `[sources]`, and a `runtests.jl` that calls
      `test_kernel()`. Register it in a local registry, and in an empty depot
      run `add ProjecturedKernel` and `test ProjecturedKernel` on Julia 1.13
      and 1.11. Record whether Pkg reads those `[sources]`, the size, and the
      time.
      Done on 2026-10-01 (`/var/tmp/r30/p0/`, scripts `make.jl`, `user.jl`,
      `run-all.sh`):
      - **Pkg reads the `[sources]` of `test/Project.toml` for an installed
        package**, on Julia 1.13 and on 1.11. `Pkg.test` found
        `test/support/ProjecturedKernelTest` and `…Example` inside the
        installed folder, from a registry entry with `subdir`. So T2 holds,
        with no fallback.
      - Size: the test folder adds 0.9 MB to the 3.7 MB of the kernel.
      - Time, with an empty depot: 253 s on 1.13 (precompile and
        `test_kernel()`), 217 s on 1.11.
      - The builder rewrites only the include prefix `../../../source/`; a
        support package includes `test/` and `example/` too, so the generator
        must rewrite any of the three.
      - The scan of the copy reports two paths through `pathof` in the kernel
        tests. Both read the include lines of the entry file, which work in the
        release layout too, so the scan of a test folder must accept them.
      - Two kernel tests assumed the development checkout, and are fixed:
        `MeaningSearchTest.jl` expected the meaning folder `build/meaning`,
        which is right for a checkout only (an installed package uses the
        cache folder of the user); `CellStructPlanTest.jl` wrote a field
        docstring on one line, which the parser of Julia 1.11 refuses.
      - Result: 1.13 passes (4059 passed, 2 broken). **1.11 fails 2
        assertions**, `CellTest.jl:97-98`: after `GC.gc(true)` twice, a
        discarded cell is still alive. Open: a test that depends on the
        collector of one Julia version, or a real leak on 1.11. The bound of
        R13, `julia = "1.11"`, was checked with `add` and `using` only.
- [x] **Step 1, the narrow closure (T3, T6).** Its own plan, if the owner
      agrees.
      Done: [narrow-test-closure.md](narrow-test-closure.md).
- [x] **Step 2, the generator.** `build_package_release!` writes the test
      folder of each package: the unregistered closure in `test/support/`,
      with the include prefixes changed as for `source/`; `test/Project.toml`
      with the registered dependencies, their `[compat]` bounds and the
      `[sources]` of the support packages; and `runtests.jl`. The test
      packages of each released package come from `context`, by the rule of
      the name (`<Name>Test`).
      Done (`b9f1ae5a0`). `build_package_release!` takes `tests`, a function
      that answers the test package and the text of `runtests.jl`;
      `build_projectured_package_release!` gives `<Name>Test` and
      `test_<name>()`, and for the umbrella `ProjecturedTest` and
      `test_integration()`. The support packages are the unregistered closure
      of the test package; a path of the repository in their `src/`
      (`"../../../`) becomes one of the copy, for `include` and for
      `joinpath(@__DIR__, …)`, and the folders those paths name come along.
      What was found on the way:
      - A support package reads files of the repository too. The asset table
        names them, and an entry may now be one file: two images for the
        platform example, one for the Markdown test, the recording driver for
        the SDL keysym test, and `test/suite` for the umbrella test package.
        `asset/image` as a whole is 4.9 MB, nearly all of it the generated
        screenshots that nothing reads.
      - The scan reports the kind of each finding (`:include`, `:path`,
        `:form`). In `test/`, a form that it can not follow and a runtime path
        inside the package that names nothing are left to the tests, which
        Step 4 runs; an `include` that names nothing, and any path that leaves
        the package, still stop the build.
      - **A change of a test gives no package a new version** (Decision 1, the
        owner, 2026-10-01): the content of a package leaves `test/` out, and a
        released folder keeps the tests of its version until the package
        itself changes.
      - **T5 changed** (Decision 2, the owner, 2026-10-01): `test_integration()`
        held three tests that read the repository. `test_package_graph()` is now
        `test_repository()`, which CI runs as a job of its own, and the builder
        tests are the test package `ProjecturedBuilderTest` (`test_builder()`;
        the binary tests are `test_build_executable()`), so the umbrella test
        package no longer loads the builder and its fonts.
      - Size (bytes): the release copy is 91.3 MB with the tests, against 35 MB
        without them on 2026-09-29. The 32 test folders hold 56.1 MB: 0.7 MB for
        the kernel, about 2.1 MB for a domain, 4.2 MB for the umbrella. Of the
        2.1 MB of a domain, 1.8 MB is the copy of the kernel and platform test
        packages, and 0.04 MB its own tests. This is the number for T4.
- [x] **Step 3, the test.** `test_package_release()` checks the test folder
      of a fixture package, and that its `Pkg.test` passes.
      Done (`5cfa55ffe`): the fixture has a test package and an example
      package for `FakeTop`; the test checks the folder, the `[sources]`, the
      include prefix, a file a test reads, and that a change of a test gives no
      new version. `test_builder()` passes 386 of 386. The `Pkg.test` of a
      package is in Step 4, because the fixture depends on a package that no
      registry holds.
- [ ] **Step 4, the full check.** In an empty depot with a local registry,
      `Pkg.test` for each of the 32 packages; record the size and the time.
- [ ] **Step 5, the guides.** `builder.md` and `build-guide.md`.

## 5. Decisions made during the work

(filled in as the work goes)
