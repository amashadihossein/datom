# daapr: Data-as-a-Product Framework

## Executive Summary

daapr is an R framework implementing the Data-as-a-Product (DaaP) methodology, bringing together data and code joint versioning with automated workflow management. The framework enables clinical and scientific teams to create reproducible, version-controlled data products through an orchestrated set of packages.

This document describes the architectural vision for the next generation of daapr, including a significant refactoring to enable cross-language compatibility and address current limitations.

---

## Current State

### Package Ecosystem

daapr provides a comprehensive framework through three core packages:

| Package | Purpose |
|---------|---------|
| **dpbuild** | Streamlines building data products |
| **dpdeploy** | Manages deployment of data products |
| **dpi** | Provides interfaces for accessing data products |

### Key Capabilities

- Joint versioning of data and code through Git integration
- Automated workflow management with optional targets integration
- Computational environment management via renv
- Standard metadata collection and management
- Separation of code (GitHub) and data (S3/cloud) storage
- Uses pins package for data storage and versioning interface

### Data Product Structure (Current)

```r
dp$output$mydata1          # Direct access to output data (cached in memory)
dp$output$mydata2          # Additional output tables
dp$input$myinput1()        # Function calls for input data
dp$input$myinput_n()       # Lazy-loaded inputs via pins
```

### Strengths

1. **Comprehensive Integration**: Orchestrates established R packages (pins, targets, renv) into cohesive workflow
2. **Clinical Research Optimized**: Sweet spot for <1TB datasets, perfect for clinical trials (<1GB typical)
3. **Automated Workflow**: Minimizes manual steps in data product lifecycle
4. **Version Control**: Joint tracking of data and code changes
5. **Reproducibility**: Strong focus on computational environment consistency
6. **R Ecosystem Native**: Deep integration with R best practices

### Current Limitations

| Limitation | Impact |
|------------|--------|
| **R-Only Ecosystem** | Excludes Python data scientists and mixed-language teams |
| **RDS Storage Format** | Data stored as R lists, not accessible to other languages |
| **Memory Bottleneck** | Output storage requires entire RDS to be cached in memory |
| **Limited Discoverability** | Only available via GitHub, not on CRAN |

---

## Architectural Vision

### The Core Problem

Data products stored as R lists in RDS format creates multiple barriers:

- Python pins implementation cannot read RDS files
- Nested R list structure not accessible from other languages
- Entire RDS object must be cached in memory for access
- Limits potential user base to R-only environments

### The Solution: datom + Language-Agnostic Storage

The architectural shift centers on replacing the pins-based storage with **datom**, a new foundational package that provides:

1. **Git-First Metadata**: All metadata in git, synced to S3 for readers
2. **Parquet Storage**: Cross-language data format with excellent compression
3. **Implicit Location**: Redirect chain enables seamless migration
4. **Routing Layer**: Flexible dispatch enabling future extensions

See **[datom Package Specification](./datom_specification.md)** for complete details.

### Before and After

```
CURRENT ARCHITECTURE                    NEW ARCHITECTURE
┌─────────────────────┐                 ┌─────────────────────┐
│      dpbuild        │                 │      dpbuild        │
│    (builds DPs)     │                 │    (builds DPs)     │
└──────────┬──────────┘                 └──────────┬──────────┘
           │                                       │
           ▼                                       ▼
┌─────────────────────┐                 ┌─────────────────────┐
│       pins          │                 │       datom          │
│  (RDS, R-only)      │                 │  (Parquet, JSON)    │
└──────────┬──────────┘                 └──────────┬──────────┘
           │                                       │
           ▼                                       ▼
┌─────────────────────┐                 ┌─────────────────────┐
│         S3          │                 │    S3 + Git         │
│   (data + metadata) │                 │  (data)  (metadata) │
└─────────────────────┘                 └─────────────────────┘
```

---

## Package Architecture (New)

### Dependency Structure

```
┌─────────────────────────────────────────────────────────────┐
│                        daapr                                │
│              (meta-package, installs all)                   │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│    dpbuild      │ │    dpdeploy     │ │      dpi        │
│  (build logic)  │ │  (deployment)   │ │   (interface)   │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             ▼
                   ┌─────────────────┐
                   │      datom       │
                   │  (versioning)   │
                   └─────────────────┘
```

### Package Responsibilities

| Package | Responsibility | Key Changes |
|---------|---------------|-------------|
| **datom** | Version-controlled table storage | NEW: Replaces pins dependency |
| **dpbuild** | Data product construction | MODIFIED: Uses datom instead of pins |
| **dpdeploy** | Deployment orchestration | MODIFIED: Deploys datom-based products |
| **dpi** | Data product access | MODIFIED: Reads from datom |
| **daapr** | Meta-package | UNCHANGED: Installs ecosystem |

---

## Data Product Structure (New)

### Unified Access Pattern

Both inputs and outputs become function calls, eliminating the memory bottleneck:

```r
# New structure — both inputs and outputs are lazy-loaded
dp$output$mydata1()        # Function call (was: direct access)
dp$output$mydata2()        # Function call
dp$input$myinput1()        # Function call (unchanged)
dp$input$myinput_n()       # Function call (unchanged)
```

### Cross-Language Access

The same data product becomes accessible from Python:

```python
# Python access (new capability)
dp.output.mydata1()        # Mirror interface
dp.output.mydata2()
dp.input.myinput1()
```

### Storage Format

| Component | Format | Location |
|-----------|--------|----------|
| Data | Parquet | S3 (content-addressed by SHA) |
| Metadata | JSON | Git (authoritative) + S3 (cached) |
| Routing | JSON (routing.json) | Git + S3 |
| Migration | JSON (.redirect.json) | S3 (old bucket only) |

