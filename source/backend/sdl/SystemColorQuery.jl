# Fragment of `SdlModule` — the colour settings of the operating system: the query
# of each system, the answer at start, and a new query when a window gets the focus.

# The longest wait for the answer of the system: at start, before the first print,
# and in the task that a window starts when it gets the focus.
const _SYSTEM_COLORS_START_LIMIT = 0.5
const _SYSTEM_COLORS_QUERY_LIMIT = 1.0

"""
    find_system_colors(backend::SdlBackend) -> SystemColors or nothing

The colour settings of the operating system: on Linux from `gsettings` on a GNOME
desktop and from the settings portal on another one, on Windows from the registry
and the window manager, and on macOS from `defaults`. `nothing` when the system
does not answer within half a second. The backend keeps the answer, and when a
window of the backend gets the focus, it asks again in a task and reports a
different answer as a `SystemColorsChange`.
"""
function BackendModule.find_system_colors(backend::SdlBackend)
    colors = _read_system_colors(_SYSTEM_COLORS_START_LIMIT)
    colors === nothing || (backend.system_colors = colors)
    colors
end

# Ask the system again in a task, unless a query runs already. A different answer
# waits in `system_colors_change` for `take_from_devices!`, and a wake ends the wait
# of the editor for it.
function _start_system_colors_query!(backend::SdlBackend)
    task = backend.system_colors_task
    (task === nothing || istaskdone(task)) || return nothing
    backend.system_colors_task = @async begin
        colors = _read_system_colors(_SYSTEM_COLORS_QUERY_LIMIT)
        _report_system_colors!(backend, colors)
    end
    nothing
end

# Keep `colors` as the answer of the system and report it, when it is an answer and
# differs from the one that the backend holds.
function _report_system_colors!(backend::SdlBackend, colors)
    (colors === nothing || colors == backend.system_colors) && return nothing
    backend.system_colors = colors
    backend.system_colors_change = WindowInput(:none, SystemColorsChange(colors; time = time()))
    wake_backend!(backend)
    nothing
end

# The colour settings of the system on which this process runs, or `nothing`. A
# query that fails gives `nothing` too: the colours then stay as they are, and the
# editor goes on.
function _read_system_colors(limit::Real)
    try
        Sys.iswindows() ? _read_windows_colors() :
        Sys.isapple() ? _read_macos_colors(limit) :
        Sys.islinux() ? _read_linux_colors(limit) : nothing
    catch
        nothing
    end
end

# ── Linux ───────────────────────────────────────────────────────────────────

# GNOME keeps the settings in `gsettings`, which answers at once. Another desktop
# gives them through the settings portal, a call over D-Bus that can wait. A
# process that does not know its desktop reads `gsettings` first, and the portal
# when `gsettings` does not answer.
function _is_gsettings_desktop()
    desktop = uppercase(get(ENV, "XDG_CURRENT_DESKTOP", ""))
    isempty(desktop) || occursin("GNOME", desktop)
end

function _read_linux_colors(limit::Real)
    if _is_gsettings_desktop() && Sys.which("gsettings") !== nothing
        colors = _read_gsettings_colors(limit)
        colors === nothing || return colors
    end
    Sys.which("gdbus") === nothing && return nothing
    text = _read_command_output(Cmd(["gdbus", "call", "--session",
                                     "--dest", "org.freedesktop.portal.Desktop",
                                     "--object-path", "/org/freedesktop/portal/desktop",
                                     "--method", "org.freedesktop.portal.Settings.ReadAll",
                                     "['org.freedesktop.appearance']"]), limit)
    text === nothing ? nothing : _convert_portal_answer(text)
end

function _read_gsettings_colors(limit::Real)
    read_key(schema, key) = _read_command_output(`gsettings get $schema $key`, limit)
    scheme = read_key("org.gnome.desktop.interface", "color-scheme")
    scheme === nothing && return nothing
    _convert_gsettings_answers(scheme, read_key("org.gnome.desktop.a11y.interface", "high-contrast"),
                               read_key("org.gnome.desktop.interface", "accent-color"))
end

# The colour of each accent that a system names: the solid step (step 9) of the
# hue of the default palette that the name means, so the appearance finds that hue.
# A grey accent names no hue.
const _NAMED_ACCENT_COLORS = Dict{String,NTuple{3,UInt8}}(
    "red" => (0xe5, 0x48, 0x4d), "orange" => (0xf7, 0x6b, 0x15),
    "yellow" => (0xff, 0xc5, 0x3d), "green" => (0x30, 0xa4, 0x6c),
    "teal" => (0x12, 0xa5, 0x94), "blue" => (0x3e, 0x63, 0xdd),
    "purple" => (0x6e, 0x56, 0xcf), "pink" => (0xd6, 0x40, 0x9f))

# The colour settings in the answers of `gsettings` for the colour scheme, the high
# contrast and the accent: `'prefer-dark'`, `true` and `'orange'`. An answer that
# is `nothing` or not known gives light, normal or no accent.
function _convert_gsettings_answers(scheme::AbstractString, contrast, accent)
    unquote(text) = strip(strip(text), '\'')
    SystemColors(; mode = unquote(scheme) == "prefer-dark" ? :dark : :light,
                 contrast = contrast !== nothing && unquote(contrast) == "true" ? :high : :normal,
                 accent = accent === nothing ? nothing : get(_NAMED_ACCENT_COLORS, unquote(accent), nothing))
