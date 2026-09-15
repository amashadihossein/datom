#' Read a datom Table
#'
#' Unified read function with dispatch via `dispatch.json`. Reads from S3
#' metadata cache for data readers.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param name Table name.
#' @param version Optional metadata_sha (datom version). If NULL, uses current.
#' @param context Optional context for dispatch (e.g., "default", "cached").
#' @param ... Additional parameters forwarded to routed function.
#'
#' @return Data frame or routed function result.
#' @export
#'
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   datom_write(conn, data = datom_example_data("dm"), name = "dm")
#'
#'   # Current version
#'   dm <- datom_read(conn, "dm")
#'   print(head(dm))
#'
#'   # A specific version, by its identifier -- byte-for-byte the same table
#'   v <- datom_history(conn, "dm")$version[1]
#'   print(identical(datom_read(conn, "dm", version = v), dm))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_read <- function(conn,
                      name,
                      version = NULL,
                      context = NULL,
                      ...) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  .datom_validate_name(name)

  # 1. Read metadata + version history from S3
  metadata_list <- .datom_read_metadata(conn, name)

  # 2. One name is one artifact, and this verb reads one of the two kinds. The
  #    document has just been read, so the check costs nothing; without it a set
  #    is reported as a missing parquet file, which names neither sets nor the
  #    verb that reads them.
  .datom_check_artifact_kind(
    metadata_list$current, name, "table", operation = "read"
  )

  # 3. Resolve version to data_sha (+ the expected parquet_sha for integrity)

  resolved <- .datom_resolve_version(
    metadata_list, version = version, name = name, field = "parquet_sha"
  )

  # 4. Download and read parquet, verifying its integrity against parquet_sha.
  .datom_read_parquet(
    conn, name, resolved$data_sha,
    parquet_sha = resolved$object_sha
  )
}


# --- Read infrastructure ------------------------------------------------------

#' Read Table Metadata from S3
#'
#' Fetches both `metadata.json` (current state) and `version_history.json`
#' (version index) for a given table from S3.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name (validated).
#' @return Named list with `current` (metadata.json contents) and
#'   `history` (version_history.json contents as a list of entries).
#' @keywords internal
.datom_read_metadata <- function(conn, name) {
  .datom_validate_name(name)

  metadata_key <- .datom_artifact_meta_key(name, "metadata")
  history_key <- .datom_artifact_meta_key(name, "version_history")

  current <- .datom_storage_read_json(conn, metadata_key)

  # Compatibility check before the second read: datom_read() never touches the
  # manifest, so this is the only place the data path sees a schema version.
  .datom_check_schema_version(current, metadata_key)

  history <- .datom_storage_read_json(conn, history_key)

  list(current = current, history = history)
}


#' Resolve Version to data_sha, Stored-Object Hash and Recorded Version
#'
#' Given metadata from [.datom_read_metadata()], resolves a version spec
#' to the corresponding `data_sha` (the storage address), the recorded
#' stored-object integrity hash, and the version string as **recorded**. If
#' `version` is NULL, resolves from the current `metadata.json`; if a
#' metadata_sha string (or a prefix of one), looks it up in
#' `version_history.json`.
#'
#' **One function, two kinds, one `field` argument.** A table's stored object is
#' a parquet file pinned by `parquet_sha`; a set's is a JSON payload pinned by
#' `document_sha`. The question is identical either way -- *which recorded hash
#' pins the version I just resolved* -- so a second copy of this lookup would
#' eventually disagree with this one about prefix matching or about what an
#' absent hash means. The resolved hash comes back as `object_sha` regardless,
#' because the caller already knows which field it asked for.
#'
#' The `object_sha` may be `NULL`/`""`, and what that means is the caller's to
#' decide, not this function's. For a table it is **pre-cv1 metadata** and tells
#' [.datom_read_parquet()] to skip the integrity check -- a grace for legacy
#' metadata, not a gap in the current writer. For a set there is no legacy
#' population, so the set read treats it as an error.
#'
#' `version` is the version **recorded** for the resolved state, never
#' recomputed: a pinned read echoes the matched history entry's own version
#' string (so a caller who passed an 8-character prefix gets the full one back),
#' and an unpinned read takes the current state's recorded version via
#' [.datom_recorded_current_version()]. That helper returns `NULL` when the
#' history records nothing matching the current document, which is a gap
#' `datom_validate()` owns -- a manufactured version would be a wrong statement
#' rather than a missing one.
#'
#' @param metadata_list Return value of [.datom_read_metadata()].
#' @param version NULL (current) or a metadata_sha string / prefix.
#' @param name Artifact name (for error messages).
#' @param field Which recorded stored-object hash to resolve:
#'   `"parquet_sha"` (a table's parquet) or `"document_sha"` (a set's payload).
#' @return Named list with `data_sha` (character), `object_sha` (character or
#'   `NULL`) and `version` (character or `NULL`) for the resolved version.
#' @keywords internal
.datom_resolve_version <- function(metadata_list, version = NULL, name = "table",
                                   field = "parquet_sha") {
  # `doc[[field]]` on a list that lacks the name is a subscript error rather than
  # NULL, and every document written before the field existed lacks it.
  recorded <- function(doc) {
    if (is.list(doc) && field %in% names(doc)) doc[[field]] else NULL
  }

  if (is.null(version)) {
    data_sha <- metadata_list$current$data_sha
    if (is.null(data_sha) || !nzchar(data_sha)) {
      cli::cli_abort(
        c(
          "metadata.json for {.val {name}} has no {.field data_sha}.",
          "i" = "The metadata may be corrupt or the table has no data."
        )
      )
    }
    return(list(
      data_sha = data_sha,
      object_sha = recorded(metadata_list$current),
      version = .datom_recorded_current_version(
        metadata_list$current, metadata_list$history
      )
    ))
  }

  if (!is.character(version) || length(version) != 1L || !nzchar(version)) {
    cli::cli_abort("{.arg version} must be a single non-empty string or NULL.")
  }

  # Look up version (metadata_sha) in history
  history <- metadata_list$history
  if (!is.list(history) || length(history) == 0L) {
    cli::cli_abort(
      c(
        "No version history found for {.val {name}}.",
        "i" = "version_history.json is empty or missing."
      )
    )
  }

  # history is a list of entries; each has $version and $data_sha
  # Support prefix matching (like git short SHAs)
  match_indices <- which(purrr::map_lgl(
    history, ~ startsWith(.x$version %||% "", version)
  ))

  if (length(match_indices) == 0L) {
    cli::cli_abort(
      c(
        "Version {.val {version}} not found in history for {.val {name}}.",
        "i" = "Use {.fn datom_history} to see available versions."
      )
    )
  }

  if (length(match_indices) > 1L) {
    cli::cli_abort(
      c(
        "Version prefix {.val {version}} is ambiguous for {.val {name}}.",
        "i" = "It matches {length(match_indices)} versions. Use a longer prefix.",
        "i" = "Use {.fn datom_history} to see available versions."
      )
    )
  }

  match_idx <- match_indices[[1L]]

  data_sha <- history[[match_idx]]$data_sha
  if (is.null(data_sha) || !nzchar(data_sha)) {
    cli::cli_abort(
      c(
        "Version {.val {version}} has no {.field data_sha} in history.",
        "i" = "The version_history.json entry may be corrupt."
      )
    )
  }

  list(
    data_sha = data_sha,
    object_sha = recorded(history[[match_idx]]),
    version = history[[match_idx]]$version
  )
}


