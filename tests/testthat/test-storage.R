# Tests for datom_storage_list() and datom_storage_delete_prefix()
# Chunk 1 of Phase 22: Storage Extension API

# --- Local conn helper --------------------------------------------------------

make_local_storage_conn <- function(root, prefix = "proj") {
  structure(
    list(
      project_name = "test-project",
      backend      = "local",
      root         = as.character(root),
      prefix       = prefix,
      client       = NULL,
      path         = NULL,
      role         = "developer",
      region       = NULL,
      gov_root     = NULL
    ),
    class = "datom_conn"
  )
}


# === datom_storage_list() =====================================================

test_that("datom_storage_list() errors on non-conn", {
  expect_error(datom_storage_list("not-a-conn"), "datom_conn")
  expect_error(datom_storage_list(list()), "datom_conn")
  expect_error(datom_storage_list(NULL), "datom_conn")
})

test_that("datom_storage_list() returns keys from S3 backend", {
  expected_keys <- c(
    "proj/datom/demo/abc123.parquet",
    "proj/datom/.metadata/manifest.json"
  )
  mock_list <- mockery::mock(
    list(
      Contents  = purrr::map(expected_keys, ~ list(Key = .x)),
      IsTruncated = FALSE
    )
  )
  conn <- mock_datom_conn(
    list(list_objects_v2 = mock_list),
    root   = "my-bucket",
    prefix = "proj"
  )

  result <- datom_storage_list(conn)

  expect_equal(result, expected_keys)
  mockery::expect_called(mock_list, 1)
  # Verify the full datom namespace prefix was passed (not a sub-path)
  call_args <- mockery::mock_args(mock_list)[[1]]
  expect_equal(call_args$Prefix, "proj/datom/")
})

test_that("datom_storage_list() returns empty vector when namespace is empty", {
  mock_list <- mockery::mock(
    list(Contents = list(), IsTruncated = FALSE)
  )
  conn <- mock_datom_conn(list(list_objects_v2 = mock_list))

  result <- datom_storage_list(conn)

  expect_equal(result, character(0))
})

test_that("datom_storage_list() works with NULL prefix on S3", {
  mock_list <- mockery::mock(
    list(Contents = list(), IsTruncated = FALSE)
  )
  conn <- mock_datom_conn(list(list_objects_v2 = mock_list), prefix = NULL)

  datom_storage_list(conn)

  call_args <- mockery::mock_args(mock_list)[[1]]
  # No prefix component -- should start with datom/
  expect_equal(call_args$Prefix, "datom/")
})

test_that("datom_storage_list() returns keys from local backend", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")

    # Seed a few objects in the datom namespace
    fs::dir_create("proj/datom/demographics")
    fs::dir_create("proj/datom/.metadata")
    writeLines("data", "proj/datom/demographics/abc.parquet")
    writeLines("meta", "proj/datom/.metadata/manifest.json")

    result <- datom_storage_list(conn)

    expect_true(is.character(result))
    expect_length(result, 2L)
    expect_true(any(grepl("demographics/abc.parquet", result, fixed = TRUE)))
    expect_true(any(grepl(".metadata/manifest.json", result, fixed = TRUE)))
  })
})

test_that("datom_storage_list() returns empty vector for empty local namespace", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")
    # datom dir does not exist yet
    result <- datom_storage_list(conn)
    expect_equal(result, character(0))
  })
})


# === datom_storage_delete_prefix() ===========================================

test_that("datom_storage_delete_prefix() errors on non-conn", {
  expect_error(datom_storage_delete_prefix("not-a-conn"), "datom_conn")
  expect_error(datom_storage_delete_prefix(NULL), "datom_conn")
})

test_that("datom_storage_delete_prefix() passes NULL prefix_key to internal", {
  # Stub the internal so we can inspect the args without needing a real S3 client
  mock_internal <- mockery::mock(invisible(0L))
  mockery::stub(datom_storage_delete_prefix, ".datom_storage_delete_prefix", mock_internal)

  conn <- mock_datom_conn(list(), root = "my-bucket")
  datom_storage_delete_prefix(conn)

  mockery::expect_called(mock_internal, 1)
  call_args <- mockery::mock_args(mock_internal)[[1]]
  expect_null(call_args[[2]])  # prefix_key = NULL
})

