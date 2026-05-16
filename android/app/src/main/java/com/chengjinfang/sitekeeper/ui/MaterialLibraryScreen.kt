package com.chengjinfang.sitekeeper.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntrySummary
import com.chengjinfang.sitekeeper.database.material.SupplierProfileSummary
import com.chengjinfang.sitekeeper.database.project.MaterialLibraryOverview
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.launch

private enum class MaterialLibrarySection(val title: String) {
    Prices("价格库"),
    Suppliers("供应商")
}

@Composable
fun MaterialLibraryScreen(projectRepository: ProjectRepository) {
    val overview by projectRepository.materialLibrary.collectAsStateWithLifecycle(
        initialValue = MaterialLibraryOverview(
            priceEntries = emptyList(),
            suppliers = emptyList(),
            projectMaterialCount = 0,
            warehouseMaterialNames = 0
        )
    )
    val scope = rememberCoroutineScope()
    var section by rememberSaveable { mutableStateOf(MaterialLibrarySection.Prices) }
    var searchText by rememberSaveable { mutableStateOf("") }
    var selectedCategory by rememberSaveable { mutableStateOf<String?>(null) }
    var showPriceForm by rememberSaveable { mutableStateOf(false) }
    var showSupplierForm by rememberSaveable { mutableStateOf(false) }
    var editingPriceId by rememberSaveable { mutableStateOf<String?>(null) }
    var editingSupplierId by rememberSaveable { mutableStateOf<String?>(null) }

    val categories = overview.categories
    val filteredPrices = overview.priceEntries
        .filter { entry -> selectedCategory == null || entry.category == selectedCategory }
        .filter { entry -> materialLibraryMatches(entry, searchText) }
    val filteredSuppliers = overview.suppliers
        .filter { supplier ->
            val category = selectedCategory
            category == null || supplier.category == category || overview.priceEntries.any { entry ->
                entry.category == category && entry.supplier == supplier.name
            }
        }
        .filter { supplier -> materialLibraryMatches(supplier, searchText) }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "材料库",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "维护常用材料、参考单价和供应商，后续报价、采购、仓库都可以从这里取数。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            MaterialLibraryMetrics(overview = overview)
        }

        item {
            MaterialLibraryToolbar(
                section = section,
                onSectionChange = {
                    section = it
                    editingPriceId = null
                    editingSupplierId = null
                },
                onImportDefaults = {
                    scope.launch { projectRepository.importDefaultMaterialLibrary() }
                }
            )
        }

        item {
            OutlinedTextField(
                value = searchText,
                onValueChange = { searchText = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("搜索材料、规格、品牌、供应商") }
            )
        }

        item {
            MaterialLibraryCategoryRow(
                categories = categories,
                selectedCategory = selectedCategory,
                onSelectCategory = { selectedCategory = it }
            )
        }

        when (section) {
            MaterialLibrarySection.Prices -> {
                item {
                    Button(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            showPriceForm = !showPriceForm
                            editingPriceId = null
                        }
                    ) {
                        Text(if (showPriceForm) "收起价格录入" else "添加材料价格")
                    }
                }

                if (showPriceForm) {
                    item {
                        MaterialPriceFormCard(
                            formKey = "new-price",
                            knownSuppliers = overview.suppliers.map { it.name },
                            onCancel = { showPriceForm = false },
                            onSubmit = { name, specification, brand, unit, price, supplier, category, note ->
                                scope.launch {
                                    projectRepository.addMaterialPriceEntry(
                                        name = name,
                                        specification = specification,
                                        brand = brand,
                                        unit = unit,
                                        referencePrice = price,
                                        supplier = supplier,
                                        category = category,
                                        note = note
                                    )
                                    showPriceForm = false
                                }
                            }
                        )
                    }
                }

                if (filteredPrices.isEmpty()) {
                    item { MaterialLibraryEmptyText("没有匹配的材料价格") }
                }

                items(filteredPrices, key = MaterialPriceEntrySummary::id) { entry ->
                    MaterialPriceRow(
                        entry = entry,
                        supplier = overview.suppliers.firstOrNull { it.name == entry.supplier },
                        onEdit = {
                            editingPriceId = if (editingPriceId == entry.id) null else entry.id
                            showPriceForm = false
                        },
                        onDelete = {
                            scope.launch { projectRepository.deleteMaterialPriceEntry(entry.id) }
                        }
                    )
                    if (editingPriceId == entry.id) {
                        Spacer(modifier = Modifier.height(8.dp))
                        MaterialPriceFormCard(
                            formKey = entry.id,
                            initial = entry,
                            knownSuppliers = overview.suppliers.map { it.name },
                            onCancel = { editingPriceId = null },
                            onSubmit = { name, specification, brand, unit, price, supplier, category, note ->
                                scope.launch {
                                    projectRepository.updateMaterialPriceEntry(
                                        entryId = entry.id,
                                        name = name,
                                        specification = specification,
                                        brand = brand,
                                        unit = unit,
                                        referencePrice = price,
                                        supplier = supplier,
                                        category = category,
                                        note = note
                                    )
                                    editingPriceId = null
                                }
                            }
                        )
                    }
                }
            }

            MaterialLibrarySection.Suppliers -> {
                item {
                    Button(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            showSupplierForm = !showSupplierForm
                            editingSupplierId = null
                        }
                    ) {
                        Text(if (showSupplierForm) "收起供应商录入" else "添加供应商")
                    }
                }

                if (showSupplierForm) {
                    item {
                        SupplierFormCard(
                            formKey = "new-supplier",
                            onCancel = { showSupplierForm = false },
                            onSubmit = { name, category, contact, phone, address, note ->
                                scope.launch {
                                    projectRepository.addSupplierProfile(
                                        name = name,
                                        category = category,
                                        contact = contact,
                                        phone = phone,
                                        address = address,
                                        note = note
                                    )
                                    showSupplierForm = false
                                }
                            }
                        )
                    }
                }

                if (filteredSuppliers.isEmpty()) {
                    item { MaterialLibraryEmptyText("没有匹配的供应商") }
                }

                items(filteredSuppliers, key = SupplierProfileSummary::id) { supplier ->
                    SupplierProfileRow(
                        supplier = supplier,
                        linkedPriceCount = overview.priceEntries.count { it.supplier == supplier.name },
                        onEdit = {
                            editingSupplierId = if (editingSupplierId == supplier.id) null else supplier.id
                            showSupplierForm = false
                        },
                        onDelete = {
                            scope.launch { projectRepository.deleteSupplierProfile(supplier.id) }
                        }
                    )
                    if (editingSupplierId == supplier.id) {
                        Spacer(modifier = Modifier.height(8.dp))
                        SupplierFormCard(
                            formKey = supplier.id,
                            initial = supplier,
                            onCancel = { editingSupplierId = null },
                            onSubmit = { name, category, contact, phone, address, note ->
                                scope.launch {
                                    projectRepository.updateSupplierProfile(
                                        supplierId = supplier.id,
                                        name = name,
                                        category = category,
                                        contact = contact,
                                        phone = phone,
                                        address = address,
                                        note = note
                                    )
                                    editingSupplierId = null
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MaterialLibraryMetrics(overview: MaterialLibraryOverview) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        MaterialLibraryMetric("价格", overview.priceEntries.size.toString(), Modifier.weight(1f))
        MaterialLibraryMetric("已报价", overview.pricedMaterialCount.toString(), Modifier.weight(1f))
        MaterialLibraryMetric("缺价", overview.missingPriceCount.toString(), Modifier.weight(1f))
        MaterialLibraryMetric("供应商", overview.suppliers.size.toString(), Modifier.weight(1f))
    }
}

@Composable
private fun MaterialLibraryMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun MaterialLibraryToolbar(
    section: MaterialLibrarySection,
    onSectionChange: (MaterialLibrarySection) -> Unit,
    onImportDefaults: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        MaterialLibrarySection.entries.forEach { target ->
            FilterChip(
                selected = section == target,
                onClick = { onSectionChange(target) },
                label = { Text(target.title) }
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        TextButton(onClick = onImportDefaults) {
            Text("补充预置")
        }
    }
}

@Composable
private fun MaterialLibraryCategoryRow(
    categories: List<String>,
    selectedCategory: String?,
    onSelectCategory: (String?) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        FilterChip(
            selected = selectedCategory == null,
            onClick = { onSelectCategory(null) },
            label = { Text("全部") }
        )
        categories.forEach { category ->
            FilterChip(
                selected = selectedCategory == category,
                onClick = { onSelectCategory(category) },
                label = { Text(category) }
            )
        }
    }
}

@Composable
private fun MaterialPriceRow(
    entry: MaterialPriceEntrySummary,
    supplier: SupplierProfileSummary?,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = entry.displayName,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(entry.category, entry.brand, entry.supplier)
                            .filter(String::isNotBlank)
                            .joinToString(" · ")
                            .ifBlank { "未填写分类/品牌/供应商" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = if (entry.referencePrice.isBlank()) "未报价" else "${entry.referencePrice}/${entry.unit}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (entry.referencePrice.isBlank()) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    }
                )
            }
            if (supplier != null) {
                Text(
                    text = listOfNotNull(
                        supplier.contact.takeIf(String::isNotBlank)?.let { "联系人 $it" },
                        supplier.phone.takeIf(String::isNotBlank),
                        supplier.address.takeIf(String::isNotBlank)
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (entry.note.isNotBlank()) {
                Text(text = entry.note, style = MaterialTheme.typography.bodyMedium)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onEdit) { Text("编辑") }
                TextButton(onClick = onDelete) { Text("删除") }
            }
        }
    }
}

@Composable
private fun SupplierProfileRow(
    supplier: SupplierProfileSummary,
    linkedPriceCount: Int,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = supplier.name.ifBlank { "未命名供应商" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = supplier.category.ifBlank { "未分类" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = "$linkedPriceCount 项价格",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                text = listOfNotNull(
                    supplier.contact.takeIf(String::isNotBlank)?.let { "联系人 $it" },
                    supplier.phone.takeIf(String::isNotBlank),
                    supplier.address.takeIf(String::isNotBlank)
                ).joinToString(" · ").ifBlank { "未填写联系方式" },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (supplier.note.isNotBlank()) {
                Text(text = supplier.note, style = MaterialTheme.typography.bodyMedium)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onEdit) { Text("编辑") }
                TextButton(onClick = onDelete) { Text("删除") }
            }
        }
    }
}

@Composable
private fun MaterialPriceFormCard(
    formKey: String,
    knownSuppliers: List<String>,
    initial: MaterialPriceEntrySummary? = null,
    onCancel: () -> Unit,
    onSubmit: (
        name: String,
        specification: String,
        brand: String,
        unit: String,
        price: String,
        supplier: String,
        category: String,
        note: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initial?.name) { mutableStateOf(initial?.name.orEmpty()) }
    var specification by rememberSaveable(formKey, initial?.specification) { mutableStateOf(initial?.specification.orEmpty()) }
    var brand by rememberSaveable(formKey, initial?.brand) { mutableStateOf(initial?.brand.orEmpty()) }
    var unit by rememberSaveable(formKey, initial?.unit) { mutableStateOf(initial?.unit ?: "项") }
    var price by rememberSaveable(formKey, initial?.referencePrice) { mutableStateOf(initial?.referencePrice.orEmpty()) }
    var supplier by rememberSaveable(formKey, initial?.supplier) { mutableStateOf(initial?.supplier.orEmpty()) }
    var category by rememberSaveable(formKey, initial?.category) { mutableStateOf(initial?.category ?: "其他") }
    var note by rememberSaveable(formKey, initial?.note) { mutableStateOf(initial?.note.orEmpty()) }

    MaterialLibraryFormContainer(title = if (initial == null) "添加材料价格" else "编辑材料价格") {
        MaterialLibraryField(name, { name = it }, "材料名称")
        MaterialLibraryField(specification, { specification = it }, "规格")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MaterialLibraryField(brand, { brand = it }, "品牌", Modifier.weight(1f))
            MaterialLibraryField(unit, { unit = it }, "单位", Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MaterialLibraryField(price, { price = it }, "参考单价", Modifier.weight(1f))
            MaterialLibraryField(category, { category = it }, "分类", Modifier.weight(1f))
        }
        MaterialLibraryField(supplier, { supplier = it }, "供应商")
        if (knownSuppliers.isNotEmpty()) {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                knownSuppliers.distinct().forEach { value ->
                    FilterChip(
                        selected = supplier == value,
                        onClick = { supplier = value },
                        label = { Text(value) }
                    )
                }
            }
        }
        MaterialLibraryField(note, { note = it }, "备注")
        MaterialLibraryFormActions(
            canSubmit = name.trim().isNotBlank(),
            onCancel = onCancel,
            onSubmit = {
                onSubmit(name, specification, brand, unit, price, supplier, category, note)
            }
        )
    }
}

