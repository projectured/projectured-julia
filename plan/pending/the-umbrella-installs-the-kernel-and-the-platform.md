# The umbrella installs the kernel and the platform only

## 1. Goal

The owner, 2026-10-02: "I think it should only install automatically the
platform and the kernel, no? So if somebody installs DataFrames,
SimpleDirectMediaLayer and Projectured then she doesn't get all kinds of stuff
she didn't ask for." The owner accepted way (B) the same day ("Yes"):

- `add Projectured` installs `ProjecturedKernel` and `ProjecturedPlatform`, and
  nothing more.
- `using Projectured` loads every ProjecturEd package that the user installed:
  each domain, the console and PDF backends, the model adapters with no trigger,
  and the integrations of
  [umbrella-loads-installed-integrations.md](../done/umbrella-loads-installed-integrations.md)
  when their trigger is loaded too.
- The flat namespace of every package moves to a development package that the
  registry does not hold.

## 2. Facts (2026-10-02, `main` at `7cc4bf5c8`)

- The `[deps]` of the umbrella are 21 ProjecturEd packages: the kernel, the
  platform, `ProjecturedConsole`, `ProjecturedPDF` and the 17 domains. With the
  5 standard libraries, that is its whole closure; none comes from General.
- `source/projectured/Projectured.jl` builds the flat namespace: it re-exports
  the names of every package in `_SOURCES`, which are the `[deps]`. A package can
  export only the names of what it loads itself, so an umbrella of the kernel and
  the platform exports only their names.
- The flat namespace has users: in this repository `ProjecturedTest`,
  `ProjecturedExample`, `ProjecturedFaultExample`, `ProjecturedODBCExample`,
  `ProjecturedTulipExample`, `ProjecturedAdaptagramsExample`, `ProjecturedREPL`
  and `ProjecturedBench`; downstream, 70 files in omnet-julia and 9 in inet-julia
  have `using Projectured`.
- The umbrella already loads the installed model adapters after the load of the
  session, through `Base.package_callbacks`, because an `__init__` inside a load
  can not load a package of the same load.
- The binary lists its packages: `Projectured`, the model adapters, MCP and the
  backends. It gets the domains through the umbrella today.

## 3. The design

- **`Projectured`** depends on the kernel and the platform. Its namespace is
  theirs. Every other ProjecturEd package of the release is a weak dependency,
  for its `[compat]` bound. After the load of the session, the umbrella loads
  each one that the environment of the session has: the domains, the console,
  PDF and the model adapters. The six integrations with a trigger stay as they
  are.
- **The development package** holds the flat namespace of every package, as the
  umbrella does today; it is the `using` of the tests, the examples, the REPL
  and the downstream repositories. The registry does not hold it.
- **The binary** names its domains, the console and PDF in its package list.
- **A user who wants the names of a domain** loads it: `using ProjecturedJSON`.

## 4. Decisions

The owner accepted the three recommendations on 2026-10-02 ("Agreed, start").

| # | Question | Decision |
| --- | --- | --- |
| U1 | The name of the development package. | `ProjecturedAll`: it says what it holds, and it is not a name a user of the registry meets. |
| U2 | Downstream: change `using Projectured` to the development package, or to the packages each file uses? | The development package now: one mechanical change in 79 files. Naming the packages is a change of its own, file by file, later if at all. |
| U3 | Measure the precompile and the load of `using Projectured` before and after? | Yes, the same way as the fold measured them: both commits in one session at the end, a fresh clone and an empty compiled folder for each. |

## 5. Steps

- [x] **Step 1, the development package.** `ProjecturedAll` with the flat
      namespace of today; `environment/all` names it. Done in `3d8dc8e10`. Its
      loop is `source/all/ProjecturedAll.jl`, not in `source/projectured/`: the
      package-graph test finds the owner of a folder by its source, and two
      packages in one folder made that test mix them.
- [x] **Step 2, its users.** The eight packages here and 18 test and tool
      scripts change to it, by `julia-rename.jl`. Done in `3d8dc8e10`. The code
      tool of the assistant changes too: see 6.2.
- [x] **Step 3, the umbrella.** `[deps]` the kernel and the platform, the rest
      `[weakdeps]` without `[sources]` (Pkg refuses them), and the load of every
      installed package after the load, through the callback of the model
      adapters. Done in `3d8dc8e10`.
- [x] **Step 4, the binary.** `PROJECTURED_APPLICATION_IMPORTS` names the
      console, PDF and the 17 domains. Done in `3d8dc8e10`; the binary built in
      493 s and passed its check.
- [x] **Step 5, the test of the two ways.** JSON stands for the domains: it
      loads with the umbrella in `environment/all`, and it does not load in the
      environment that names only the umbrella and a trigger. Done in
      `3d8dc8e10`.
- [x] **Step 6, downstream.** omnet-julia `61d6f6a0` (120 files) and
      inet-julia `d0519bf` (24 files), on branches `umbrella-core`; both
      precompile with 0 errors against this branch.
- [x] **Step 7, the guides.** The own-project guide, the setup, testing and
      debugging guides, the system anatomy, the package and architecture rules,
      the division terminology, the domain inventory, the new-domain guide, and
      the editor, application, kernel architecture and builder documents. The
      README and `CONTRIBUTING.md` need no change: their sessions call only names
      of `ProjecturedExample`. `architecture-invariants.md` is sealed and stays;
      its direction `kernel → platform → domain → umbrella` is still true.

