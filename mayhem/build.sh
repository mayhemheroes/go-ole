#!/usr/bin/env bash
#
# go-ole/mayhem/build.sh — build go-ole/go-ole's Go fuzz target as a sanitized libFuzzer
# binary, REPLICATING OSS-Fuzz's compile_native_go_fuzzer.
#
# OSS-Fuzz target (projects/go-ole/build.sh):
#   cp $SRC/fuzz_test.go ./
#   go mod tidy
#   printf "package ole\nimport _ \"github.com/AdamKorcz/go-118-fuzz-build/testing\"\n" > register.go
#   go mod tidy
#   compile_native_go_fuzzer github.com/go-ole/go-ole FuzzGUID FuzzGUID
# i.e. the NATIVE go fuzz harness `func FuzzGUID(f *testing.F)` (our vendored
# mayhem/fuzz_guid_test.go, == the OSS-Fuzz fuzz_test.go), built with go-118-fuzz-build
# (AdamKorcz) then linked against $LIB_FUZZING_ENGINE. It fuzzes GUID parsing/formatting:
# NewGUID(data).String().
#
# We produce:
#   /mayhem/fuzz-guid — OSS-Fuzz target (ole.FuzzGUID, go-118-fuzz-build, ASan)
#
# The .a archive carries the Go fuzz code (instrumented by the go-118-fuzz builder); we link it
# against the C/C++ libFuzzer engine with clang ($CXX) + ASan, exactly like compile_go_fuzzer's
# final `$CXX $CXXFLAGS $LIB_FUZZING_ENGINE $fuzzer.a -o $OUT/$fuzzer` step.
#
# DWARF gate (SPEC §6.2 item 10): Go's gc compiler always emits DWARF4 (no downgrade flag).
# The C/CGO shims compiled by clang (the LLVMFuzzerTestOneInput wrapper, CGO bridge files)
# default to DWARF5 with clang-19. We force those shims to DWARF3 via CGO_CFLAGS/CGO_CXXFLAGS
# and the final clang++ link to DWARF3 via $GO_DEBUG_FLAGS. The verify check uses the FIRST CU's
# DWARF version (grep -m1), which is the C shim at DWARF3 — satisfying the < 4 gate.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASAN-only (project.yaml sanitizers: [address]); UBSan is not part of the
# Go libFuzzer link. Keep ASan as the Go-fuzz sanitizer regardless of the base default. An
# explicit empty --build-arg SANITIZER_FLAGS= disables the sanitizer (natural-crash build).
: "${SANITIZER_FLAGS=-fsanitize=address}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS

# Debug-info flags (SPEC §6.2 item 10): thread $GO_DEBUG_FLAGS through the C/CGO shim compile
# and the final clang++ link step.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Air-gapped contract (SPEC §6.5): the PATCH tier re-runs build.sh OFFLINE.
# $(go env GOMODCACHE) reads the pinned ENV under /opt/toolchains (set in the Dockerfile),
# so the file proxy path is correct regardless of $HOME.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

cd "$SRC"
go version

# Vendor the OSS-Fuzz harness into the repo-root package `ole` (replicates OSS-Fuzz's
# `cp $SRC/fuzz_test.go ./`). The mayhem/ copy carries a `//go:build ignore` constraint so
# `go test ./...` (test.sh) doesn't try to compile `package ole` inside mayhem/; strip that
# constraint here so the root copy is a normal package-`ole` harness for go-118-fuzz-build.
# Idempotent: overwriting the same target file each run keeps a re-run clean.
grep -vE '^//go:build ignore$|^// \+build ignore$' \
  "$SRC/mayhem/fuzz_guid_test.go" > "$SRC/fuzz_guid_test.go"

# register.go keeps the AdamKorcz testing shim referenced so `go mod tidy` doesn't prune it
# (exactly what OSS-Fuzz's build.sh does). Idempotent overwrite.
printf 'package ole\n\nimport _ "github.com/AdamKorcz/go-118-fuzz-build/testing"\n' > "$SRC/register.go"

go mod tidy 2>&1 | tail -2 || true
go get github.com/AdamKorcz/go-118-fuzz-build/testing@latest 2>&1 | tail -2 || true
go mod tidy 2>&1 | tail -2 || true

mkdir -p "$SRC/mayhem-build"

build_native() {
  local func="$1" out="$2"
  echo "=== building $out ($func, go-118-fuzz-build) ==="
  go-118-fuzz-build -o "$SRC/mayhem-build/$out.a" -func "$func" "$SRC"
  # Link: DWARF3 via $GO_DEBUG_FLAGS ensures the C-shim CU (first in the binary) is at DWARF3.
  $CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$SRC/mayhem-build/$out.a" -o "/mayhem/$out"
  echo "built /mayhem/$out"
}

# ── OSS-Fuzz target: ole.FuzzGUID (native, go-118-fuzz-build) ─────────────────────────────────
build_native FuzzGUID fuzz-guid

echo "build.sh complete:"
ls -la /mayhem/fuzz-guid 2>&1 || true