test_that("datom_storage_delete_prefix() passes specific prefix_key to internal", {
  mock_internal <- mockery::mock(invisible(3L))
  mockery::stub(datom_storage_delete_prefix, ".datom_storage_delete_prefix", mock_internal)

  conn <- mock_datom_conn(list(), root = "my-bucket")
  datom_storage_delete_prefix(conn, prefix_key = "demographics")

  call_args <- mockery::mock_args(mock_internal)[[1]]
  expect_equal(call_args[[2]], "demographics")
})

test_that("datom_storage_delete_prefix() returns internal result invisibly", {
  mock_internal <- mockery::mock(invisible(5L))
  mockery::stub(datom_storage_delete_prefix, ".datom_storage_delete_prefix", mock_internal)

  conn <- mock_datom_conn(list())
  result <- withVisible(datom_storage_delete_prefix(conn, "table1"))

  expect_equal(result$value, 5L)
  expect_false(result$visible)
})

test_that("datom_storage_delete_prefix() deletes files on local backend", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")

    # Seed files across two tables
    fs::dir_create("proj/datom/table1")
    fs::dir_create("proj/datom/table2")
    writeLines("a", "proj/datom/table1/v1.parquet")
    writeLines("b", "proj/datom/table1/v2.parquet")
    writeLines("c", "proj/datom/table2/v1.parquet")

    # Delete only table1
    n <- datom_storage_delete_prefix(conn, prefix_key = "table1")

    expect_equal(n, 1L)  # local backend: 1L = directory removed
    expect_false(fs::dir_exists("proj/datom/table1"))
    expect_true(fs::dir_exists("proj/datom/table2"))
  })
})

test_that("datom_storage_delete_prefix(prefix_key = NULL) removes entire namespace on local", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")

    fs::dir_create("proj/datom/table1")
    fs::dir_create("proj/datom/.metadata")
    writeLines("a", "proj/datom/table1/v1.parquet")
    writeLines("m", "proj/datom/.metadata/manifest.json")

    n <- datom_storage_delete_prefix(conn)

    expect_equal(n, 1L)  # local backend: 1L = directory removed
    expect_false(fs::dir_exists("proj/datom"))
  })
})

test_that("datom_storage_delete_prefix() returns 0L when prefix does not exist", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")
    n <- datom_storage_delete_prefix(conn, prefix_key = "nonexistent")
    expect_equal(n, 0L)
  })
})


# === datom_storage_copy() =====================================================

test_that("datom_storage_copy() errors on non-conn args", {
  conn <- mock_datom_conn(list())
  expect_error(datom_storage_copy("not-a-conn", conn), "from_conn")
  expect_error(datom_storage_copy(conn, list()),        "to_conn")
  expect_error(datom_storage_copy(NULL, conn),          "from_conn")
})

test_that("datom_storage_copy() returns empty data frame when source is empty", {
  mock_list <- mockery::mock(list(Contents = list(), IsTruncated = FALSE))
  from_conn <- mock_datom_conn(list(list_objects_v2 = mock_list))
  to_conn   <- mock_datom_conn(list())

  result <- datom_storage_copy(from_conn, to_conn)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
  expect_named(result, c("key", "bytes"))
})

test_that("datom_storage_copy() local->local copies files and returns data frame", {
  withr::with_tempdir({
    from_root <- fs::dir_create("from")
    to_root   <- fs::dir_create("to")

    from_conn <- make_local_storage_conn(from_root, prefix = "proj")
    to_conn   <- make_local_storage_conn(to_root,   prefix = "proj")

    # Seed two objects in source namespace
    fs::dir_create(fs::path(from_root, "proj/datom/table1"))
    fs::dir_create(fs::path(from_root, "proj/datom/.metadata"))
    writeBin(charToRaw("parquet bytes"), fs::path(from_root, "proj/datom/table1/abc.parquet"))
    writeBin(charToRaw("manifest json"), fs::path(from_root, "proj/datom/.metadata/manifest.json"))

    result <- datom_storage_copy(from_conn, to_conn)

    expect_s3_class(result, "data.frame")
    expect_named(result, c("key", "bytes"))
    expect_equal(nrow(result), 2L)
    expect_true(is.character(result$key))
    expect_true(is.numeric(result$bytes))
    # Bytes are positive
    expect_true(all(result$bytes > 0))

    # Files actually exist at destination
    expect_true(fs::file_exists(
      fs::path(to_root, "proj/datom/table1/abc.parquet")
    ))
    expect_true(fs::file_exists(
      fs::path(to_root, "proj/datom/.metadata/manifest.json")
    ))

    # Content is identical
    expect_equal(
      readBin(fs::path(to_root, "proj/datom/table1/abc.parquet"), "raw", 100),
      charToRaw("parquet bytes")
    )
  })
})

