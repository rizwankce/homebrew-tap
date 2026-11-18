#!/usr/bin/env bash
# Bump a formula to a new release of its source repo, open a PR, wait for the
# bottle build, then publish it. Run locally by the maintainer with their own
# gh login, so the PR it opens triggers tests.yml. See the README.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bump.sh [--dry-run] [--no-verify] FORMULA VERSION

  FORMULA      formula name, e.g. cryo or cryo-ci (Formula/FORMULA.rb must exist)
  VERSION      release version without the leading v, e.g. 1.2.3
  --dry-run    stop after rewriting and styling the formula; nothing is committed
               or pushed, and your working tree is left untouched
  --no-verify  skip "gh attestation verify" (for releases that predate attestations)
EOF
}

die() {
  echo "bump.sh: $*" >&2
  exit 1
}

dry_run=0
verify=1
positional=()
for arg in "$@"
do
  case "${arg}" in
    --dry-run) dry_run=1 ;;
    --no-verify) verify=0 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      die "unknown option: ${arg}"
      ;;
    *) positional+=("${arg}") ;;
  esac
done
[[ ${#positional[@]} -eq 2 ]] || {
  usage >&2
  exit 2
}
formula=${positional[0]}
version=${positional[1]}

repo_root=$(git rev-parse --show-toplevel)
cd "${repo_root}"
formula_path="Formula/${formula}.rb"

# 1. Validate arguments and find the source repo from the formula's url line.
[[ ${formula} =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid formula name: ${formula}"
[[ -f ${formula_path} ]] || die "no such formula: ${formula_path}"
[[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 1.2.3, got: ${version}"

url_line=$(grep -E '^  url "' "${formula_path}" | head -n1 || true)
[[ ${url_line} =~ github\.com/([^/\"]+/[^/\"]+)/releases/download/ ]] ||
  die "cannot find the GitHub release repo in the url line of ${formula_path}"
source_repo=${BASH_REMATCH[1]}
tag="v${version}"
tarball="${formula}-${version}.tar.gz"
branch="bump-${formula}-${version}"

for tool in gh git shasum
do
  command -v "${tool}" >/dev/null || die "${tool} is required"
done

# 2. Require a clean tree and branch from an up-to-date origin/main. The work
# happens in a temporary worktree so this script file and your checkout are
# never switched underneath you.
dirty="$(git status --porcelain)"
[[ -z ${dirty} ]] || die "working tree is not clean; commit or stash first"
git fetch --quiet origin main
if git show-ref --verify --quiet "refs/heads/${branch}" ||
   git ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1
then
  die "branch ${branch} already exists locally or on origin"
fi

tmp=$(mktemp -d)
worktree="${tmp}/tap"
cleanup() {
  git -C "${repo_root}" worktree remove --force "${worktree}" >/dev/null 2>&1 || true
  if [[ ${dry_run} -eq 1 ]]
  then
    git -C "${repo_root}" branch -D "${branch}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmp}"
}
trap cleanup EXIT
git worktree add --quiet -b "${branch}" "${worktree}" origin/main

# 3. Download the release tarball, hash it, and check it.
dl="${tmp}/download"
mkdir "${dl}"
echo "Downloading ${tarball} from ${source_repo} ${tag}"
gh release download "${tag}" -R "${source_repo}" -D "${dl}" -p "${tarball}" ||
  die "could not download ${tarball} from ${source_repo} ${tag}"
sha=$(shasum -a 256 "${dl}/${tarball}" | awk '{print $1}')
echo "sha256: ${sha}"

if gh release download "${tag}" -R "${source_repo}" -D "${dl}" -p "${tarball}.sha256" >/dev/null 2>&1
then
  published=$(awk '{print $1; exit}' "${dl}/${tarball}.sha256")
  [[ ${published} == "${sha}" ]] || die "sha256 mismatch: release says ${published}, tarball is ${sha}"
  echo "Matches the release's .sha256 asset"
else
  echo "No .sha256 asset on the release; skipping that check"
fi

if [[ ${verify} -eq 1 ]]
then
  echo "Verifying provenance"
  gh attestation verify "${dl}/${tarball}" -R "${source_repo}" ||
    die "attestation check failed (releases before attestations need --no-verify)"
else
  echo "Skipping provenance check (--no-verify)"
fi

# 4. Rewrite the url and the source sha256 (two-space indent; the bottle block's
# lines are indented further). A new version drops the old bottle block: its
# root_url and checksums belong to the previous release, and pr-pull adds the
# new one after the bottles are built.
wt_formula="${worktree}/${formula_path}"
old_version=$(sed -nE 's#^  url ".*/download/v([^/]+)/.*"#\1#p' "${wt_formula}" | head -n1)
drop=0
[[ ${old_version} == "${version}" ]] || drop=1
new_url="https://github.com/${source_repo}/releases/download/${tag}/${tarball}"
awk -v url="${new_url}" -v sha="${sha}" -v drop="${drop}" '
  /^  url "/    { print "  url \"" url "\""; next }
  /^  sha256 "/ { print "  sha256 \"" sha "\""; next }
  drop == 1 && /^  bottle do$/ { inbottle = 1; next }
  inbottle { if ($0 == "  end") { inbottle = 0; skipblank = 1 } ; next }
  skipblank && $0 == "" { skipblank = 0; next }
  { skipblank = 0; print }
' "${wt_formula}" >"${wt_formula}.new"
mv "${wt_formula}.new" "${wt_formula}"

echo
git -C "${worktree}" --no-pager diff -- "${formula_path}" || true
if git -C "${worktree}" diff --quiet -- "${formula_path}"
then
  [[ ${dry_run} -eq 1 ]] || die "formula already points at ${version}; nothing to bump"
  echo "(no changes: formula already at ${version} with this sha256)"
fi

if command -v brew >/dev/null
then
  echo "Running brew style"
  brew style "${wt_formula}" || die "brew style failed"
else
  echo "brew not found; skipping brew style"
fi

if [[ ${dry_run} -eq 1 ]]
then
  echo "Dry run: stopping before commit; your working tree is untouched."
  exit 0
fi

# 5. Commit, push, open the PR.
cd "${worktree}"
git add "${formula_path}"
git commit --quiet -m "${formula} ${version}"
git push --quiet -u origin "${branch}"
pr_url=$(gh pr create --base main --head "${branch}" \
  --title "${formula} ${version}" \
  --body "Bump ${formula} to ${version} from the ${tag} release of ${source_repo}.

The tarball sha256 is ${sha}.")
pr=${pr_url##*/}
echo "Opened ${pr_url}"

# 6. Wait for tests.yml (it builds the bottle). A just-opened PR can briefly
# have no checks, so retry until some appear.
for _ in $(seq 1 30)
do
  [[ -n $(gh pr checks "${pr}" 2>/dev/null || true) ]] && break
  sleep 10
done
if ! gh pr checks "${pr}" --watch --fail-fast
then
  echo "Checks failed for ${pr_url}" >&2
  gh pr checks "${pr}" --json name,state,link \
    -q '.[] | select(.state == "FAILURE") | "  " + .name + ": " + .link' >&2 || true
  exit 1
fi

# 7. Publish: publish.yml runs brew pr-pull, which downloads the bottles built
# by the PR's test run, adds the bottle block, uploads the bottles to the tap's
# release and pushes the result to main. GitHub then shows the PR as merged.
head_sha=$(gh pr view "${pr}" --json headRefOid -q .headRefOid)
before=$(gh run list --workflow publish.yml --limit 1 --json databaseId -q '.[0].databaseId // 0')
gh workflow run publish.yml -f pull_request="${pr}" -f head_sha="${head_sha}"
run_id=""
for _ in $(seq 1 30)
do
  sleep 5
  run_id=$(gh run list --workflow publish.yml --limit 5 --json databaseId \
    -q "map(select(.databaseId > ${before})) | .[0].databaseId // empty")
  [[ -n ${run_id} ]] && break
done
[[ -n ${run_id} ]] || die "could not find the publish.yml run that was just dispatched"
gh run view "${run_id}" --json url -q .url
if ! gh run watch "${run_id}" --exit-status
then
  run_url="$(gh run view "${run_id}" --json url -q .url)"
  echo "publish.yml failed: ${run_url}" >&2
  exit 1
fi

echo
gh pr view "${pr}" --json state,url -q '"PR " + .state + ": " + .url'
git fetch --quiet origin main
git --no-pager log --oneline -n 3 origin/main