@Composable
private fun SupplierFormCard(
    formKey: String,
    initial: SupplierProfileSummary? = null,
    onCancel: () -> Unit,
    onSubmit: (
        name: String,
        category: String,
        contact: String,
        phone: String,
        address: String,
        note: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initial?.name) { mutableStateOf(initial?.name.orEmpty()) }
    var category by rememberSaveable(formKey, initial?.category) { mutableStateOf(initial?.category ?: "综合材料") }
    var contact by rememberSaveable(formKey, initial?.contact) { mutableStateOf(initial?.contact.orEmpty()) }
    var phone by rememberSaveable(formKey, initial?.phone) { mutableStateOf(initial?.phone.orEmpty()) }
    var address by rememberSaveable(formKey, initial?.address) { mutableStateOf(initial?.address.orEmpty()) }
    var note by rememberSaveable(formKey, initial?.note) { mutableStateOf(initial?.note.orEmpty()) }

    MaterialLibraryFormContainer(title = if (initial == null) "添加供应商" else "编辑供应商") {
        MaterialLibraryField(name, { name = it }, "供应商名称")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MaterialLibraryField(category, { category = it }, "分类", Modifier.weight(1f))
            MaterialLibraryField(contact, { contact = it }, "联系人", Modifier.weight(1f))
        }
        MaterialLibraryField(phone, { phone = it }, "电话")
        MaterialLibraryField(address, { address = it }, "地址")
        MaterialLibraryField(note, { note = it }, "备注")
        MaterialLibraryFormActions(
            canSubmit = name.trim().isNotBlank(),
            onCancel = onCancel,
            onSubmit = {
                onSubmit(name, category, contact, phone, address, note)
            }
        )
    }
}