---

## User Roles and Access

### Separation of Concerns

datom introduces a clean separation between data developers and data readers:

| Role | Credentials | Capabilities |
|------|-------------|--------------|
| **Data Developer** | AWS + GITHUB_PAT | Create, update, version data |
| **Data Reader** | AWS only | Read any version, no git needed |
| **Data Product** | AWS only | Consume versioned inputs |

This separation simplifies access for consumers while maintaining full version control for developers.

---

## Migration Support

### Redirect-Based Continuity

When data moves between buckets, old code continues working via redirect chain:

```
Old bucket (post-migration):
└── .redirect.json → points to new bucket

Reader with old code:
1. Connects to old bucket
2. Finds .redirect.json
3. Follows to new bucket
4. Reads data seamlessly
```

**Credential requirement**: Old code needs credentials for both buckets. Updating code to point directly to new bucket avoids this.

See datom specification for detailed migration workflow.

---

## Migration Strategy

### Breaking Change Approach

Given the complexity of the current system, a clean break is preferred over maintaining backward compatibility:

1. **New major version**: daapr 1.0 with datom-based architecture
2. **Clear migration path**: Documentation for converting existing data products
3. **No hybrid mode**: Avoids compounding complexity

### Migration Steps for Existing Data Products

1. Export current data to source files (CSV/Parquet)
2. Initialize new datom repository
3. Sync source files to create datom-versioned tables
4. Update dpbuild configuration
5. Redeploy data product

---

## Development Roadmap

### Phase 1: Foundation (Current Focus)

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| 1 | datom R package | 4-6 weeks | Critical |
| 2 | dpbuild integration | 2-3 weeks | Critical |
| 3 | dpdeploy updates | 1-2 weeks | High |
| 4 | dpi updates | 1-2 weeks | High |

### Phase 2: Ecosystem

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| 5 | CRAN publication | 1-2 weeks | Medium-High |
| 6 | Documentation & migration guides | 2 weeks | High |
| 7 | Python datom implementation | 2-3 weeks | High |

### Phase 3: Enhancement

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| 8 | datom_auth (access control) | 2-3 weeks | Medium |
| 9 | datom_cache (performance) | 1-2 weeks | Medium |
| 10 | AI assistant package | 2-3 weeks | Medium |
| 11 | Additional cloud backends | 2-3 weeks | Medium |

---

## Competitive Positioning

### Landscape

| Tool | Strengths | daapr Differentiator |
|------|-----------|---------------------|
| **DVC** | Language-agnostic, Git-like | daapr: Deeper R integration, clinical focus |
| **MLflow** | Comprehensive ML lifecycle | daapr: Data products, not just models |
| **lakeFS** | Enterprise scale | daapr: Simpler, scientist-friendly |
| **pins + targets** | Individual tools | daapr: Orchestrated methodology |

### Target Use Cases

daapr is optimized for:

- Clinical trial data management
- Scientific research workflows
- Datasets with many tables (50-100+)
- Data products in the MB to low-GB range
- Teams requiring reproducibility and auditability
- Mixed R/Python environments (with new architecture)

---

## Technical Specifications

### datom Package

The foundational layer for version-controlled table storage. See **[datom Package Specification](./datom_specification.md)** for:

- Complete API reference
- Metadata schema definitions (metadata.json, version_history.json, manifest.json, routing.json)
- Storage architecture and location resolution
- User workflows including migration
- Implementation details

### Integration Points

**dpbuild → datom**:
```r
# dpbuild creates data products using datom for storage
dp_build(
  inputs = list(
    customers = datom_ref("customers", version = "abc123")
  ),
  outputs = list(
    summary = my_summary_table
  )
)
```

**dpi → datom**:
```r
# dpi reads data products via datom routing
dp <- dp_get("my_product", version = "1.0.0")
data <- dp$output$summary()  # Routed through datom_read
```

---

## Design Principles

### Guiding Philosophy

1. **Reproducibility First**: Every output traceable to inputs and code
2. **Scientist-Friendly**: Minimize DevOps burden on researchers
3. **Auditable**: Full lineage for regulatory compliance
4. **Extensible**: Clean extension points for enterprise features
5. **Pragmatic**: Optimized for real clinical/scientific workflows

### Non-Goals

- Replacing general-purpose data lakes
- Real-time streaming data
- Multi-TB analytical workloads
- Replacing MLflow for model lifecycle

---

## Summary

The daapr framework evolution centers on replacing the pins-based storage layer with datom, enabling:

1. **Cross-language access**: Python and R can share data products
2. **Better performance**: Lazy-loading eliminates memory bottleneck
3. **Modern storage**: Parquet format with excellent tooling support
4. **Cleaner architecture**: Git-first metadata, content-addressed storage
5. **Simpler access**: Data readers don't need GitHub credentials
6. **Seamless migration**: Redirect chain preserves old code functionality

This is a breaking change that simplifies the overall system while expanding its reach to polyglot data science teams.

---

## References

- **[datom Package Specification](./datom_specification.md)**: Detailed technical specification
- **[Current daapr Documentation](https://amashadihossein.github.io/daapr/)**: Existing vignettes and guides
- **[dpbuild Repository](https://github.com/amashadihossein/dpbuild)**: Build package source
- **[dpdeploy Repository](https://github.com/amashadihossein/dpdeploy)**: Deploy package source
- **[dpi Repository](https://github.com/amashadihossein/dpi)**: Interface package source