#' Download and Read Parquet from S3
#'
#' Downloads `{table}/{data_sha}.parquet` from S3 to a temporary file and reads
#' it via `arrow::read_parquet()`. When an expected `parquet_sha` is supplied
#' (non-empty), the downloaded object's SHA-256 is verified against it BEFORE
#' parsing, so corruption or tampering aborts rather than being silently read.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param data_sha SHA identifying the parquet file.
#' @param parquet_sha Expected SHA-256 of the stored parquet object bytes, from
#'   the resolved metadata (see [.datom_resolve_version()]). When non-empty, the
#'   downloaded file is verified against it and a mismatch aborts. When `NULL`
#'   or empty -- which now happens only for pre-cv1 metadata -- the integrity
#'   check is skipped and the read succeeds.
#' @return Data frame.
#' @keywords internal
.datom_read_parquet <- function(conn, name, data_sha, parquet_sha = NULL) {
  .datom_validate_name(name)

  if (!is.character(data_sha) || length(data_sha) != 1L || !nzchar(data_sha)) {
    cli::cli_abort("{.arg data_sha} must be a single non-empty string.")
  }
  # data_sha is spliced into a storage key; reject path-traversal / non-hex.
  .datom_validate_sha(data_sha, arg = "data_sha")

  s3_key <- .datom_artifact_payload_key(name, data_sha, "table")
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  .datom_storage_download(conn, s3_key, tmp)

  # Read-time integrity: verify the stored object bytes against the recorded
  # parquet_sha before parsing. Skipped when parquet_sha is absent/empty
  # (pre-cv1 metadata) -- a read-time grace, not a data migration.
  if (!is.null(parquet_sha) && nzchar(parquet_sha)) {
    actual <- digest::digest(file = tmp, algo = "sha256")
    if (!identical(actual, parquet_sha)) {
      cli::cli_abort(
        c(
          "Stored parquet for {.val {name}} failed its integrity check.",
          "x" = "Key: {.val {s3_key}}",
          "x" = "Expected {.field parquet_sha}: {.val {parquet_sha}}",
          "x" = "Actual SHA-256: {.val {actual}}",
          "i" = "The stored object may be corrupted or tampered with. Do not trust this data."
        )
      )
    }
  }

  arrow::read_parquet(tmp)
}


# --- Write infrastructure -----------------------------------------------------

