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
4. **Done** — publish, with the owner's word for each push:
   - **Done** — the owner renamed the GitHub repository to
     `projectured/AutoIntegration.jl`; `origin` of `../auto-integration` names it.
   - **Done** — pushed: the package repository `504659a..ffd6d72`, this
     repository `2b6d5b686..8395d8bdb`, the site `14604e0..0b8f440`.
   - **Done** — the owner asked for one commit in the package repository: its
     history is the root commit `cf89407`, force-pushed. Its tree is `8f4d68f4`,
     the tree of `ffd6d72`. Its CI passes.
   - **Done** — force-pushed: the release `19fe700`, "ProjecturEd 0.1.0, from
     projectured-julia 9624b51ed", 89 packages, and the registry `f8f0451`. The
     registry has the README and the entries AutoIntegration (tree `8f4d68f4`) and
     AutoPrecompile (tree `26ee88b5`) of the registry prepared in
     `/var/tmp/release-fresh2`, then the release. The release is made again from
     `9624b51ed` and not from `8395d8bdb`, because `9624b51ed` changes two files
     that the release ships: `naming-rules.md` and the tree guard of
     ProjecturedTest. It replaces the release `18d9208` and the registry
     `11b7d77`. AutoIntegration 0.1.0 installs from the registry in an empty
     depot, and the 32 workflows of the release pass.
   - **Done** — no copy on this machine names the old package: the second clone
     `../projectured-registry` is reset to the registry, the old compiled caches
     are deleted, and the environment `../Project.toml` has a new manifest. An
     environment that installed the old 0.1.0 needs a new manifest, because the
     fresh release keeps the version 0.1.0 and Pkg keeps the old dependencies
     of `Projectured` from the manifest.
5. **Done** — the memory `autointegration-rename-landed.md`, in the index of
   landed changes: an older branch rebases, or it cannot load the umbrella.
   `projectured-julia-release` and `projectured-julia-kernel-audit-decisions`
   still name the old folder.
