# Test fixtures

`SampleDataFixture.json` is a synthetic, debug-only sample used by automated
tests. Its repeated identifiers, project and company labels, amounts, and
contact entries are demonstration data, not a customer backup. Phone values
are deliberately non-dialable placeholders.

Keep real project data, customer contacts, device backups, screenshots, and
test-result bundles outside the published repository. Use an isolated test
data directory when exercising backup or restore flows.