## 6. Decisions made during the work

### 6.1 Each domain package exports its names

Before this change, the root module of a domain package exported nothing: the
names reached a user only through the flat namespace of the umbrella. With an
umbrella of the kernel and the platform, `using Projectured, ProjecturedJSON`
gave no `JsonString`. The owner agreed on 2026-10-02 ("I agree with the
reexport"): each of the 17 root modules does `using .<Domain>Module` and exports
every name of it, as `ProjecturedPlatform` exports the names of `PlatformModule`.
Commit `4d5070acd`. `ProjecturedAll` still loads beside them, with 6113 names.

### 6.2 The code tool imports every loaded ProjecturEd package

`execute_julia_code` ran in a scratch module with `using Projectured`, which
gave every name. It now imports every loaded `Projectured*` package that is not a
test or an example package, re-exports their names, and binds `Projectured` to
the scratch module itself. So `Projectured.JsonObject` keeps working in the code
that a model writes, although the umbrella does not export that name.

### 6.3 Three lists name the full set, and two tests keep them equal

The `_SOURCES` of `ProjecturedAll`, the `_INSTALLED_PACKAGES` of the umbrella and
`PROJECTURED_APPLICATION_IMPORTS` of the builder each name the packages above the
kernel and the platform. A domain that one list misses does not load with the
umbrella, or is not in the binary, and nothing reports it. So
`test_umbrella_names_every_package()` (in `test_repository()`) and a test of
`test_builder()` compare each list with the `[deps]` of `ProjecturedAll`; the
first also checks that each installed package is a weak dependency of the
umbrella. One list read at precompile time from the `Project.toml` was the
alternative; the explicit tuples are easier to read, and the tests close the gap.

### 6.4 The code tool leaves the aggregates out of its surface

With every loaded package on the surface, `KernelModule` and `PlatformModule`,
which gather the layers and the slices, came first in the order of the names, so
`search_api` answered `ReplaceSelectionOperation` as a type of `KernelModule`
and a search for `^OperationModule\.Replace` found nothing. A submodule that
exports names and defines none of them is now left out, so each name counts
under the module that defines it, as it did when the umbrella was the surface.
The test reads only the names whose value is not a module: the name of a
gathered module reaches the aggregate through two imports, and `which` throws
for it. No other exported name of the 365,924 is ambiguous. Naming the two
aggregates, as the loop of `ProjecturedAll` does, was the alternative; the
kernel would then name a module of the platform.

### 6.5 Faults found on `main`, not of this change

Each one fails the same way on `main` at `aa7ce9223`:

- `test/kernel/projection/RoutedChangeTest.jl:199`, from the gesture work.
- The exports guard: 4 blocks of the application, settings and settings
  managing slices are not in the order of definition.
- `test_catalog_coverage()`: seven types of the drag, settings, tooltip and
  context menu work are not in the catalog.
- `test_history_sweep()`: `chart_inspector` and `sequencechart_inspector`
  record `MouseMove`.
- `test_table_cell_editing()`: a typed character in a JSON string cell gives no
  operation.
- `test_click_roundtrips()` inside the full `test_integration()`: three
  `@test_broken` markers at `ClickRoundtripTest.jl:323` pass. Alone, the sweep
  keeps them broken.
- The arguments guard: 6 findings.

## 7. Measurements (U3)

Both commits in one session on 2026-10-02, a fresh clone and an empty depot for
each case, CPUs 28, 30 and 31, `JULIA_NUM_PRECOMPILE_TASKS=3`. The machine was
not idle: the load average was 4 to 8 from other sessions. The five loads of a
case differ by 0.04 s at most; the table gives their middle value.

| Case | `main` `aa7ce9223` | branch `8901d6c1e` |
| --- | --- | --- |
| `environment/all`: precompile | 246 s, 275 files, 531 MB | 244 s, 276 files, 533 MB |
| `environment/all`: load `using Projectured` | 2.59 s | 2.60 s |
| `environment/all`: load `using ProjecturedAll` | — | 2.37 s |
| Only `Projectured`: packages in the manifest | 27 | 8 |
| Only `Projectured`: precompile | 30 s, 22 files, 78 MB | 17 s, 3 files, 47 MB |
| Only `Projectured`: load | 2.44 s | 0.18 s |
| `Projectured` and `ProjecturedJSON`: packages | 27 | 9 |
| `Projectured` and `ProjecturedJSON`: precompile | 31 s, 22 files, 78 MB | 18 s, 4 files, 48 MB |
| `Projectured` and `ProjecturedJSON`: load | 2.42 s | 0.25 s |

The kernel loads in 0.03 s and the platform in 0.12 s on both. In
`environment/all`, `using Projectured` loads every installed package, so it costs
what the flat namespace costs. The script is `/var/tmp/r30/times/measure.sh`.

## 8. The final check

`ci14`, 2026-10-02, a fresh clone of `5a1499df9` (on `main` `0d17c1385`), every
CI job in its own environment, in `unshare -rn`:

- The 32 package suites pass, except the kernel fault of 6.5.
- `test_repository()` 370 of 370; `test_builder()` 381 of 381.
- `test_integration()` and the guards give exactly the failures of a fresh clone
  of `main` at `ce541bf1f`, which 6.5 lists.
- omnet-julia and inet-julia precompile with 0 errors against the branch.