test_that("datom_storage_copy() local->s3 calls put_object with correct args", {
  withr::with_tempdir({
    from_root <- fs::dir_create("from")
    from_conn <- make_local_storage_conn(from_root, prefix = "proj")

    content_raw <- charToRaw("parquet content")
    fs::dir_create(fs::path(from_root, "proj/datom/table1"))
    writeBin(content_raw, fs::path(from_root, "proj/datom/table1/abc.parquet"))

    mock_put <- mockery::mock(list())
    to_conn  <- mock_datom_conn(
      list(put_object = mock_put),
      root   = "dest-bucket",
      prefix = "dest-proj"
    )

    result <- datom_storage_copy(from_conn, to_conn)

    expect_equal(nrow(result), 1L)
    expect_equal(result$key, "table1/abc.parquet")
    expect_equal(result$bytes, length(content_raw))

    mockery::expect_called(mock_put, 1L)
    put_args <- mockery::mock_args(mock_put)[[1]]
    expect_equal(put_args$Bucket, "dest-bucket")
    expect_equal(put_args$Key,    "dest-proj/datom/table1/abc.parquet")
    expect_equal(put_args$Body,   content_raw)
  })
})

test_that("datom_storage_copy() s3->local downloads and writes files", {
  withr::with_tempdir({
    to_root  <- fs::dir_create("to")
    to_conn  <- make_local_storage_conn(to_root, prefix = "proj")

    content_raw <- charToRaw("parquet bytes from s3")

    mock_list <- mockery::mock(list(
      Contents    = list(list(Key = "src-proj/datom/table1/abc.parquet")),
      IsTruncated = FALSE
    ))
    mock_get <- mockery::mock(list(Body = content_raw))
    from_conn <- mock_datom_conn(
      list(list_objects_v2 = mock_list, get_object = mock_get),
      root   = "src-bucket",
      prefix = "src-proj"
    )

    result <- datom_storage_copy(from_conn, to_conn)

    expect_equal(nrow(result), 1L)
    expect_equal(result$key, "table1/abc.parquet")
    expect_equal(result$bytes, length(content_raw))

    # get_object called with the correct source full key
    get_args <- mockery::mock_args(mock_get)[[1]]
    expect_equal(get_args$Bucket, "src-bucket")
    expect_equal(get_args$Key,    "src-proj/datom/table1/abc.parquet")

    # File written at destination with correct content
    dest_path <- fs::path(to_root, "proj/datom/table1/abc.parquet")
    expect_true(fs::file_exists(dest_path))
    expect_equal(readBin(dest_path, what = "raw", n = 100), content_raw)
  })
})

test_that("datom_storage_copy() s3->s3 streams bytes through memory", {
  content_raw <- charToRaw("s3 object bytes")

  mock_list <- mockery::mock(list(
    Contents    = list(list(Key = "from-proj/datom/table1/abc.parquet")),
    IsTruncated = FALSE
  ))
  mock_get <- mockery::mock(list(Body = content_raw))
  mock_put <- mockery::mock(list())

  from_conn <- mock_datom_conn(
    list(list_objects_v2 = mock_list, get_object = mock_get),
    root   = "src-bucket",
    prefix = "from-proj"
  )
  to_conn <- mock_datom_conn(
    list(put_object = mock_put),
    root   = "dest-bucket",
    prefix = "to-proj"
  )

  result <- datom_storage_copy(from_conn, to_conn)

  expect_equal(nrow(result), 1L)
  expect_equal(result$key, "table1/abc.parquet")
  expect_equal(result$bytes, length(content_raw))

  # get from source with correct key
  get_args <- mockery::mock_args(mock_get)[[1]]
  expect_equal(get_args$Bucket, "src-bucket")
  expect_equal(get_args$Key,    "from-proj/datom/table1/abc.parquet")

  # put to destination with new-prefixed key and same bytes
  mockery::expect_called(mock_put, 1L)
  put_args <- mockery::mock_args(mock_put)[[1]]
  expect_equal(put_args$Bucket, "dest-bucket")
  expect_equal(put_args$Key,    "to-proj/datom/table1/abc.parquet")
  expect_equal(put_args$Body,   content_raw)
})

