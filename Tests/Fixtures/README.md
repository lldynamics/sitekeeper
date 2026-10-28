# Test fixtures

The debug sample is constructed by `SyntheticSampleFixtureBuilder` in
`Sources/Shared/Services/Fixtures/SampleDataFixture.swift`.
Recipe `synthetic-fixture-v1` uses seed `0x5EED2026`, fixed dates, explicit IDs,
artificial labels and arithmetic amounts. Contacts use non-dialable
`NON-DIALABLE-` strings and the reserved `example.invalid` domain.

PNG color grids and single-page vector PDFs are constructed entirely in code;
no customer records, disk fixtures, real drawings or external assets are inputs.
The DEBUG loader round-trips the typed snapshot through JSON in memory.
Release sample loading remains disabled. Tests verify counts, links,
determinism, every generated image and every generated PDF.

Keep real project data, customer contacts, device backups, screenshots, and
test-result bundles outside the published repository. Use an isolated test
data directory when exercising backup or restore flows.
