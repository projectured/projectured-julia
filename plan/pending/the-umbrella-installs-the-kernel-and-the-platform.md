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

## 4. Open decisions

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| U1 | The name of the development package. | `ProjecturedAll`: it says what it holds, and it is not a name a user of the registry meets. |
| U2 | Downstream: change `using Projectured` to the development package, or to the packages each file uses? | The development package now: one mechanical change in 79 files. Naming the packages is a change of its own, file by file, later if at all. |
| U3 | Measure the precompile and the load of `using Projectured` before and after? | Yes, the same way as the fold measured them, with the owner's word for the run. |

## 5. Steps

- [ ] **Step 1, the development package.** `ProjecturedAll` with the flat
      namespace of today, from `source/projectured/`; `environment/all` names it.
- [ ] **Step 2, its users.** The eight packages here change to it; the guards
      and the suites of the umbrella, the examples and the REPL pass.
- [ ] **Step 3, the umbrella.** `[deps]` the kernel and the platform, the rest
      `[weakdeps]`, and the load of every installed package after the load.
- [ ] **Step 4, the binary.** Its package list names the domains, the console
      and PDF; build and check.
- [ ] **Step 5, the test of the two ways.** The integration test adds the
      domains: an installed domain loads with the umbrella, and one that is not
      installed does not.
- [ ] **Step 6, downstream.** omnet-julia and inet-julia, on branches of their
      own, land together with this one.
- [ ] **Step 7, the guides.** The own-project guide, the setup guide, the
      system anatomy, the testing guide and the README.

## 6. Decisions made during the work

(filled in as the work goes)
