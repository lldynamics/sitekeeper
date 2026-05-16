package com.chengjinfang.sitekeeper.database.material

object DefaultMaterialLibrary {
    private const val UPDATED_AT = "2026-05-17T00:00:00+0800"

    val priceEntries: List<MaterialPriceEntryEntity> = listOf(
        priceEntry(
            id = "preset-bv-2-5",
            name = "BV 铜芯线",
            specification = "2.5mm2",
            unit = "卷(100m)",
            referencePrice = "198",
            supplier = "城东建材",
            category = "电线",
            brand = "国标"
        ),
        priceEntry(
            id = "preset-bv-4",
            name = "BV 铜芯线",
            specification = "4mm2",
            unit = "卷(100m)",
            referencePrice = "318",
            supplier = "城东建材",
            category = "电线",
            brand = "国标"
        ),
        priceEntry(
            id = "preset-yjv-5x16",
            name = "YJV 电力电缆",
            specification = "5x16mm2",
            unit = "米",
            referencePrice = "58",
            supplier = "华南线缆",
            category = "电缆",
            brand = "国标"
        ),
        priceEntry(
            id = "preset-pvc-20",
            name = "PVC 线管",
            specification = "20",
            unit = "米",
            referencePrice = "2.6",
            supplier = "城东建材",
            category = "线管"
        ),
        priceEntry(
            id = "preset-galvanized-tray-200x100",
            name = "热镀锌桥架",
            specification = "200x100",
            unit = "米",
            referencePrice = "45",
            supplier = "城东建材",
            category = "桥架"
        ),
        priceEntry(
            id = "preset-led-panel-600",
            name = "LED 平板灯",
            specification = "600x600",
            unit = "套",
            referencePrice = "86",
            supplier = "明辉照明",
            category = "灯具"
        ),
        priceEntry(
            id = "preset-mccb-100a",
            name = "塑壳断路器",
            specification = "100A/3P",
            unit = "只",
            referencePrice = "235",
            supplier = "配电成套厂",
            category = "断路器"
        ),
        priceEntry(
            id = "preset-distribution-box",
            name = "照明配电箱",
            specification = "12 回路",
            unit = "台",
            referencePrice = "680",
            supplier = "配电成套厂",
            category = "配电箱"
        )
    )

    val suppliers: List<SupplierProfileEntity> = listOf(
        supplier(
            id = "supplier-chengdong-material",
            name = "城东建材",
            category = "综合材料",
            contact = "张经理",
            phone = "13800001001",
            address = "城东建材市场 A 区",
            note = "桥架、线管、辅材常用供应商"
        ),
        supplier(
            id = "supplier-huanan-cable",
            name = "华南线缆",
            category = "电线电缆",
            contact = "李经理",
            phone = "13800001002",
            address = "高新区线缆仓",
            note = "电缆按当天铜价复核"
        ),
        supplier(
            id = "supplier-minghui-lighting",
            name = "明辉照明",
            category = "灯具",
            contact = "陈经理",
            phone = "13800001003",
            address = "灯饰城 2 号楼",
            note = "灯具到货前确认色温和质保"
        ),
        supplier(
            id = "supplier-panel-factory",
            name = "配电成套厂",
            category = "配电箱/断路器",
            contact = "王工",
            phone = "13800001004",
            address = "工业园成套车间",
            note = "箱体下单前复核系统图版本"
        )
    )

    private fun priceEntry(
        id: String,
        name: String,
        specification: String,
        unit: String,
        referencePrice: String,
        supplier: String,
        category: String,
        brand: String = "",
        note: String = ""
    ): MaterialPriceEntryEntity =
        MaterialPriceEntryEntity(
            id = id,
            name = name,
            specification = specification,
            brand = brand,
            unit = unit,
            referencePrice = referencePrice,
            supplier = supplier,
            category = category,
            note = note,
            updatedAt = UPDATED_AT
        )

    private fun supplier(
        id: String,
        name: String,
        category: String,
        contact: String,
        phone: String,
        address: String,
        note: String
    ): SupplierProfileEntity =
        SupplierProfileEntity(
            id = id,
            name = name,
            category = category,
            contact = contact,
            phone = phone,
            address = address,
            note = note,
            updatedAt = UPDATED_AT
        )
}
