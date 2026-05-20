# LibreDWG iOS Vendor Artifact

`CLibreDWG.xcframework` is a local iOS static build of LibreDWG used by the CAD Metal PoC.

Important constraints:

- This is not the removed `LibreDWGBridge`.
- This artifact is only a DWG geometry source.
- Swift and Metal must convert LibreDWG output into `SiteKeeperCADKernel.CADDatabase` / `CADEntity` before rendering.
- The current native PoC exports `LINE`, `LWPOLYLINE`, `POLYLINE`, `CIRCLE`, `ARC`, tessellated `ELLIPSE`, degraded `SPLINE`, degraded `SOLID` / `TRACE` / `3DFACE` boundary paths, `TEXT`, `MTEXT`, `ATTRIB`, `ATTDEF`, simplified `DIMENSION`, degraded `HATCH` boundary paths, and basic `INSERT` / `BLOCK` expansion for those entity types.

LibreDWG is GPL-licensed. Shipping this static library in the iOS app requires a product/legal decision about GPL compliance and App Store distribution constraints before release.

Release compliance files:

- `SOURCE_MANIFEST.md` records the exact LibreDWG source used to build the artifact. It must say `Source status: READY` before release.
- `COPYING.GPL-3.0.txt` is the license text that must be included with the release source package.
- `../../GPL_COMPLIANCE.md` describes the release checklist.
- `../../THIRD_PARTY_NOTICES.md` contains the user-facing third-party notice.

To rebuild:

```sh
scripts/cad/build_libredwg_ios_xcframework.sh
```

After rebuilding, run:

```sh
scripts/release/check_libredwg_gpl_compliance.sh
scripts/release/package_corresponding_source.sh
```
