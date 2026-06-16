#!/usr/bin/env bash
# Create a HAmbar release zip, update README release notes, and refresh the Homebrew cask.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MONOREPO_ROOT="$(cd "${APP_REPO_ROOT}/.." && pwd)"

APP_NAME="HAmbar"
APP_BUNDLE="${APP_REPO_ROOT}/builds/${APP_NAME}.app"
DIST_DIR="${APP_REPO_ROOT}/dist"
VERSION_DIR="${APP_REPO_ROOT}/.version"
NEXT_VERSION_FILE="${VERSION_DIR}/next"
README_FILE="${APP_REPO_ROOT}/README.md"
CASK_FILE="${MONOREPO_ROOT}/hambar-homebrew/Casks/hambar.rb"
GITHUB_REPO="hipszkij/hambar-app"

SKIP_GH=false
SKIP_CASK=false
DRY_RUN=false
VERSION=""

usage() {
  cat <<'EOF'
Usage: release.sh [options]

Options:
  --version VERSION   Release version (default: .version/next)
  --app PATH          Path to HAmbar.app (default: hambar-app/builds/HAmbar.app)
  --skip-gh           Do not run `gh release create`
  --skip-cask         Do not update hambar-homebrew/Casks/hambar.rb
  --dry-run           Print actions without writing files
  -h, --help          Show this help

Before running:
  1. Export a signed + notarized app to hambar-app/builds/HAmbar.app
  2. Edit hambar-app/.version/notes/<version>.md with release notes
EOF
}

log() {
  printf '→ %s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      [[ -n "${VERSION}" ]] || die "--version requires a value"
      shift 2
      ;;
    --app)
      APP_BUNDLE="${2:-}"
      [[ -n "${APP_BUNDLE}" ]] || die "--app requires a value"
      shift 2
      ;;
    --skip-gh) SKIP_GH=true; shift ;;
    --skip-cask) SKIP_CASK=true; shift ;;
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

if [[ -z "${VERSION}" ]]; then
  [[ -f "${NEXT_VERSION_FILE}" ]] || die "Missing ${NEXT_VERSION_FILE}. Create it with the next version number."
  VERSION="$(tr -d '[:space:]' < "${NEXT_VERSION_FILE}")"
  [[ -n "${VERSION}" ]] || die "${NEXT_VERSION_FILE} is empty"
fi

NOTES_FILE="${VERSION_DIR}/notes/${VERSION}.md"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
TAG="v${VERSION}"
RELEASE_DATE="$(date +%Y-%m-%d)"

[[ -d "${APP_BUNDLE}" ]] || die "App bundle not found: ${APP_BUNDLE}"
[[ -f "${NOTES_FILE}" ]] || die "Release notes not found: ${NOTES_FILE}"

if [[ "${SKIP_CASK}" == false && ! -f "${CASK_FILE}" ]]; then
  die "Homebrew cask not found: ${CASK_FILE}"
fi

log "Version: ${VERSION}"
log "App: ${APP_BUNDLE}"
log "Notes: ${NOTES_FILE}"

if [[ "${DRY_RUN}" == false ]]; then
  mkdir -p "${DIST_DIR}"
  rm -f "${ZIP_PATH}"
  ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
fi

SHA256="$(
  if [[ "${DRY_RUN}" == true ]]; then
    echo "DRY_RUN_SHA256"
  else
    shasum -a 256 "${ZIP_PATH}" | awk '{print $1}'
  fi
)"

log "SHA256: ${SHA256}"
log "Zip: ${ZIP_PATH}"

python3 - "${README_FILE}" "${VERSION}" "${RELEASE_DATE}" "${NOTES_FILE}" "${DRY_RUN}" <<'PY'
import pathlib
import sys

readme_path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
release_date = sys.argv[3]
notes_path = pathlib.Path(sys.argv[4])
dry_run = sys.argv[5].lower() == "true"