#' Build Metadata Object
#'
#' Constructs the metadata list for a table write, including auto-computed
#' fields (data_sha, dimensions, colnames, timestamp, datom_version) and
#' any user-supplied custom metadata.
#'
#' @param data Data frame being written.
#' @param data_sha datom-cv1 canonical content hash of the data.
#' @param custom Optional named list of user-supplied custom metadata.
#' @param table_type `"derived"` (default, from `datom_write`) or `"imported"` (from `datom_sync`).
#' @param size_bytes Size of the parquet file in bytes. NULL if not yet computed.
#' @param parents Lineage list of parent entries (each with source, table, version),
#'   or NULL if no lineage recorded.
#' @param source_lineage Pre-computed transitive source list (each entry with
#'   project, table, version_sha), or NULL.
#' @param original_file_sha SHA-256 of the source file, for imported tables.
#'   Included in the metadata **only when non-NULL**; the derived path omits it
#'   from the object entirely (not present-with-NULL).
#' @param original_format Extension of the source file (`"csv"`, `"parquet"`,
#'   ...), for imported tables. Recorded on the same only-when-non-NULL terms as
#'   `original_file_sha`, and for one reason: it was previously written onto the
#'   manifest row and nowhere else, which made it the single field a
#'   reconstructed index had to drop. It is **not** part of the version identity
#'   -- see `.datom_metadata_excluded_fields`.
#' @param column_hashes Ordered list of per-column `list(name, sha)` digests
#'   from [.datom_canonical_hash()], or NULL. Excluded from `metadata_sha`
#'   (see [.datom_compute_metadata_sha()]).
#' @return Named list suitable for writing as metadata.json. Always carries
#'   `kind = "table"` (which artifact kind the document describes),
#'   `schema_version` (the format the document is written in) and
#'   `hash_algo = "datom-cv1"`, and declares `parquet_sha` (left NULL here and
#'   populated by [datom_write()] after change detection, since the stored-
#'   object hash is not knowable until then; it is excluded from `metadata_sha`
#'   so this deferred assignment is safe).
#' @keywords internal
.datom_build_metadata <- function(data, data_sha, custom = NULL,
                                 table_type = "derived", size_bytes = NULL,
                                 parents = NULL, source_lineage = NULL,
                                 original_file_sha = NULL,
                                 original_format = NULL, column_hashes = NULL) {
  if (!table_type %in% c("imported", "derived")) {
    cli::cli_abort("{.arg table_type} must be {.val imported} or {.val derived}.")
  }

  meta <- list(
    # The format this document is written in, declared first because every other
    # field's meaning depends on it. The value is what this build supports,
    # since a build writes the only shape it knows. It is on the documented
    # not-identity list, so stamping it mints no new version for content that
    # did not move.
    schema_version = .datom_supported_schema,
    # Which kind of artifact this document describes. Not a parameter: a table
    # write is the only thing that reaches this builder, and a set gets its own
    # builder (.datom_build_set_metadata()) because the field sets barely
    # overlap. It is IDENTITY -- a table and a set must not be able to share a
    # version -- which is why adding it re-mints one version for every existing
    # table on unchanged content. Accepted deliberately (see NEWS): the storage
    # address is data_sha, which does not move, so nothing is re-uploaded.
    kind = "table",
    data_sha = data_sha,
    hash_algo = "datom-cv1",
    parquet_sha = NULL,
    table_type = table_type,
    nrow = nrow(data),
    ncol = ncol(data),
    colnames = names(data),
    column_hashes = column_hashes,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    datom_version = as.character(utils::packageVersion("datom"))
  )

  if (!is.null(original_file_sha)) meta$original_file_sha <- original_file_sha
  if (!is.null(original_format)) meta$original_format <- original_format
  if (!is.null(parents)) meta$parents <- parents
  if (!is.null(source_lineage)) meta$source_lineage <- source_lineage
  if (!is.null(size_bytes)) meta$size_bytes <- size_bytes

  if (!is.null(custom)) {
    if (!is.list(custom) || is.null(names(custom))) {
      cli::cli_abort("{.arg metadata} must be a named list.")
    }
    meta$custom <- custom
  }

  meta
}


#' Build the Metadata Document for a Set Write
#'
#' A set's `metadata.json` is a collapsed version of a table's: seven fields and
#' no more. Everything a table carries that describes a rectangle (`nrow`,
#' `ncol`, `colnames`, `column_hashes`), the provenance axis (`table_type`,
#' `parents`, `source_lineage`), the stored-parquet facts (`parquet_sha`,
#' `size_bytes`) and the user-metadata channel (`custom`) are all **omitted, not
#' nulled** -- a set's members and its user metadata both live in the payload as
#' tags, and no counter reads a set's byte size.
#'
#' Kept beside [.datom_build_metadata()] on purpose: the two documents are close
#' enough that a field copied from the wrong one is easy to miss, and two of the
#' values here are exactly that kind of trap.
#'
#' * `data_sha` comes from [.datom_canonical_set_hash()], the `datom-sv1`
#'   identity engine, **not** from the table hash. Computed here rather than
#'   passed in, so a caller cannot hand a set a table-regime hash.
#' * `hash_algo` is the literal `"datom-sv1"`. The encoder embeds that string
#'   inside the digest but nothing stamps the field, so the builder must. A
#'   copied `"datom-cv1"` would leave a set claiming one regime while hashing
#'   under the other, and no hash comparison would notice.
#'
#' @param payload The set payload: a list with `members` (an unnamed list of
#'   member records) and optional set-level `tags`. Must already be tidied and
#'   validated -- this builder hashes what it is given.
#' @param document_sha SHA-256 of the stored payload bytes, or NULL. Declared
#'   either way, mirroring how [.datom_build_metadata()] declares `parquet_sha`
#'   for [datom_write()] to populate: the byte hash is not knowable until the
#'   payload has been serialized, and it is excluded from `metadata_sha`, so the
#'   deferred assignment cannot move a version. **Nothing computes one until the
#'   set write path exists**, so today it arrives NULL from every caller.
#'
#'   **The write path must populate it before writing the document.** `jsonlite`
#'   does not omit a NULL element -- it writes `{}`, which reads back as an empty
#'   list rather than an absent key. `parquet_sha` never hits this because its
#'   only two outcomes are a real hash or `meta$parquet_sha <- NULL`, and
#'   assigning NULL *removes* the element. A field left declared-and-unpopulated
#'   through a write would satisfy a names-only field-set check while carrying an
#'   empty object, so assert on the written bytes where the field set matters.
#' @return Named list of exactly the seven fields a set's `metadata.json`
#'   carries.
#' @keywords internal
.datom_build_set_metadata <- function(payload, document_sha = NULL) {
  list(
    schema_version = .datom_supported_schema,
    kind = "set",
    data_sha = .datom_canonical_set_hash(payload),
    hash_algo = "datom-sv1",
    document_sha = document_sha,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    datom_version = as.character(utils::packageVersion("datom"))
  )
}


#' Detect Changes Against Current Metadata
#'
#' Compares the proposed metadata_sha against the current version in S3.
#' Returns the type of change detected.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param new_data_sha SHA of the new data.
#' @param new_metadata_sha SHA of the new metadata (from `.datom_compute_metadata_sha()`).
#' @return Named list with two elements: `change_type` -- `"none"` (no change),
#'   `"metadata_only"` (data same, metadata changed), or `"full"` (data
#'   changed) -- and `current`, the already-read current metadata (or `NULL`
#'   for a brand-new table). Returning `current` lets [datom_write()] reuse it
#'   (the `metadata_only` `parquet_sha` carry-forward and the revert-to-older
#'   history scan) without a second storage read.
#' @keywords internal
.datom_has_changes <- function(conn, name, new_data_sha, new_metadata_sha) {
  metadata_key <- .datom_artifact_meta_key(name, "metadata")

  # If metadata doesn't exist yet, it's a new table -> full write, no current.
  if (!.datom_storage_exists(conn, metadata_key)) {
    return(list(change_type = "full", current = NULL))
  }

  current <- .datom_storage_read_json(conn, metadata_key)
  current_metadata_sha <- .datom_compute_metadata_sha(current)

  change_type <- if (identical(current_metadata_sha, new_metadata_sha)) {
    "none"
  } else if (identical(current$data_sha, new_data_sha)) {
    "metadata_only"
  } else {
    "full"
  }

  list(change_type = change_type, current = current)
}


