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

## See also

Useful links:

- <https://github.com/amashadihossein/datom>

- <https://amashadihossein.github.io/datom/>

- Report bugs at <https://github.com/amashadihossein/datom/issues>

## Author

**Maintainer**: Afshin Mashadi-Hossein <amashadihossein@gmail.com>
