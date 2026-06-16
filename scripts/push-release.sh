#!/usr/bin/env bash
# Commit and push hambar-app + hambar-homebrew after ./scripts/release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MONOREPO_ROOT="$(cd "${APP_REPO_ROOT}/.." && pwd)"
HOMEBREW_REPO_ROOT="${MONOREPO_ROOT}/hambar-homebrew"

README_FILE="${APP_REPO_ROOT}/README.md"
CASK_FILE="${HOMEBREW_REPO_ROOT}/Casks/hambar.rb"
GITHUB_APP_REPO="hipszkij/hambar-app"

SKIP_APP=false
SKIP_CASK=false
DRY_RUN=false
VERIFY_RELEASE=false
VERSION=""

usage() {
  cat <<'EOF'
Usage: push-release.sh [options]

Commit and push release metadata to GitHub after running release.sh.

Options:
  --version VERSION   Release version (default: read from hambar-homebrew cask)
  --skip-app          Do not push hipszkij/hambar-app
  --skip-cask         Do not push hipszkij/hambar-homebrew
  --verify-release    Require matching gh release tag before pushing
  --dry-run           Print actions without running git push
  -h, --help          Show this help

Typical flow:
  ./scripts/release.sh
  ./scripts/push-release.sh
EOF
}

log() {
  printf '→ %s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

read_cask_version() {
  python3 - "${CASK_FILE}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
match = re.search(r'^\s+version "([^"]+)"', text, re.MULTILINE)
if not match:
    raise SystemExit(f'Could not read version from {path}')
print(match.group(1))
PY
}

verify_readme_release() {
  python3 - "${README_FILE}" "${VERSION}" <<'PY'
import pathlib
import sys

readme_path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
text = readme_path.read_text(encoding="utf-8")
start = "<!-- release-notes:start -->"
end = "<!-- release-notes:end -->"
if start not in text or end not in text:
    raise SystemExit(f"README missing release notes markers in {readme_path}")
section = text.split(start, 1)[1].split(end, 1)[0].strip()
expected = f"### {version} —"
if not section.startswith(expected):
    raise SystemExit(
        f"README release notes do not start with {expected!r}. "
        f"Run release.sh for {version} first."
    )
PY
}

ensure_git_repo() {
  local repo_root="$1"
  local label="$2"

  [[ -d "${repo_root}/.git" ]] || die "${label} is not a git repository: ${repo_root}"
  git -C "${repo_root}" rev-parse --abbrev-ref HEAD >/dev/null 2>&1 \
    || die "${label} has no checked-out branch: ${repo_root}"

  if ! git -C "${repo_root}" remote get-url origin >/dev/null 2>&1; then
    die "${label} has no origin remote. Add one before pushing."
  fi
}

commit_if_changed() {
  local repo_root="$1"
  local message="$2"
  shift 2
  local -a paths=("$@")
  local repo_name changed

  repo_name="$(basename "${repo_root}")"
  git -C "${repo_root}" add -- "${paths[@]}"

  if git -C "${repo_root}" diff --cached --quiet -- "${paths[@]}"; then
    log "${repo_name}: nothing to commit"
    return 0
  fi

  changed="$(git -C "${repo_root}" diff --cached --name-only -- "${paths[@]}")"
  if [[ "${DRY_RUN}" == true ]]; then
    log "${repo_name}: would commit:"
    printf '%s\n' "${changed}" | sed 's/^/    /'
    log "${repo_name}: would run: git commit -m ${message@Q}"
    return 0
  fi

  git -C "${repo_root}" commit -m "${message}"
  log "${repo_name}: committed ${message}"
}

push_branch() {
  local repo_root="$1"
  local repo_name branch upstream ahead

  repo_name="$(basename "${repo_root}")"
  branch="$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD)"
  upstream="$(git -C "${repo_root}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  if [[ -n "${upstream}" ]]; then
    ahead="$(git -C "${repo_root}" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
    if [[ "${ahead}" == "0" && "${DRY_RUN}" == false ]]; then
      log "${repo_name}: already up to date with ${upstream}"
      return 0
    fi
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log "${repo_name}: would run: git push origin ${branch}"
    return 0
  fi

  git -C "${repo_root}" push origin "${branch}"
  log "${repo_name}: pushed to origin/${branch}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      [[ -n "${VERSION}" ]] || die "--version requires a value"
      shift 2
      ;;
    --skip-app) SKIP_APP=true; shift ;;
    --skip-cask) SKIP_CASK=true; shift ;;
    --verify-release) VERIFY_RELEASE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

if [[ "${SKIP_APP}" == true && "${SKIP_CASK}" == true ]]; then
  die "Nothing to do: both --skip-app and --skip-cask were passed"
fi

if [[ -z "${VERSION}" ]]; then
  [[ -f "${CASK_FILE}" ]] || die "Homebrew cask not found: ${CASK_FILE}"
  VERSION="$(read_cask_version)"
fi

log "Release version: ${VERSION}"

if [[ "${VERIFY_RELEASE}" == true ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    die "GitHub CLI (gh) not found. Install it or omit --verify-release"
  fi
  gh release view "v${VERSION}" --repo "${GITHUB_APP_REPO}" >/dev/null \
    || die "GitHub release v${VERSION} not found in ${GITHUB_APP_REPO}. Run release.sh first."
  log "Verified GitHub release v${VERSION}"
fi

if [[ "${SKIP_APP}" == false ]]; then
  [[ -f "${README_FILE}" ]] || die "README not found: ${README_FILE}"
  verify_readme_release
  ensure_git_repo "${APP_REPO_ROOT}" "hambar-app"

  commit_if_changed \
    "${APP_REPO_ROOT}" \
    "Release ${VERSION}" \
    "README.md"

  push_branch "${APP_REPO_ROOT}"
fi

if [[ "${SKIP_CASK}" == false ]]; then
  [[ -f "${CASK_FILE}" ]] || die "Homebrew cask not found: ${CASK_FILE}"

  cask_version="$(read_cask_version)"
  [[ "${cask_version}" == "${VERSION}" ]] \
    || die "Cask version is ${cask_version}, but push target is ${VERSION}"

  ensure_git_repo "${HOMEBREW_REPO_ROOT}" "hambar-homebrew"

  commit_if_changed \
    "${HOMEBREW_REPO_ROOT}" \
    "Update hambar cask to ${VERSION}" \
    "Casks/hambar.rb"

  push_branch "${HOMEBREW_REPO_ROOT}"
fi

cat <<EOF

Done.

  Version: ${VERSION}
  App:     ${GITHUB_APP_REPO}
  Cask:    hipszkij/hambar-homebrew

Test install:
  brew untap hipszkij/hambar 2>/dev/null
  brew tap hipszkij/hambar https://github.com/hipszkij/hambar-homebrew
  brew install --cask hambar

EOF