test_that("datom_storage_copy() rel keys are stripped from from_conn prefix", {
  # Verify returned keys have no source prefix -- ready for datom_storage_verify
  content_raw <- charToRaw("bytes")
  mock_list <- mockery::mock(list(
    Contents = list(
      list(Key = "old/datom/tableA/v1.parquet"),
      list(Key = "old/datom/.metadata/manifest.json")
    ),
    IsTruncated = FALSE
  ))
  mock_get <- mockery::mock(list(Body = content_raw), list(Body = content_raw))
  mock_put <- mockery::mock(list(), list())

  from_conn <- mock_datom_conn(
    list(list_objects_v2 = mock_list, get_object = mock_get),
    root = "src-bucket", prefix = "old"
  )
  to_conn <- mock_datom_conn(
    list(put_object = mock_put),
    root = "dest-bucket", prefix = "new"
  )

  result <- datom_storage_copy(from_conn, to_conn)

  expect_equal(nrow(result), 2L)
  expect_setequal(result$key, c("tableA/v1.parquet", ".metadata/manifest.json"))

  # Both put_object calls should use the new prefix
  all_dest_keys <- c(
    mockery::mock_args(mock_put)[[1]]$Key,
    mockery::mock_args(mock_put)[[2]]$Key
  )
  expect_true(all(startsWith(all_dest_keys, "new/datom/")))
})


# === datom_storage_verify() ===================================================

test_that("datom_storage_verify() errors on non-conn args", {
  conn <- mock_datom_conn(list())
  expect_error(datom_storage_verify("x", conn), "from_conn")
  expect_error(datom_storage_verify(conn, list()), "to_conn")
  expect_error(datom_storage_verify(NULL, conn), "from_conn")
})

test_that("datom_storage_verify() errors on invalid mode", {
  conn <- mock_datom_conn(list())
  expect_error(datom_storage_verify(conn, conn, mode = "wrong"), "arg")
})

test_that("datom_storage_verify() errors when keys is not character", {
  conn <- mock_datom_conn(list())
  expect_error(datom_storage_verify(conn, conn, keys = 123L), "character")
})

test_that("datom_storage_verify() returns empty df when no keys", {
  mock_list <- mockery::mock(list(Contents = list(), IsTruncated = FALSE))
  conn <- mock_datom_conn(list(list_objects_v2 = mock_list))

  result <- datom_storage_verify(conn, conn)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
  expect_named(result, c("key", "ok", "issue"))
})

test_that("datom_storage_verify() structural mode passes when sizes match", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    content <- charToRaw("parquet content")
    fs::dir_create("from/proj/datom/table1")
    fs::dir_create("to/proj/datom/table1")
    writeBin(content, "from/proj/datom/table1/v1.parquet")
    writeBin(content, "to/proj/datom/table1/v1.parquet")

    result <- datom_storage_verify(from_conn, to_conn,
                                   keys = "table1/v1.parquet",
                                   mode = "structural")

    expect_equal(nrow(result), 1L)
    expect_true(result$ok[[1]])
    expect_true(is.na(result$issue[[1]]))
  })
})

test_that("datom_storage_verify() structural mode catches truncated destination", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    fs::dir_create("from/proj/datom/table1")
    fs::dir_create("to/proj/datom/table1")
    writeBin(charToRaw("full parquet content"), "from/proj/datom/table1/v1.parquet")
    writeBin(charToRaw("truncated"),            "to/proj/datom/table1/v1.parquet")

    result <- datom_storage_verify(from_conn, to_conn,
                                   keys = "table1/v1.parquet",
                                   mode = "structural")

    expect_equal(nrow(result), 1L)
    expect_false(result$ok[[1]])
    expect_match(result$issue[[1]], "size mismatch")
  })
})

