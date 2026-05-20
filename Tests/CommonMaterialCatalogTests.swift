import Testing
import Foundation
@testable import sitekeeper

struct CommonMaterialCatalogTests {
    @Test func bundledCatalogLoadsExpectedMaterials() {
        let materials = MaterialLibrary.all

        #expect(materials.count == 961)
        #expect(materials.contains {
            $0.name == "BV 铜芯线"
                && $0.specification == "2.5mm²"
                && $0.unit == "卷(100m)"
                && $0.category == .wire
        })
        #expect((MaterialLibrary.byCategory[.wire] ?? []).isEmpty == false)
        #expect((MaterialLibrary.byCategory[.tools] ?? []).isEmpty == false)
    }

    @Test func catalogDecoderAcceptsStableCategoryKeys() throws {
        let data = Data(#"[{"name":"测试材料","specification":"DN20","unit":"米","category":"conduit"}]"#.utf8)
        let materials = try MaterialLibrary.decodeCatalog(from: data)

        #expect(materials.count == 1)
        #expect(materials.first?.category == .conduit)
    }
}