@Composable
private fun MaterialLibraryFormContainer(
    title: String,
    content: @Composable () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            content()
        }
    }
}

@Composable
private fun MaterialLibraryField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true
    )
}

@Composable
private fun MaterialLibraryFormActions(
    canSubmit: Boolean,
    onCancel: () -> Unit,
    onSubmit: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End
    ) {
        TextButton(onClick = onCancel) { Text("取消") }
        Button(onClick = onSubmit, enabled = canSubmit) { Text("保存") }
    }
}

@Composable
private fun MaterialLibraryEmptyText(text: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun materialLibraryMatches(
    entry: MaterialPriceEntrySummary,
    keyword: String
): Boolean {
    val normalized = keyword.trim()
    if (normalized.isBlank()) return true
    return listOf(
        entry.name,
        entry.specification,
        entry.brand,
        entry.unit,
        entry.referencePrice,
        entry.supplier,
        entry.category,
        entry.note
    ).any { value -> value.contains(normalized, ignoreCase = true) }
}

private fun materialLibraryMatches(
    supplier: SupplierProfileSummary,
    keyword: String
): Boolean {
    val normalized = keyword.trim()
    if (normalized.isBlank()) return true
    return listOf(
        supplier.name,
        supplier.category,
        supplier.contact,
        supplier.phone,
        supplier.address,
        supplier.note
    ).any { value -> value.contains(normalized, ignoreCase = true) }
}
