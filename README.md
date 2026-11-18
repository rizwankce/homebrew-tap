# Rizwankce Tap

## How do I install these formulae?

`brew install rizwankce/tap/<formula>`

Or `brew tap rizwankce/tap` and then `brew install <formula>`.

Or, in a `brew bundle` `Brewfile`:

```ruby
tap "rizwankce/tap"
brew "<formula>"
```

## Documentation

`brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).

## Releasing a new version

Maintainers bump a formula with `scripts/bump.sh`, run locally with your own `gh` login (so the PR it opens triggers the test workflow; CI holds no tokens):

```sh
scripts/bump.sh [--dry-run] [--no-verify] FORMULA VERSION
scripts/bump.sh cryo 0.2.0
```

It downloads `FORMULA-VERSION.tar.gz` from the `vVERSION` release of the repo named in the formula's `url`, computes the sha256 (and compares it with the release's `.sha256` asset if there is one), and verifies provenance with `gh attestation verify`. It then rewrites `url` and `sha256` (dropping the previous version's `bottle` block), runs `brew style`, commits `FORMULA VERSION`, pushes `bump-FORMULA-VERSION` and opens a PR. It waits for `tests.yml` to build the bottle, then dispatches `publish.yml`, which runs `brew pr-pull`: that adds the bottle block, uploads the bottles and pushes to `main`, so GitHub shows the PR as merged.

- `--dry-run` stops after the rewrite and `brew style`; nothing is committed or pushed, and your checkout is not touched (the work happens in a temporary worktree).
- `--no-verify` skips the attestation check, for releases that predate attestations. Without it, a release with no attestation fails.
- The working tree must be clean. Needs `gh`, `git` and `shasum`; `brew` is optional.
