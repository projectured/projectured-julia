# ─────────────────────────────────────────────────────────────────────────────
# Checked-in DEFAULT app configuration — the v1 spec: a JSON file editor with the
# SDL backend baked in. `ProjecturedExecutable.jl` includes the generated
# `AppConfig.jl` when it exists, and falls back to this file otherwise (fresh
# checkout that has never run the builder).
#
# Mirrors `render_app_config(BuildSpec())` from Builder.jl. To build a different
# editor, call `build_executable(; …)` (which regenerates `AppConfig.jl`) rather
# than editing this file.
# ─────────────────────────────────────────────────────────────────────────────
using ProjecturedSdl

const APP_NAME            = "projectured"
const APP_DOMAIN          = :json
const APP_DOMAINS         = (:json,)
const APP_WORKBENCH       = false
const APP_FILE_BACKED     = true
const APP_BACKENDS        = (:sdl,)
const APP_DEFAULT_BACKEND = :sdl
const APP_EXPOSE_BACKEND  = false
const APP_WIDTH           = nothing
const APP_HEIGHT          = nothing
const APP_MCP             = false
