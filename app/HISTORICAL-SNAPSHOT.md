# Historical mobile application snapshot

This tree reconstructs a September 2026 revision of the Nultra mobile app. The
archive import preserved the original author and commit dates, parent order,
application changes and eligible design, testing and release notes. The import
moved these files under `app/` and mapped the owner's private Git addresses to
the public GitHub attribution address. The accompanying public software and
Gradle notices were added during the import.

The original code is presented with retrospective privacy and security edits.
Revisions that supplied a shared device password now require explicit input
for an individual switch. The app, credential storage, associated controls and
test fixtures were adjusted together. Historical network clients that lacked
authentication have their live transport disabled. Protocol-fixture tests can
still exercise their parsers. Consult the current public release for supported
device pairing, gateway authentication, development and distribution.

The import omitted private hosting and signing infrastructure, release automation
and packages, unreviewed screenshots, personal settings and workstation-specific
data. Remaining project artwork was matched against the published app and its
ancillary image metadata removed. Historical instructions may refer to omitted
files. These archival edits are later additions, outside the historical authors'
original changes.
