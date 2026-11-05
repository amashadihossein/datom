# datom lanes: principles and examples

Draft, 2026-11-04, for checking against the dpdev design conversation. Not a spec yet: no
requirements, design or tasks have been written or approved. It describes where #156 (only the
publish branch writes to storage) is heading after a discussion with the owner on 2026-11-03/04;
#156 as filed says "refuse on other branches", and this revises that to "write to a private lane".

## Terms

- **Store**: where datom keeps a project's data and the documents readers use (each table's
  `metadata.json`, its version history, version snapshots, and the project manifest).
- **Record**: those documents taken together: which versions exist and which one is current.
- **Publish branch**: the branch named when the project is created (`datom_init_repo(...,
  publish_branch = "main")`).
- **Version ID**: the hash datom gives a version. It covers the content, column names, custom
  metadata, parents (with their versions), lineage and table type. It does not cover time, the
  datom version, the stored bytes, or where the data is stored.

## Principles

1. **One branch per store.** Every store is written by exactly one branch. Trouble starts when two
   branches land in the same store, so datom never lets that happen.

2. **Two kinds of lane.**
   - The **public lane** is permanent and shared. It is the publish branch, writing to the shared
     store. Everyone reads from it.
   - A **private lane** is ephemeral and personal. It is any other branch, writing to its own
     store (local for now; another space later). Nobody else reads from it, and deleting the
     branch and its store leaves nothing behind.

3. **The lane decides whether the record is tracked in git.** There is no separate switch.
   - Public lane: tracked. datom's files are committed and pushed, then published to the shared
     store. Git is how teammates agree, and how a re-run finds where it stopped.
   - Private lane: not tracked. The same documents are generated, but they are written only to
     the lane's store. The clone's datom files are never touched, so git sees only code.

4. **The branch decides the lane, automatically.** Every write compares the current branch with
   the publish branch. A match means the public lane; anything else means that branch's private
   lane. The write commands are the same in both.

5. **A private lane starts from the public lane.** It reads its inputs (imports, the input set,
   other projects) from the public lane. Anything the branch has not built itself is read from
   the public lane too. Only what the branch builds goes to its own store.

6. **The merge carries code only.** Private-lane writes never touch git, so merging a branch
   brings over its code and nothing else.

7. **Data reaches the public lane by rebuilding, never by copying.** After the merge, the
   derivations run again on the publish branch. Because the version ID ignores where data is
   stored, a deterministic build gets the same IDs it got in the private lane. The public lane's
   result is the one that counts.

8. **A re-run finishes the job** (#155). If a write breaks partway, running the same write again
   completes it, in either lane. In the public lane, a write repairs only its own table or set; if
   it finds another one's unfinished work, it stops and names `datom_validate(fix = TRUE)`.

9. **Some commands exist only in the public lane.** The repair (`datom_validate(fix = TRUE)`),
   changing the data store, attaching governance, and releases (#154) are refused on any other
   branch.

10. **datom does not depend on any build tool.** Where a build keeps intermediate results, and
    which steps it re-runs after a failure, are the build layer's business (dpdev, which may use
    targets for task management). datom only promises principles 1-9.

## Examples

### A. Inputs updated, logic unchanged: stay in the public lane

New raw files arrive for `dm` and `lb`. Nothing in the derivations changes.

1. On `main`: `datom_sync()` imports the new `dm` and `lb` versions.
2. Build the input set, citing those versions.
3. Run the derivations (`adsl`, `adae`, then the product set) on `main`. Each write commits,
   pushes and publishes to the shared store.

No branch is needed, and readers see the new versions as each write finishes.

### B. Changing a derivation: experiment in a private lane

You want to change how `adsl` is derived.

1. `git checkout -b adsl-rework`.
2. Edit the code. Run the build. `datom_write(conn, adsl_new, "adsl")` sees it is not on `main`,
   so it writes `adsl` and its record to the `adsl-rework` store only. Inputs (`dm`, `lb`, the
   input set) are read from the public lane.
3. `adae` depends on `adsl`. Its write reads the new `adsl` from the private lane, because the
   branch built it, and writes `adae` to the private lane too.
4. Iterate until it looks right. Your commits contain only code.
5. Open a pull request. A reviewer or CI checks out the branch and runs the same build. They get
   their own private lane and, with deterministic code, the same version IDs you got.
6. Merge into `main` and push. The merge contains only code.
7. On `main`, run the build. The same write calls now commit, push and publish to the shared
   store, and land the same version IDs.
8. Delete the branch and its private store.

### C. A failure in the public lane

On `main`, the build's write of `adae` loses the network halfway.

1. The build tool reports the failed step.
2. Re-run that step. The write of `adae` finds its own unfinished work and finishes it.
3. If something else ran first and found `adae`'s unfinished work, it stops with a message naming
   `datom_validate(fix = TRUE)`. Run that, then carry on.

### D. A command that only makes sense in the public lane

On `adsl-rework`, you run `datom_validate(fix = TRUE)`. datom refuses and says to switch to `main`.
A private lane needs no repair: if something there looks wrong, delete its store and rebuild.

### E. Results differ between lanes

A teammate merged a change to `dm`'s import while your branch was open. After your merge, the
build on `main` gets different version IDs than your private lane did. That is expected: the
public lane's run is authoritative. If IDs differ with no input change, the build is not
deterministic (an unfixed random seed, or a timestamp passed in `metadata =`).

## Open, or not yet decided

- **How the private store is chosen.** The default is probably a local folder outside git, keyed by
  branch name. Whether a later "shared test space" is a store named on the connection is open.
- **Old projects.** Projects created before the publish branch is recorded are not migrated. To
  keep writing one, install the earlier datom release, or start a new project with this release
  (history is not carried over).
- **Computing a version ID without writing.** A possible later addition so a pull request can show
  which IDs a merge would land. Not needed for the principles above.
- **Same project name in both lanes.** The version ID includes each parent's project name, so the
  private and public lanes must be the same project for IDs to match. With the design above they
  are, since a lane is a branch of the same project, not a new project.
