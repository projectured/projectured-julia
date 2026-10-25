# Fragment of `LinkModule` — the open of an address outside the editor, and the
# seam through which a backend opens it in a program of the system.

"""
    OpenUrlOperation(url, place = :here)

The request to open `url`, an absolute address, outside the editor: a `file:`
address opens its file in a tab, and any other address in the program of the
system for it, such as the browser for `https:` or the mail program for
`mailto:`. `place` is the place that the gesture asked for; a program of the
system opens an address at either place. A link answers it, it goes up to the
editor unchanged, and the editor evaluates it.

# Example

    OpenUrlOperation(Url("https://julialang.org"))
"""
struct OpenUrlOperation <: Operation
    url::Url
    place::Symbol
end

# @optional: most addresses open from a plain click.
OpenUrlOperation(url::Url) = OpenUrlOperation(url, :here)

is_self_contained_operation(::OpenUrlOperation) = true
describe_operation(operation::OpenUrlOperation) = "Open " * String(operation.url.address)

"""
    open_url!(backend, address) -> Bool

Open `address` in the program of the system for it, such as the browser, through
`backend`, the backend of an editor. `true` when the system took it. The default
opens nothing and answers `false`: a backend with no system to open it in, as the
backend of a test.

Use it in a backend that can ask the system to open an address.

# Example

    open_url!(editor.backend, "https://julialang.org")
"""
function open_url! end

open_url!(backend, address::AbstractString) = false