notes_lines = [
    line.rstrip()
    for line in notes_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
if not notes_lines:
    raise SystemExit(f"Release notes are empty: {notes_path}")

bullet_block = "\n".join(
    line if line.startswith("- ") else f"- {line}"
    for line in notes_lines
)
entry = f"### {version} — {release_date}\n{bullet_block}"

start = "<!-- release-notes:start -->"
end = "<!-- release-notes:end -->"
text = readme_path.read_text(encoding="utf-8")

if start not in text or end not in text:
    raise SystemExit(f"README missing release notes markers in {readme_path}")

before, rest = text.split(start, 1)
middle, after = rest.split(end, 1)
existing = middle.strip()
if existing:
    new_body = f"{entry}\n\n{existing}".rstrip() + "\n"
else:
    new_body = entry + "\n"

updated = before + start + "\n" + new_body + end + after
if dry_run:
    print(updated.split(start, 1)[1].split(end, 1)[0].strip())
else:
    readme_path.write_text(updated, encoding="utf-8")
PY

if [[ "${SKIP_CASK}" == false ]]; then
  if [[ "${DRY_RUN}" == true ]]; then
    log "Would update cask: ${CASK_FILE}"
  else
    python3 - "${CASK_FILE}" "${VERSION}" "${SHA256}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3]
text = path.read_text(encoding="utf-8")
text, count_version = re.subn(
    r'(\n  version ")[^"]+(")',
    rf'\g<1>{version}\2',
    text,
    count=1,
)
text, count_sha = re.subn(
    r'(\n  sha256 ")[^"]+(")',
    rf'\g<1>{sha256}\2',
    text,
    count=1,
)
if count_version != 1 or count_sha != 1:
    raise SystemExit(f"Failed to update version/sha256 in {path}")
path.write_text(text, encoding="utf-8")
PY
    log "Updated cask: ${CASK_FILE}"
  fi
fi

bump_next_version() {
  python3 - "${VERSION}" <<'PY'
import sys

parts = sys.argv[1].split(".")
if not parts or not all(part.isdigit() for part in parts):
    raise SystemExit(f"Cannot bump non-numeric version: {sys.argv[1]}")
parts[-1] = str(int(parts[-1]) + 1)
print(".".join(parts))
PY
}

NEXT_VERSION="$(bump_next_version "${VERSION}")"
NOTES_TEMPLATE="${VERSION_DIR}/notes/${NEXT_VERSION}.md"

if [[ "${DRY_RUN}" == true ]]; then
  log "Would set next version to ${NEXT_VERSION}"
else
  printf '%s\n' "${NEXT_VERSION}" > "${NEXT_VERSION_FILE}"
  if [[ ! -f "${NOTES_TEMPLATE}" ]]; then
    cat > "${NOTES_TEMPLATE}" <<EOF
- 
EOF
    log "Created draft notes: ${NOTES_TEMPLATE}"
  fi
  log "Next version: ${NEXT_VERSION} (saved to .version/next)"
fi

if [[ "${SKIP_GH}" == false ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    die "GitHub CLI (gh) not found. Install it or pass --skip-gh"
  fi
  if [[ "${DRY_RUN}" == true ]]; then
    log "Would run: gh release create ${TAG} ${ZIP_PATH} --repo ${GITHUB_REPO} --title '${APP_NAME} ${VERSION}' --notes-file ${NOTES_FILE}"
  else
    log "Creating GitHub release ${TAG}..."
    gh release create "${TAG}" "${ZIP_PATH}" \
      --repo "${GITHUB_REPO}" \
      --title "${APP_NAME} ${VERSION}" \
      --notes-file "${NOTES_FILE}"
  fi
fi

cat <<EOF

Done.

  Zip:     ${ZIP_PATH}
  SHA256:  ${SHA256}
  Tag:     ${TAG}
  URL:     https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_NAME}

Next steps:
  1. ./scripts/push-release.sh
  2. Test: brew tap hipszkij/hambar https://github.com/hipszkij/hambar-homebrew && brew install --cask hambar

EOF