#' Refuse to Write One Kind of Artifact Over Another
#'
#' One name means one artifact, whatever its kind, because both kinds store
#' everything under `{name}/` -- a set named `dm` beside a table named `dm` would
#' write the same `dm/.metadata/metadata.json` and each would clobber the other.
#'
#' **Checked against the metadata document in storage, not against the
#' manifest.** The manifest is a projection and can lag behind a write that got
#' partway through, so it can say a name is free when it is not. The document is
#' also the copy [.datom_has_changes()] has just read, so the comparison costs no
#' extra round trip -- which is why the current document is passed in rather than
#' fetched here.
#'
#' An absent `kind` reads as `"table"`: every document written before the field
#' existed describes a table, because sets did not exist. The pairing with a
#' format check is not needed here the way it is in `datom_member()` -- a document
#' from a future datom has already been refused at the write entry, and on the
#' read path [.datom_read_metadata()] has just checked the same document.
#'
#' **Both directions of the same invariant, in one function.** A read that meets
#' the other kind needs different words and a different suggested verb from a
#' write that does, which `operation` selects -- following
#' [.datom_check_schema_version()], which took exactly that shape for exactly
#' this reason. A separate read-side twin would let the two directions drift,
#' each passing its own tests, while the rule they enforce is single: **one name
#' is one artifact**. For the same reason both aborts carry one condition class,
#' so no test can key on one direction alone.
#'
#' The check is made by each verb after its own [.datom_read_metadata()] call
#' rather than inside that function, because the two verbs want different answers
#' from it.
#'
#' @param current The artifact's current metadata document, or `NULL` when the
#'   name is free.
#' @param name Artifact name.
#' @param expected `"table"` or `"set"` -- the kind the caller's verb handles.
#' @param operation What the caller was about to do: `"write"` (default, so
#'   existing call sites and the messages they assert on are unchanged) or
#'   `"read"`.
#' @return Invisibly `NULL`. Aborts on a kind mismatch.
#' @keywords internal
.datom_check_artifact_kind <- function(current, name, expected,
                                       operation = c("write", "read")) {
  operation <- match.arg(operation)

  if (!is.list(current)) return(invisible(NULL))

  found <- current$kind %||% "table"
  if (identical(found, expected)) return(invisible(NULL))

  # switch() rather than a named-vector lookup: `found` comes off a document, so
  # a value neither kind uses must fall through to a default instead of raising a
  # subscript error inside the function that exists to explain the problem.
  verb <- if (identical(operation, "read")) {
    switch(found, set = "datom_get_set", "datom_read")
  } else {
    switch(found, set = "datom_write_set", "datom_write")
  }

  if (identical(operation, "read")) {
    cli::cli_abort(
      c(
        "{.val {name}} is a {found}, not a {expected}.",
        "i" = "Read it with {.fn {verb}}.",
        "i" = "One name is one artifact, and the two kinds are read by \\
               different verbs: a table resolves to data, a set to references."
      ),
      class = "datom_artifact_kind_conflict"
    )
  }

  cli::cli_abort(
    c(
      "{.val {name}} already exists in this project as a {found}.",
      "i" = "One name is one artifact: both kinds store under {.val {name}} in \\
             the same namespace, so a set and a table cannot share a name.",
      "i" = "Write the existing {found} with {.fn {verb}}, or pick another name."
    ),
    class = "datom_artifact_kind_conflict"
  )
}


#' Resolve the parquet_sha to Record and Whether to Upload
#'
#' For a write that is not a no-op, decides which `parquet_sha` the new metadata
#' should carry and whether the freshly-serialized parquet bytes need uploading.
#' The caller performs the actual upload AFTER the git push (git push is the
#' serialization point); this function only decides.
#'
#' Cases:
#' * `metadata_only` -- the `data_sha` is unchanged, so the parquet object
#'   already exists; carry forward the current metadata's `parquet_sha` (which
#'   may be NULL for a pre-cv1 table, leaving the integrity check skipped) and
#'   do not upload.
#' * `full` where a prior version already recorded a `parquet_sha` for this
#'   exact `data_sha` -- the stored object exists and is pinned by that version;
#'   reuse its `parquet_sha` and do NOT re-upload (a fresh serialization can
#'   differ byte-for-byte and would break that version's integrity pin).
#' * `full` otherwise (brand-new content, or a legacy object with no recorded
#'   `parquet_sha`) -- upload these bytes and record their hash.
#'
#' This refines the design's literal step 7 (which gated on
#' `.datom_storage_exists()`): a recorded `parquet_sha` is the precise thing we
#' must not clobber, and its presence implies the object exists, so the history
#' lookup subsumes the existence check with identical behavior and one fewer
#' storage round-trip.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param data_sha Canonical content hash (the storage address).
#' @param new_parquet_sha SHA-256 of the freshly-serialized parquet bytes.
#' @param change_type `"metadata_only"` or `"full"` (never `"none"`).
#' @param current The current metadata (from [.datom_has_changes()]), or NULL.
#' @return List with `parquet_sha` (character or NULL) and `upload` (logical).
#' @keywords internal
.datom_resolve_parquet_sha <- function(conn, name, data_sha, new_parquet_sha,
                                       change_type, current) {
  # metadata_only: data_sha unchanged -> the parquet object already exists;
  # carry the current object's parquet_sha forward, no upload.
  if (identical(change_type, "metadata_only")) {
    return(list(parquet_sha = current$parquet_sha, upload = FALSE))
  }

  # change_type == "full".
  # version_history entries persist parquet_sha, so this lookup activates the
  # revert-to-older reuse branch: writing content whose data_sha already appears
  # in history reuses that version's recorded parquet_sha instead of
  # re-uploading (a fresh serialization can differ byte-for-byte and would break
  # the older version's integrity pin).
  reused <- .datom_lookup_history_parquet_sha(conn, name, data_sha)
  if (!is.null(reused)) {
    return(list(parquet_sha = reused, upload = FALSE))
  }

  list(parquet_sha = new_parquet_sha, upload = TRUE)
}


