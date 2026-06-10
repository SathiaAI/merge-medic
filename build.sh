#!/usr/bin/env bash
# Build merge-medic.skill from the current source tree.
# Run from the repo root; produces merge-medic.skill in the working directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
NAME="merge-medic"
OUT="${ROOT}/${NAME}.skill"

# Sanity: SKILL.md exists and frontmatter name matches NAME
if [[ ! -f "${ROOT}/SKILL.md" ]]; then
  echo "ERROR: SKILL.md not found at ${ROOT}/SKILL.md" >&2
  exit 1
fi
if ! grep -q "^name: ${NAME}\$" "${ROOT}/SKILL.md"; then
  echo "ERROR: SKILL.md frontmatter 'name:' does not match '${NAME}'" >&2
  exit 1
fi

# Stage the bundle in a temp dir so the zip has a single top-level folder named ${NAME}
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/${NAME}"
cp "${ROOT}/SKILL.md" "${STAGE}/${NAME}/"
if [[ -d "${ROOT}/references" ]]; then
  cp -r "${ROOT}/references" "${STAGE}/${NAME}/"
fi
if [[ -d "${ROOT}/scripts" ]]; then
  cp -r "${ROOT}/scripts" "${STAGE}/${NAME}/"
fi
if [[ -d "${ROOT}/assets" ]]; then
  cp -r "${ROOT}/assets" "${STAGE}/${NAME}/"
fi

rm -f "${OUT}"
(cd "${STAGE}" && zip -qr "${OUT}" "${NAME}" -x '*.DS_Store')

echo "Built ${OUT}"
unzip -l "${OUT}"
