# A VersionedObject over a small JSON object, carrying three ObjectVersions with
# different timestamps and authors (newest-first by convention). The default
# criterion is VersionCriterionLatest, so the elimination projection shows the
# newest version's value as a plain JSON object; switching the criterion (e.g.
# VersionCriterionIndex(2) or VersionCriterionByAuthor("bob")) selects another.
# See make_versioning_projection_example for the keys.
function make_versioning_document_example()
    v3 = ObjectVersion(
        JsonObject(
            "title"  => JsonString("Versioning"),
            "status" => JsonString("published"),
            "views"  => JsonNumber(128),
        );
        timestamp=3, author="carol", label="release",
    )
    v2 = ObjectVersion(
        JsonObject(
            "title"  => JsonString("Versioning"),
            "status" => JsonString("review"),
            "views"  => JsonNumber(42),
        );
        timestamp=2, author="bob", label="edit",
    )
    v1 = ObjectVersion(
        JsonObject(
            "title"  => JsonString("Draft"),
            "status" => JsonString("draft"),
        );
        timestamp=1, author="alice", label="initial",
    )
    VersionedObject([v3, v2, v1])
end
