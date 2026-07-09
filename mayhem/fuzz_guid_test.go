//go:build ignore
// +build ignore

// fuzz_guid_test.go — go-ole/go-ole's OSS-Fuzz harness
// (projects/go-ole/fuzz_test.go in google/oss-fuzz), vendored here so the integration owns it.
// It is a native Go fuzz harness (`func FuzzGUID(f *testing.F)`) in package `ole`, built by
// go-118-fuzz-build. The fuzzed surface is GUID parsing + formatting: NewGUID parses the input
// string across all accepted GUID textual forms ({...}, bare hex, brace/dash variants) and
// String() re-serializes it.
//
// The `//go:build ignore` constraint above keeps this file OUT of the repo's normal package
// build and `go test ./...` (it lives under mayhem/ but declares `package ole`). build.sh
// copies it to the repo ROOT *with the ignore constraint stripped* before invoking
// go-118-fuzz-build (exactly like OSS-Fuzz's own build.sh: `cp $SRC/fuzz_test.go ./`).

package ole

import (
	"testing"
)

func FuzzGUID(f *testing.F) {
	f.Fuzz(func(t *testing.T, data string) {
		g := NewGUID(data)
		_ = g.String()
	})
}
