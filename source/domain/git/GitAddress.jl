# Fragment of `GitModule` — the address of a commit and of a file at a revision,
# which a link of any domain names: `git+file://<repository>#<revision>` and
# `git+file://<repository>#<revision>:<path>`.

# The document that a `git+file:` address names: a `GitCommit` for `#<revision>`,
# and a `GitFileRevision` for `#<revision>:<path>`, where the first `:` ends the
# revision, as in `git show <revision>:<path>`. The repository is the path of the
# address, a folder on this computer, so an address with a host names nothing, and
# so does an address with no revision. The document reads nothing until a view
# prints it, and a revision that git does not know shows the words of git there.
function find_url_document(::Val{Symbol("git+file")}, url::Url)
    (url.host === nothing || isempty(url.host)) || return nothing
    (url.fragment === nothing || isempty(url.fragment)) && return nothing
    repository = decode_url_text(url.path)
    startswith(repository, '/') || return nothing
    target = decode_url_text(url.fragment)
    colon = findfirst(':', target)
    colon === nothing && return GitCommit(repository, target)
    revision = target[1:prevind(target, colon)]
    path = target[nextind(target, colon):end]
    (isempty(revision) || isempty(path)) && return nothing
    GitFileRevision(repository, revision, path)
end
