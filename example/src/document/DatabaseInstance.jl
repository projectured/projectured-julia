function make_database_instance_document_example()
    DatabaseInstance(
        database="projectured_test",
        host="localhost",
        port=5432,
        credentials=DatabaseCredentials(
            user="projectured",
            password="projectured",
        ),
    )
end
