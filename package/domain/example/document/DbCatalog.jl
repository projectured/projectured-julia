# Atomic documents for the catalog: a tiny nested PostgreSQL catalog tree
# (rdbms → database → schema → table → column), each level wrapping the
# smaller one below it. No live connection is needed — the catalog document
# types are plain nested value documents.

make_db_catalog_column_document_example()   = DbCatalogColumn("id", "integer")
make_db_catalog_table_document_example()    = DbCatalogTable("users", [make_db_catalog_column_document_example()])
make_db_catalog_schema_document_example()   = DbCatalogSchema("public", [make_db_catalog_table_document_example()])
make_db_catalog_database_document_example() = DbCatalogDatabase("projectured_test", [make_db_catalog_schema_document_example()])
make_db_catalog_rdbms_document_example()    = DbCatalogRdbms("localhost", 5432, [make_db_catalog_database_document_example()])
