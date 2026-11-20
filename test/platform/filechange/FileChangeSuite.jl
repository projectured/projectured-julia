"""
    test_filechange()

Run this slice's whole suite: the store of the watched files, and its feed.
"""
const test_filechange = TestSuite("ProjecturedPlatform", [
    test_file_change_store,
])

export test_filechange, test_file_change_store