#' Resolve the document_sha to Record and Whether to Upload
#'
#' The set analogue of [.datom_resolve_parquet_sha()], kept beside it so the two
#' cannot drift: the decision is the same decision, and both are the one place
#' where "these are new bytes, so hash them" is the wrong answer.
#'
#' **Recomputing the hash from freshly emitted bytes while reusing the stored
#' object records a hash of bytes nobody stored.** Nothing fails at write time --
#' it surfaces much later as a *refused read of a valid version*, when the
#' integrity gate compares the stored payload against a hash taken from a
#' different serialization of the same content. Sets reach that state far more
#' easily than tables do: for a table it takes an `arrow` upgrade, while for a set
#' an ordinary tag-value reorder is enough, because several payload spellings
#' share one `data_sha`.
#'
#' Cases, mirroring the parquet ones:
#' * `metadata_only` -- the `data_sha` is unchanged, so the payload object already
#'   exists; carry the current metadata's `document_sha` forward and do not
#'   upload. Structurally unreachable for a set today (a set's hashed fields are
#'   `data_sha`, `hash_algo` and `kind`, so unchanged content means an unchanged
#'   version), and handled anyway rather than assumed away.
#' * `full` where a prior version already recorded a `document_sha` for this exact
#'   `data_sha` -- reuse it and do **not** re-upload.
#' * `full` otherwise -- upload these bytes and record their hash.
#'
#' @param conn A `datom_conn` object.
#' @param name Set name.
#' @param data_sha Canonical content hash (the storage address).
#' @param new_document_sha SHA-256 of the payload bytes just written to the clone.
#' @param change_type `"metadata_only"` or `"full"` (never `"none"`).
#' @param current The current metadata (from [.datom_has_changes()]), or NULL.
#' @return List with `document_sha` (character or NULL) and `upload` (logical).
#' @keywords internal
.datom_resolve_document_sha <- function(conn, name, data_sha, new_document_sha,
                                        change_type, current) {
  if (identical(change_type, "metadata_only")) {
    return(list(document_sha = current$document_sha, upload = FALSE))
  }

  reused <- .datom_lookup_history_document_sha(conn, name, data_sha)
  if (!is.null(reused)) {
    return(list(document_sha = reused, upload = FALSE))
  }

  list(document_sha = new_document_sha, upload = TRUE)
}


#' Most-recent version_history Stored-Object Hash for a data_sha
#'
#' Scans the developer's local `version_history.json` (newest-first) for the
#' most recent entry whose `data_sha` matches and that carries a non-empty hash
#' in `field`. Returns NULL when none is found. Reads the local git clone
#' (offline-friendly); a stale clone is tolerated because the subsequent git push
#' serializes concurrent writers (a behind clone fails to push before it can
#' upload).
#'
#' One scan serves both kinds, because the question is identical in each case --
#' *has this exact content already been stored, and under which byte hash?* --
#' and only the field name differs. Two copies would eventually disagree about
#' what counts as a usable recorded value, and the reuse decision they feed is
#' the one place where getting that wrong records a hash of bytes nobody stored.
#'
#' @param conn A `datom_conn` object (developer, with local path).
#' @param name Artifact name.
#' @param data_sha Canonical content hash to match.
#' @param field `"parquet_sha"` (a table's stored parquet) or `"document_sha"`
#'   (a set's stored JSON payload).
#' @return The recorded hash, or NULL.
#' @keywords internal
.datom_lookup_history_object_sha <- function(conn, name, data_sha, field) {
  history_path <- fs::path(conn$path, name, "version_history.json")
  if (!fs::file_exists(history_path)) {
    return(NULL)
  }

  # `entry[[field]]` on a list that lacks the name is a subscript error, not
  # NULL, so presence is tested before the value is taken -- and every history
  # written before the field existed lacks it.
  recorded <- function(entry) {
    if (!is.list(entry) || !(field %in% names(entry))) return("")
    value <- entry[[field]]
    if (is.character(value) && length(value) == 1L && !is.na(value)) value else ""
  }

  history <- jsonlite::read_json(history_path)

  # detect() stops at the first match, and history is newest-first, so this is
  # the most recent version that pinned this content.
  hit <- purrr::detect(history, function(entry) {
    identical(entry$data_sha %||% "", data_sha) && nzchar(recorded(entry))
  })

  if (is.null(hit)) NULL else recorded(hit)
}


#' Most-recent version_history parquet_sha for a data_sha
#'
#' The table half of [.datom_lookup_history_object_sha()]. Returns NULL for a
#' pre-cv1 history, whose entries predate `parquet_sha` being recorded.
#'
#' @inheritParams .datom_lookup_history_object_sha
#' @return Character `parquet_sha`, or NULL.
#' @keywords internal
.datom_lookup_history_parquet_sha <- function(conn, name, data_sha) {
  .datom_lookup_history_object_sha(conn, name, data_sha, "parquet_sha")
}