test_that("datom_storage_verify() structural mode catches missing destination", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    fs::dir_create("from/proj/datom/table1")
    writeBin(charToRaw("content"), "from/proj/datom/table1/v1.parquet")
    # destination NOT created

    result <- datom_storage_verify(from_conn, to_conn,
                                   keys = "table1/v1.parquet",
                                   mode = "structural")

    expect_false(result$ok[[1]])
    expect_match(result$issue[[1]], "not found")
  })
})

test_that("datom_storage_verify() structural mode uses head_object on S3", {
  mock_head_src <- mockery::mock(list(ContentLength = 512))
  mock_head_dst <- mockery::mock(list(ContentLength = 512))

  from_conn <- mock_datom_conn(
    list(head_object = mock_head_src), root = "src-bucket", prefix = "from-proj"
  )
  to_conn <- mock_datom_conn(
    list(head_object = mock_head_dst), root = "dst-bucket", prefix = "to-proj"
  )

  result <- datom_storage_verify(from_conn, to_conn,
                                 keys = "table1/v1.parquet",
                                 mode = "structural")

  expect_true(result$ok[[1]])

  # head_object called on source with correct key
  src_args <- mockery::mock_args(mock_head_src)[[1]]
  expect_equal(src_args$Bucket, "src-bucket")
  expect_equal(src_args$Key, "from-proj/datom/table1/v1.parquet")

  # head_object called on destination with correct key
  dst_args <- mockery::mock_args(mock_head_dst)[[1]]
  expect_equal(dst_args$Bucket, "dst-bucket")
  expect_equal(dst_args$Key, "to-proj/datom/table1/v1.parquet")
})

test_that("datom_storage_verify() structural mode S3 catches size mismatch", {
  mock_head_src <- mockery::mock(list(ContentLength = 1024))
  mock_head_dst <- mockery::mock(list(ContentLength = 512))  # truncated

  from_conn <- mock_datom_conn(list(head_object = mock_head_src))
  to_conn   <- mock_datom_conn(list(head_object = mock_head_dst))

  result <- datom_storage_verify(from_conn, to_conn,
                                 keys = "table1/v1.parquet",
                                 mode = "structural")

  expect_false(result$ok[[1]])
  expect_match(result$issue[[1]], "size mismatch")
})

test_that("datom_storage_verify() content mode passes when hashes match", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    content <- charToRaw("exact same parquet bytes")
    fs::dir_create("from/proj/datom/table1")
    fs::dir_create("to/proj/datom/table1")
    writeBin(content, "from/proj/datom/table1/v1.parquet")
    writeBin(content, "to/proj/datom/table1/v1.parquet")

    result <- datom_storage_verify(from_conn, to_conn,
                                   keys = "table1/v1.parquet",
                                   mode = "content")

    expect_true(result$ok[[1]])
    expect_true(is.na(result$issue[[1]]))
  })
})

test_that("datom_storage_verify() content mode catches corrupted bytes", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    fs::dir_create("from/proj/datom/table1")
    fs::dir_create("to/proj/datom/table1")
    writeBin(charToRaw("original parquet bytes"), "from/proj/datom/table1/v1.parquet")
    writeBin(charToRaw("CORRUPTED BYTES HERE!"),  "to/proj/datom/table1/v1.parquet")

    result <- datom_storage_verify(from_conn, to_conn,
                                   keys = "table1/v1.parquet",
                                   mode = "content")

    expect_false(result$ok[[1]])
    expect_match(result$issue[[1]], "content hash mismatch")
  })
})