end

# The colour settings in the answer of the portal to `ReadAll`, as `gdbus` prints
# it: `color-scheme` 1 is dark, `contrast` 1 is high, and `accent-color` is three
# numbers from 0 to 1, where a number outside that range means no accent.
function _convert_portal_answer(text::AbstractString)
    scheme = match(r"'color-scheme': <uint32 (\d+)>", text)
    contrast = match(r"'contrast': <uint32 (\d+)>", text)
    accent = match(r"'accent-color': <\(([-+\d.eE]+), ([-+\d.eE]+), ([-+\d.eE]+)\)>", text)
    channels = accent === nothing ? nothing : something.(tryparse.(Float64, accent.captures), -1.0)
    SystemColors(; mode = scheme !== nothing && scheme[1] == "1" ? :dark : :light,
                 contrast = contrast !== nothing && contrast[1] == "1" ? :high : :normal,
                 accent = (channels === nothing || any(c -> !(0 <= c <= 1), channels)) ? nothing :
                          Tuple(round(UInt8, c * 255) for c in channels))
end

# ── macOS ───────────────────────────────────────────────────────────────────

# The accents of macOS by their number in `AppleAccentColor`: -1 is graphite, a
# grey, and no number is the default blue.
const _MACOS_ACCENT_NAMES = Dict(0 => "red", 1 => "orange", 2 => "yellow", 3 => "green",
                                 4 => "blue", 5 => "purple", 6 => "pink")

function _read_macos_colors(limit::Real)
    read_default(arguments...) = _read_command_output(`defaults read $arguments`, limit)
    _convert_macos_answers(read_default("-g", "AppleInterfaceStyle"),
                           read_default("com.apple.universalaccess", "increaseContrast"),
                           read_default("-g", "AppleAccentColor"))
end

# The colour settings in the answers of `defaults`: `Dark` for the style, `1` for an
# increased contrast, and the number of the accent. macOS has no value for a light
# style and for the default accent, so `nothing` is light and blue.
function _convert_macos_answers(style, contrast, accent)
    number = accent === nothing ? 4 : something(tryparse(Int, strip(accent)), 4)
    name = get(_MACOS_ACCENT_NAMES, number, nothing)
    SystemColors(; mode = style !== nothing && strip(style) == "Dark" ? :dark : :light,
                 contrast = contrast !== nothing && strip(contrast) == "1" ? :high : :normal,
                 accent = name === nothing ? nothing : _NAMED_ACCENT_COLORS[name])
end

# ── Windows ─────────────────────────────────────────────────────────────────

# The `HIGHCONTRASTW` record of `SystemParametersInfoW`.
struct _HighContrastRecord
    size::UInt32
    flags::UInt32
    scheme::Ptr{UInt16}
end

function _read_windows_colors()
    light = _read_registry_number("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                                  "AppsUseLightTheme")
    record = Ref(_HighContrastRecord(sizeof(_HighContrastRecord), 0, C_NULL))
    found = ccall((:SystemParametersInfoW, "user32"), stdcall, Int32,
                  (UInt32, UInt32, Ref{_HighContrastRecord}, UInt32),
                  0x0042, sizeof(_HighContrastRecord), record, 0)    # SPI_GETHIGHCONTRAST
    color, opaque = Ref{UInt32}(0), Ref{Int32}(0)
    status = ccall((:DwmGetColorizationColor, "dwmapi"), stdcall, Int32,
                   (Ref{UInt32}, Ref{Int32}), color, opaque)
    SystemColors(; mode = light == 0 ? :dark : :light,
                 contrast = found != 0 && record[].flags & 0x1 != 0 ? :high : :normal,    # HCF_HIGHCONTRASTON
                 accent = status == 0 ? (UInt8((color[] >> 16) & 0xff), UInt8((color[] >> 8) & 0xff),
                                         UInt8(color[] & 0xff)) : nothing)
end

# The number in the value `name` of the key `key` of the current user, or `nothing`.
function _read_registry_number(key::AbstractString, name::AbstractString)
    data, size = Ref{UInt32}(0), Ref{UInt32}(4)
    current_user = Ptr{Cvoid}(reinterpret(UInt, -2147483647))     # HKEY_CURRENT_USER
    status = ccall((:RegGetValueW, "advapi32"), stdcall, Int32,
                   (Ptr{Cvoid}, Cwstring, Cwstring, UInt32, Ptr{Cvoid}, Ref{UInt32}, Ref{UInt32}),
                   current_user, key, name, 0x00000010, C_NULL, data, size)    # RRF_RT_REG_DWORD
    status == 0 ? data[] : nothing
end

# ── A command with a limit ──────────────────────────────────────────────────

# The output of `command`, or `nothing` when it can not start, fails, or does not
# end within `limit` seconds; then it is stopped. The wait yields, so the other
# tasks of the thread go on.
function _read_command_output(command::Cmd, limit::Real)
    process = try
        open(pipeline(command; stderr = devnull), "r")
    catch
        return nothing
    end
    reader = @async read(process, String)
    ended = timedwait(() -> istaskdone(reader) && process_exited(process), Float64(limit);
                      pollint = 0.01) === :ok
    if !ended
        kill(process)
        return nothing
    end
    text = try
        fetch(reader)
    catch
        nothing
    end
    success(process) ? text : nothing
end
