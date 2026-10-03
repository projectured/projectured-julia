# Rename AutoIntegrations to AutoIntegration

The owner, 2026-10-03: rename the package AutoIntegrations to AutoIntegration,
and its folder beside this checkout too. Nothing is announced yet, so the
registry and the release take the new name with a fresh overwrite.

## What stays

- The uuid `40fd747d-4b08-4b8c-98c4-74a2b6295b1b` and `set_auto_integration!`.
- The table `[auto-integration]` in the `Project.toml` of an integration; it is
  singular already.
- The plans: they are history.

## What changes

| place | what |
| --- | --- |
| the package repository | the name, the module, `src/AutoIntegration.jl`, the README, the test, the licence line, and the table of `LocalPreferences.toml` that it reads, `[AutoIntegration]` |
| the folder beside this checkout | `auto-integrations` becomes `auto-integration` |
| this repository | the `import` of the umbrella, its `[deps]` and `[sources]`, the two environments, the builder (`AUTOINTEGRATION_URL`, the front page, the README of a package, the release workflow), the CI step that places the package, a comment in 30 `Project.toml` files, two tests, about 20 guides, and the guide folder `documentation/package/autointegration/` |
| the statement files | 4 lines of the recording "readme-data-frame" name the module; record it again |
| GitHub | the repository becomes `projectured/AutoIntegration.jl`; GitHub sends the old address to the new one |
| the registry and the release | a fresh overwrite with the new name |
| the site | 2 lines |

## Steps

1. **Done** — the package repository: commit `ffd6d72`, landed on its `main`, not
   pushed. The entry file is `src/AutoIntegration.jl`, and the table of
   `LocalPreferences.toml` that it reads is `[AutoIntegration]`. Its test: 22 of
   22.
2. **Done** — this repository: commit `78232fc98`, 62 files. The four forms
   `AutoIntegrations`, `AUTOINTEGRATIONS_URL`, `autointegrations` and
   `auto-integrations` were replaced outside the plans and the statement files;
   `auto-integration` and `auto_integration` stay. The guide moved to
   `documentation/package/autointegration/autointegration.md`. The recording
   "readme-data-frame" was made again: its 4 lines name `AutoIntegration`, and
   the platform and the kernel gained 44 lines from the code of other sessions.
   Tests: the four of `IntegrationLoadingTest.jl`, `test_package_graph`,
   `test_naming`, `test_documentation` and `test_package_release`, 665 of 665.
3. **Done** — landed on `main`, and the folder moved to `../auto-integration`.
4. Publish, with the owner's word for each push:
   - rename the GitHub repository to `projectured/AutoIntegration.jl`, and set
     the address of `origin` in `../auto-integration`;
   - push `main` of the package repository and of this repository;
   - push the site: commit `0b8f440` on the branch `rename-autointegration` of
     `projectured.github.io` (worktree `../projectured.github.io-rename`), three
     lines of `index.html`;
   - a fresh release and registry, with AutoIntegration registered first, then
     AutoPrecompile as it is registered, then the release; the README of the
     registry names `AutoIntegration.jl`. The owner force-pushes both.
5. **Done** — the memory `autointegration-rename-landed.md`, in the index of
   landed changes: an older branch rebases, or it cannot load the umbrella.
   `projectured-julia-release` and `projectured-julia-kernel-audit-decisions`
   still name the old folder.