#' Most-recent version_history document_sha for a data_sha
#'
#' The set half of [.datom_lookup_history_object_sha()]. Unlike its parquet
#' sibling there is no legacy population to return NULL for: sets record
#' `document_sha` from their first write, which is what lets a set read treat a
#' missing one as an error rather than a skip.
#'
#' @inheritParams .datom_lookup_history_object_sha
#' @return Character `document_sha`, or NULL.
#' @keywords internal
.datom_lookup_history_document_sha <- function(conn, name, data_sha) {
  .datom_lookup_history_object_sha(conn, name, data_sha, "document_sha")
}


#' Write Metadata Files Locally
#'
#' Writes `metadata.json` and appends to `version_history.json` in the local
#' git repo. Does NOT commit, push, or touch S3 — the caller handles those.
#'
#' @param conn A `datom_conn` object (must be developer with path).
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the datom "version").
#' @param message Commit message (stored in version_history entry).
#' @param original_file_sha SHA of the source file for imported tables; NULL for derived.
#' @return Invisible list with metadata_sha and local paths written.
#' @keywords internal
.datom_write_metadata_local <- function(conn, name, metadata, metadata_sha,
                                       message = NULL,
                                       original_file_sha = NULL) {
  repo_path <- conn$path
  table_dir <- fs::path(repo_path, name)
  fs::dir_create(table_dir)

  # metadata.json — current state
  metadata_path <- fs::path(table_dir, "metadata.json")
  jsonlite::write_json(metadata, metadata_path, auto_unbox = TRUE, pretty = TRUE)

  # version_history.json — append new entry
  history_path <- fs::path(table_dir, "version_history.json")

  history <- if (fs::file_exists(history_path)) {
    jsonlite::read_json(history_path)
  } else {
    list()
  }

  author <- tryCatch(
    .datom_git_author(repo_path),
    error = function(e) "unknown"
  )

  new_entry <- list(
    version = metadata_sha,
    data_sha = metadata$data_sha,
    timestamp = metadata$created_at,
    author = author,
    commit_message = message %||% paste0("Update ", name)
  )

  # Persist parquet_sha alongside original_file_sha so the stored-object
  # integrity hash travels with each version -- it powers the revert-to-older
  # reuse scan (.datom_lookup_history_parquet_sha) and version-pinned read
  # integrity (.datom_resolve_version). Added only when non-NULL to keep
  # pre-cv1 / metadata_only-carrying-NULL entries clean.
  if (!is.null(metadata$parquet_sha)) {
    new_entry$parquet_sha <- metadata$parquet_sha
  }

  # The same field for a set's stored JSON payload, on the same conditional-add
  # terms, so every version of a set carries the hash of the bytes that version
  # pinned. It is here from day one deliberately: sets then never need the
  # "older entries lack it, skip the check" grace that `parquet_sha` carries for
  # pre-cv1 tables, and a set read can treat an absent `document_sha` as an
  # error instead of building a silent-degradation path.
  #
  # INERT UNTIL THE SET WRITE PATH LANDS: nothing computes a `document_sha` yet,
  # so no metadata document reaching this function carries one.
  if (!is.null(metadata$document_sha)) {
    new_entry$document_sha <- metadata$document_sha
  }

  if (!is.null(original_file_sha)) {
    new_entry$original_file_sha <- original_file_sha
  }

  # Full-history dedup guard (Requirement 12): scan the ENTIRE history for an
  # entry whose version already equals this metadata_sha, not just the latest.
  # This is the S4 fix -- re-syncing an older-but-content-matching file must not
  # append a duplicate version that would later make datom_read(version=)
  # ambiguous. O(history) with early exit; the current pointer (metadata.json)
  # is still written above regardless.
  exists_already <- purrr::some(
    history, ~ identical(.x$version %||% "", metadata_sha)
  )
  # The new entry is PREPENDED and the existing ones are carried through
  # untouched, which is also what keeps a field this build cannot place alive on
  # an older entry -- there is no rebuild here to lose it. Do not "normalise"
  # these entries on the way past: they describe versions this build may know
  # nothing about, and an entry rewritten to today's field set would silently
  # drop whatever a newer datom recorded on it.
  if (!exists_already) {
    history <- c(list(new_entry), history)
  }
  jsonlite::write_json(history, history_path, auto_unbox = TRUE, pretty = TRUE)

  invisible(list(
    metadata_sha = metadata_sha,
    git_paths = c(metadata_path, history_path)
  ))
}


#' Push Metadata Files to S3
#'
#' Uploads `metadata.json`, `version_history.json`, and a versioned snapshot
#' to S3. Called AFTER git commit+push succeeds to maintain local → git → S3
#' ordering.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the datom "version").
#' @return Invisible character vector of S3 keys written.
#' @keywords internal
.datom_push_metadata_s3 <- function(conn, name, metadata, metadata_sha) {
  # Read local version_history.json (written by .datom_write_metadata_local)
  history_path <- fs::path(conn$path, name, "version_history.json")
  history <- if (fs::file_exists(history_path)) {
    jsonlite::read_json(history_path)
  } else {
    list()
  }

  s3_metadata_key <- .datom_artifact_meta_key(name, "metadata")
  s3_history_key <- .datom_artifact_meta_key(name, "version_history")
  s3_versioned_key <- .datom_artifact_snapshot_key(name, metadata_sha)

  .datom_storage_write_json(conn, s3_metadata_key, metadata)
  .datom_storage_write_json(conn, s3_history_key, history)
  .datom_storage_write_json(conn, s3_versioned_key, metadata)

  invisible(c(s3_metadata_key, s3_history_key, s3_versioned_key))
}


