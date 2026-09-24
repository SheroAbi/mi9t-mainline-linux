#!/bin/bash
# Regenerate kernel/patches/*.patch from the driver sources in kernel/modules/
# against the pristine upstream copies in kernel/upstream-reference/, then prove
# each patch reconstructs the source byte for byte.
set -euo pipefail
K=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../kernel" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

for n in qcom_qg qcom_smbx; do
	diff -u --label "a/$n.c" --label "b/$n.c" \
		"$K/upstream-reference/$n-before.c" "$K/modules/$n.c" > "$K/patches/$n.patch" || true
	cp "$K/upstream-reference/$n-before.c" "$TMP/$n.c"
	( cd "$TMP" && patch -s -p1 < "$K/patches/$n.patch" )
	cmp -s "$TMP/$n.c" "$K/modules/$n.c" \
		|| { echo "$n: patch does not reconstruct the source" >&2; exit 1; }
	printf '%-12s %4s lines, verified\n' "$n.patch" "$(wc -l < "$K/patches/$n.patch")"
done
