# roundhouse-rb/spin-index

A curated package index for [Spinel](https://github.com/matz/spinel)'s
`spin` tool. It uses the same format as
[matz/spin-index](https://github.com/matz/spin-index) and carries
everything that index carries, plus releases still waiting there. Every
release is tested daily against Spinel master.

```sh
export SPIN_INDEX=https://github.com/roundhouse-rb/spin-index
```

Then a bare `name = "constraint"` dependency in `spin.toml` resolves here.
This needs Spinel 22de42432 or later; older `spin` binaries keep one index
cache for every URL, so remove `~/.cache/spin/index` once before switching.

## Why it exists, and for how long

We started this on 2026-10-17 because matz/spin-index has merged nothing
since 2026-07-09, and releases were piling up behind it: an indexed
version that no longer builds on current Spinel had its fix waiting in a
pull request for weeks.

We don't yet know whether this index is a stopgap or a lasting resource.
Either way:

- **Same names, same format.** An entry here is never a different library
  from the entry with that name upstream, and the check job fails if a
  shared release's commit differs.
- **Everything here is also offered upstream.** If matz/spin-index starts
  moving again, the two stay in step.
- **Leaving is free.** `spin.lock` records each package's repository and
  commit, not the index that chose it, so a locked build doesn't depend on
  this index. If it's ever retired, this README will say so first.

## What "curated" means

- **Every release is probed, every day.** `.github/workflows/probe.yml`
  builds Spinel master and runs `spin test` on every release, live
  database and Redis lanes included. A result that changes is committed
  as a `[[probe]]` entry, which `spin` reads when it selects a release: a
  fail recorded for your compiler build is a strong warning, and a release
  whose newest probe is a fail still warns. A release that goes from pass
  to fail opens a tracking issue.
- **Old releases matter.** Selection is MVS, so `"~> 0.1"` picks the
  *lowest* matching release. If an old release fails on current Spinel,
  constrain past it: for example `bcrypt = ">= 0.1.1"` and
  `pg = "~> 0.2"`.
- **Entries are checked the way spin uses them.** `tools/check.rb` runs on
  every pull request. It checks that each `ref` is a full commit SHA the
  repository serves, and that the commit's `spin.toml` names the release's
  version.

## Format

One TOML file per package, `packages/<name>.toml`:

```toml
name = "ansi"
repo = "https://github.com/you/spinel-ansi"

[[release]]
version = "1.0.0"
ref = "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3"  # full commit SHA in `repo`

[[probe]]                 # written by the probe job
version = "1.0.0"
spinel = "22de42432"      # the revision `spinel --version` prints
result = "pass"
date = "2026-10-17"
```

The same name as a rubygems.org gem means the same library, possibly a
subset-compatible port. A diverging fork must use a different name.

## Adding a package or a release

Open a pull request that adds or updates `packages/<name>.toml`, or let
`spin publish` open it for you:

```sh
SPIN_INDEX=https://github.com/roundhouse-rb/spin-index spin publish
```

A release needs a passing `spin test` (`spin publish` won't run without
one) and a `ref` whose `spin.toml` carries its version. The check job
verifies the ref; the next probe run records how the release does on
Spinel master. Please offer the same entry to matz/spin-index too.

The curators are the members of the
[roundhouse-rb](https://github.com/roundhouse-rb) organization.

## Tools

- `ruby tools/check.rb [--upstream]` checks every entry. `--upstream` also
  lists what matz/spin-index has that this index lacks.
- `ruby tools/probe.rb [--spin PATH] [--only a,b]` probes releases with a
  local Spinel build and appends the probes that changed.