#' Commit, Push, Then Mirror to Storage
#'
#' The tail of every artifact write, in the one order that is allowed: local
#' files are already on disk, this commits and pushes them, and only then does it
#' touch storage. **Git push is the serialization point** -- a clone that is
#' behind fails to push before it can upload anything, which is what makes the
#' reuse decisions in `.datom_resolve_parquet_sha()` /
#' `.datom_resolve_document_sha()` safe against a concurrent writer. Nothing may
#' reorder these two halves.
#'
#' Extracted when the set write arrived, and the extraction is the point rather
#' than tidiness: this sequence was previously inline in [datom_write()], so a
#' second write verb had to either call it or grow a parallel copy -- and a second
#' copy of "git must succeed before storage is touched" is a second place for that
#' rule to be broken by a change that only looks at one of them.
#'
#' @param conn A `datom_conn` object (developer, with a local path).
#' @param name Artifact name.
#' @param meta The metadata document to mirror.
#' @param metadata_sha The version being written.
#' @param git_paths Absolute paths of the files this write produced in the clone.
#'   `.datom/manifest.json` is added here rather than by each caller, since every
#'   write updates it.
#' @param message Commit message.
#' @param upload Optional `list(path =, key =)` naming a payload object to upload
#'   after the push -- the freshly serialized parquet for a table, the payload
#'   JSON for a set. `NULL` when the object is already stored and must not be
#'   rewritten.
#' @return The commit SHA.
#' @keywords internal
.datom_commit_and_mirror <- function(conn, name, meta, metadata_sha, git_paths,
                                     message, upload = NULL) {
  git_files <- c(
    fs::path_rel(git_paths, conn$path),
    ".datom/manifest.json"
  )
  commit_sha <- .datom_git_commit(conn$path, git_files, message)
  .datom_git_push(conn$path, pat = conn$github_pat)

  # After git, never before. `upload = NULL` is the reuse case: the object at
  # this address is already stored and re-writing it would break the
  # integrity hash recorded against it by the version that put it there.
  if (!is.null(upload)) {
    .datom_storage_upload(conn, upload$path, upload$key)
  }

  .datom_push_metadata_s3(conn, name, meta, metadata_sha)

  # The manifest completes the round trip. Read back from the clone rather than
  # passed in, so the mirrored copy is exactly the committed one.
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")
  if (fs::file_exists(manifest_path)) {
    manifest_data <- jsonlite::read_json(manifest_path)
    .datom_storage_write_json(conn, ".metadata/manifest.json", manifest_data)
  }

  commit_sha
}


#' Write Metadata Files to Git and S3 (Legacy Wrapper)
#'
#' Calls [.datom_write_metadata_local()] then [.datom_push_metadata_s3()].
#' Kept for backward compatibility. Does NOT commit or push.
#'
#' @inheritParams .datom_write_metadata_local
#' @return Invisible list with metadata_sha, git_paths, and s3_keys.
#' @keywords internal
.datom_write_metadata <- function(conn, name, metadata, metadata_sha, message = NULL) {
  local_result <- .datom_write_metadata_local(
    conn, name, metadata, metadata_sha, message = message
  )
  s3_keys <- .datom_push_metadata_s3(conn, name, metadata, metadata_sha)

  invisible(list(
    metadata_sha = metadata_sha,
    git_paths = local_result$git_paths,
    s3_keys = s3_keys
  ))
}


