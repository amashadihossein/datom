# datom: A Unified Framework for Versioned, Traceable Tabular Data

Provides versioned storage for tabular data without a database or a
server. Each table is written as an immutable, content-addressed version
– identical content is detected and stored only once – while its version
history and metadata are kept as code in a 'git' repository and the data
itself in a local filesystem or cloud object storage ('S3'). Any past
version can be read back exactly by its identifier, and each table
records the sources it was derived from, so a project carries full data
lineage. A lightweight reader role retrieves current or historical data
from storage alone, without 'git' or write access, giving downstream
analyses and pipelines a single versioned source of truth. It targets
analytical and scientific data management, such as preparing clinical
study datasets, and is designed as a foundation for higher-level
governance tooling.

## Key terms

- **Project**: one body of data you manage together, such as one
  clinical study. It has a name, a GitHub repository that records every
  change, and a storage location that holds the data itself; the data
  never goes into git. Created once with
  [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md).

- **Store**: tells datom where a project's data lives (a local folder or
  an S3 bucket) and, if you will write, your GitHub token. Built with
  [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md).

- **Developer and reader**: the two roles. A developer has a GitHub
  token and a local copy of the project, and can write. A reader needs
  only access to the storage – no token, no git – and can only read.
  datom picks the role from whether the store carries a token.

- **Connection (`conn`)**: a pointer to one project, returned by
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).
  It records which project, where its data is kept, and your role, and
  it is the first argument to almost every other function.

- **Table**: a data frame saved in datom under a name, such as `dm`.
  Saved with
  [`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
  or
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md),
  read with
  [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md).

- **Version**: a long identifier for one exact saved state of a table or
  a set. Old versions are never overwritten, and a save that changes
  nothing makes no new version.
  [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
  lists them; pass one as `version =` to read it back.

- **Sync manifest**: the preview
  [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
  returns – one row per file in `input_files/`, each marked new,
  changed, unchanged, or in a format datom cannot read – which you then
  pass to
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md).

- **Set**: a named, versioned list of exact versions of tables (or other
  sets), so a whole collection can be cited with one version string. It
  holds no data.

- **Member**: one entry in a set – one table or set, pinned at one
  version, with optional labels such as `type = "input"`.

- **Parent, source and lineage**: a parent is a table another table was
  made from, named with
  [`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
  before writing. A source is an original imported table at the start of
  the chain. Lineage is the record of both, read with
  [`datom_get_lineage()`](https://amashadihossein.github.io/datom/reference/datom_get_lineage.md).

## See also

Useful links:

- <https://github.com/amashadihossein/datom>

- <https://amashadihossein.github.io/datom/>

- Report bugs at <https://github.com/amashadihossein/datom/issues>

## Author

**Maintainer**: Afshin Mashadi-Hossein <amashadihossein@gmail.com>
\[copyright holder\]
