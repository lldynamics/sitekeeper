# GPL Compliance Plan

This project currently links `Vendor/LibreDWG/CLibreDWG.xcframework` into the iOS app for local DWG import.

LibreDWG is distributed under the GNU General Public License version 3 or later. While this static library is bundled, release builds must treat the app binary as a GPL-covered distribution unless product/legal review approves a different architecture.

This file is an engineering release checklist, not legal advice.

## Release Gates

Before distributing any build that includes `Vendor/LibreDWG/CLibreDWG.xcframework`:

1. Rebuild LibreDWG from a recorded upstream source commit.
   - Use `scripts/cad/build_libredwg_ios_xcframework.sh`.
   - The script writes `Vendor/LibreDWG/SOURCE_MANIFEST.md`.
   - The manifest must say `Source status: READY`.
2. Keep the complete license text.
   - `Vendor/LibreDWG/COPYING.GPL-3.0.txt` must remain in the repository and release source package.
3. Provide Corresponding Source.
   - Run `scripts/release/package_corresponding_source.sh` for every distributed version.
   - The package must include the app source, LibreDWG source, build scripts, local shim source, and any local patches needed to rebuild the same binary.
4. Keep user-visible notices.
   - The app must keep an Open Source Licenses entry under the About area.
   - The notice must mention LibreDWG, GPLv3-or-later, no warranty, and where to obtain source.
5. Keep third-party notices.
   - `THIRD_PARTY_NOTICES.md` must list LibreDWG and the GPL license.
6. Run the release guard.
   - `scripts/release/check_libredwg_gpl_compliance.sh`
   - Release preflight runs this guard with strict release checks enabled.
7. App Store review risk must be decided before release.
   - GPLv3 has installation-information and anti-restriction requirements for covered user products.
   - iOS/App Store distribution can add terms or technical restrictions that need product/legal review.

## Release Commands

```sh
scripts/cad/build_libredwg_ios_xcframework.sh
scripts/release/check_libredwg_gpl_compliance.sh
scripts/release/package_corresponding_source.sh
scripts/release/preflight.sh
```

## If Closed-Source Distribution Is Required

Do not ship `Vendor/LibreDWG/CLibreDWG.xcframework` in that build. Remove the dependency from `project.yml`, regenerate the Xcode project, and keep the app on a non-GPL CAD import path.