#' Write a datom Table
#'
#' Writes data to a datom repository. Commits to git, pushes, and syncs to S3.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param data Data frame to write. If NULL with name, does metadata-only sync.
#' @param name Table name. If NULL with NULL data, does a data-only metadata
#'   sync to storage (manifest + per-table metadata).
#' @param metadata Optional list of custom metadata.
#' @param message Optional commit message.
#' @param parents Optional list of parent records produced by
#'   [datom_parent()], each carrying `source`, `table`, `version`,
#'   `data_sha`, and `source_lineage`. When supplied, the table's
#'   `source_lineage` is derived as the deduplicated union of the parents'
#'   `source_lineage` and each parent is recorded lean (`source`, `table`,
#'   `version`, `data_sha`). NULL if no lineage is recorded. There is no
#'   public `source_lineage` parameter; it is always derived from `parents`.
#' @param .source_lineage Internal. Flat list of transitive non-derived
#'   source descriptors (each with `project`, `table`, `version_sha`) for the
#'   imported self-entry path, set by [datom_sync()]. Unused on the derived
#'   (parents) path.
#' @param .table_type Internal. `"derived"` (default) or `"imported"`
#'   (set by `datom_sync()`).
#' @param .original_file_sha Internal. SHA of source file
#'   (set by `datom_sync()`); NULL for derived.
#' @param .original_format Internal. Original file format
#'   (set by `datom_sync()`); NULL for derived.
#'
#' @return List with deployment details.
#' @export
#'
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # --- Basic write (no lineage) ---
#'   dm <- datom_example_data("dm")
#'   datom_write(conn, data = dm, name = "dm")
#'
#'   # --- Write with a single parent ---
#'   # Each parent's data_sha and lineage are resolved by datom_parent.
#'   lb <- datom_example_data("lb")
#'   datom_write(conn, data = lb, name = "lb")
#'   lb_summary <- aggregate(
#'     list(n = lb$LBTESTCD), by = list(LBTESTCD = lb$LBTESTCD), FUN = length
#'   )
#'   datom_write(
#'     conn,
#'     data    = lb_summary,
#'     name    = "lb_summary",
#'     message = "Lab test counts",
#'     parents = list(
#'       datom_parent(conn, "lb", datom_history(conn, "lb")$version[1])
#'     )
#'   )
#'
#'   # --- Write with multiple parents ---
#'   # The source lineage is derived as the union of the parents' lineages.
#'   dm_lb_merged <- merge(dm, lb, by = "USUBJID")
#'   datom_write(
#'     conn,
#'     data    = dm_lb_merged,
#'     name    = "dm_lb_merged",
#'     message = "Demographics joined with lab results",
#'     parents = list(
#'       datom_parent(conn, "dm", datom_history(conn, "dm")$version[1]),
#'       datom_parent(conn, "lb", datom_history(conn, "lb")$version[1])
#'     )
#'   )
#'
#'   print(datom_list(conn))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_write <- function(conn,
                       data = NULL,
                       name = NULL,
                       metadata = NULL,
                       message = NULL,
                       parents = NULL,
                       .source_lineage = NULL,
                       .table_type = "derived",
                       .original_file_sha = NULL,
                       .original_format = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("conn must be a datom_conn object from datom_get_conn()")
  }

  # Forward-compatibility door. Above the routing returns on purpose: one of the
  # routes mirrors the whole local manifest to storage and never reaches the
  # manifest-writing step, so a check placed after the router would not cover
  # it. Above the hashing and the local writes too, so a refusal leaves nothing
  # half-written.
  #
  # `name` is NULL on the mirror-everything route, which is what tells the check
  # to inspect every artifact in the clone rather than one.
  .datom_check_write_entry(conn, name)

  # Route based on arguments

  if (is.null(data) && is.null(name)) {
    return(.datom_sync_data_metadata(conn))
  }

  if (is.null(data) && !is.null(name)) {
    return(.datom_sync_metadata(conn, name))
  }

  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  .datom_validate_name(name)

  # Parents must be resolved datom_parent() records. Derive the table's
  # source_lineage from their union and record lean parent edges. When no
  # parents are given, use the internal .source_lineage (imported path).
  if (!is.null(parents)) {
    .datom_validate_parents(parents)
    parent_lineages <- lapply(parents, function(p) p$source_lineage)
    source_lineage <- datom_lineage_union(parent_lineages)
    parents <- lapply(parents, function(p) list(
      source   = p$source,
      table    = p$table,
      version  = p$version,
      data_sha = p$data_sha
    ))
  } else {
    source_lineage <- .source_lineage
    .datom_validate_source_lineage(source_lineage)
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Write operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Write operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # 0. Write-time ref guard: ensure data location hasn't changed
  .datom_check_ref_current(conn)

  # 1. Canonical content hash: data_sha (the storage address) + the per-column
  #    index, in one pass. The all-offenders abort fires here -- before any
  #    git/storage/manifest mutation -- so a refusal leaves no partial state.
  hashed <- .datom_canonical_hash(data)
  data_sha <- hashed$data_sha

  # 2. Serialize parquet to a temp file; capture its size and the stored-object
  #    integrity hash (parquet_sha) of these exact bytes.
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)
  arrow::write_parquet(data, tmp)
  size_bytes <- as.numeric(fs::file_size(tmp))
  new_parquet_sha <- digest::digest(file = tmp, algo = "sha256")

  # 3. Build metadata. parquet_sha is set in step 5 (after change detection);
  #    it is excluded from metadata_sha, so this deferral does not affect the
  #    version identity.
  meta <- .datom_build_metadata(
    data, data_sha,
    custom = metadata,
    table_type = .table_type,
    parents = parents,
    source_lineage = source_lineage,
    size_bytes = size_bytes,
    original_file_sha = .original_file_sha,
    original_format = .original_format,
    column_hashes = hashed$column_hashes
  )
  metadata_sha <- .datom_compute_metadata_sha(meta)

  # 4. Change detection (reuses the already-read current metadata).
  chg <- .datom_has_changes(conn, name, data_sha, metadata_sha)
  change_type <- chg$change_type

  # 4a. One name is one artifact. Writing a table over an existing set would
  #     clobber that set's metadata and history, so it is refused here -- on the
  #     document change detection has just read, before anything is written.
  .datom_check_artifact_kind(chg$current, name, "table")

  if (change_type == "none") {
    cli::cli_alert_info(
      "No changes detected for {.val {name}}. Skipping write."
    )
    return(invisible(list(
      name = name,
      data_sha = data_sha,
      metadata_sha = metadata_sha,
      action = "none"
    )))
  }

  # 5. Decide the parquet_sha to record and whether these bytes need uploading.
  #    The upload itself stays AFTER the git push (step 8); this only decides.
  parquet_decision <- .datom_resolve_parquet_sha(
    conn, name, data_sha, new_parquet_sha, change_type, chg$current
  )
  meta$parquet_sha <- parquet_decision$parquet_sha

  # 5a. Keep any top-level field the existing metadata document holds that this
  #     build cannot place -- step 3 rebuilt the document from scratch, which
  #     would otherwise delete it.
  #
  #     Placed here rather than in step 3 for the same reason parquet_sha is:
  #     metadata_sha has already been computed. Identity ignores fields it does
  #     not name, so either position gives the same hash today, but attaching
  #     after the fact means a carried field cannot reach a hash at all -- no
  #     later change to the identity field list can pull one in.
  meta <- .datom_carry_unknown_fields(
    meta,
    .datom_prior_metadata(conn, name),
    .datom_metadata_known_fields()
  )

  # 6. Write metadata + manifest locally
  write_result <- .datom_write_metadata_local(
    conn, name, meta, metadata_sha,
    message = message,
    original_file_sha = .original_file_sha
  )
  .datom_update_manifest_entry(
    conn, name,
    metadata_sha = metadata_sha,
    data_sha = data_sha,
    original_file_sha = .original_file_sha,
    format = .original_format
  )

  # 7. Commit + push, then mirror to storage -- in that order, shared with
  #    datom_write_set(). The parquet upload is handed over as the payload object,
  #    and is skipped entirely when step 5 decided the stored one must be reused.
  commit_sha <- .datom_commit_and_mirror(
    conn, name, meta, metadata_sha,
    git_paths = write_result$git_paths,
    message = message %||% paste0("Update ", name),
    upload = if (isTRUE(parquet_decision$upload)) {
      list(path = tmp, key = .datom_artifact_payload_key(name, data_sha, "table"))
    } else {
      NULL
    }
  )

  cli::cli_alert_success(
    "Wrote {.val {name}} ({change_type}): {.val {substr(metadata_sha, 1, 8)}}"
  )

  invisible(list(
    name = name,
    data_sha = data_sha,
    metadata_sha = metadata_sha,
    action = change_type,
    commit_sha = commit_sha
  ))
}
