// The stub is a self-contained UEFI main package: its only import is
// "unsafe". It had no go.mod at all and built locally because an umbrella
// go.work two directories up happened to cover it -- so CI, which checks out
// this repository alone, failed with "cannot find main module".
module github.com/cloud-boot/windows-image/stub

go 1.25