test_that("datom_storage_verify() content mode uses get_object on S3", {
  content_raw <- charToRaw("parquet bytes")
  mock_get_src <- mockery::mock(list(Body = content_raw))
  # Same content for size-check (head) + content-check (get) -- structural check runs first
  mock_head_src <- mockery::mock(list(ContentLength = length(content_raw)))
  mock_head_dst <- mockery::mock(list(ContentLength = length(content_raw)))
  mock_get_dst  <- mockery::mock(list(Body = content_raw))

  from_conn <- mock_datom_conn(
    list(head_object = mock_head_src, get_object = mock_get_src),
    root = "src-bucket", prefix = "from-proj"
  )
  to_conn <- mock_datom_conn(
    list(head_object = mock_head_dst, get_object = mock_get_dst),
    root = "dst-bucket", prefix = "to-proj"
  )

  result <- datom_storage_verify(from_conn, to_conn,
                                 keys = "table1/v1.parquet",
                                 mode = "content")

  expect_true(result$ok[[1]])
  mockery::expect_called(mock_get_src, 1L)
  mockery::expect_called(mock_get_dst, 1L)

  src_args <- mockery::mock_args(mock_get_src)[[1]]
  expect_equal(src_args$Bucket, "src-bucket")
  expect_equal(src_args$Key, "from-proj/datom/table1/v1.parquet")
})

test_that("datom_storage_verify() content mode S3 catches corrupted bytes", {
  mock_head_src <- mockery::mock(list(ContentLength = 10))
  mock_head_dst <- mockery::mock(list(ContentLength = 10))  # same size...
  mock_get_src  <- mockery::mock(list(Body = charToRaw("origbytes!")))
  mock_get_dst  <- mockery::mock(list(Body = charToRaw("corruptXX!")))  # ...different content

  from_conn <- mock_datom_conn(list(head_object = mock_head_src, get_object = mock_get_src))
  to_conn   <- mock_datom_conn(list(head_object = mock_head_dst, get_object = mock_get_dst))

  result <- datom_storage_verify(from_conn, to_conn,
                                 keys = "table1/v1.parquet",
                                 mode = "content")

  expect_false(result$ok[[1]])
  expect_match(result$issue[[1]], "content hash mismatch")
})

test_that("datom_storage_verify() keys=NULL lists from from_conn", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    content <- charToRaw("data")
    for (nm in c("t1/a.parquet", "t2/b.parquet")) {
      fs::dir_create(fs::path("from/proj/datom", fs::path_dir(nm)))
      fs::dir_create(fs::path("to/proj/datom",   fs::path_dir(nm)))
      writeBin(content, fs::path("from/proj/datom", nm))
      writeBin(content, fs::path("to/proj/datom",   nm))
    }

    result <- datom_storage_verify(from_conn, to_conn)  # keys = NULL

    expect_equal(nrow(result), 2L)
    expect_true(all(result$ok))
    expect_setequal(result$key, c("t1/a.parquet", "t2/b.parquet"))
  })
})

test_that("datom_storage_verify() keys subset verifies only those keys", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    # Three objects in source, only two in destination
    for (nm in c("t1/a.parquet", "t2/b.parquet", "t3/c.parquet")) {
      fs::dir_create(fs::path("from/proj/datom", fs::path_dir(nm)))
      writeBin(charToRaw("data"), fs::path("from/proj/datom", nm))
    }
    # Put only t1 and t2 in destination
    for (nm in c("t1/a.parquet", "t2/b.parquet")) {
      fs::dir_create(fs::path("to/proj/datom", fs::path_dir(nm)))
      writeBin(charToRaw("data"), fs::path("to/proj/datom", nm))
    }

    # Verify only the two that exist -- should pass
    result <- datom_storage_verify(from_conn, to_conn,
                                   keys = c("t1/a.parquet", "t2/b.parquet"))

    expect_equal(nrow(result), 2L)
    expect_true(all(result$ok))
  })
})

test_that("datom_storage_verify() result has correct column types", {
  withr::with_tempdir({
    from_conn <- make_local_storage_conn(fs::dir_create("from"), prefix = "proj")
    to_conn   <- make_local_storage_conn(fs::dir_create("to"),   prefix = "proj")

    content <- charToRaw("bytes")
    fs::dir_create("from/proj/datom/t1")
    fs::dir_create("to/proj/datom/t1")
    writeBin(content, "from/proj/datom/t1/v.parquet")
    writeBin(content, "to/proj/datom/t1/v.parquet")

    result <- datom_storage_verify(from_conn, to_conn, keys = "t1/v.parquet")

    expect_s3_class(result, "data.frame")
    expect_named(result, c("key", "ok", "issue"))
    expect_type(result$key,   "character")
    expect_type(result$ok,    "logical")
    expect_type(result$issue, "character")
  })
})
