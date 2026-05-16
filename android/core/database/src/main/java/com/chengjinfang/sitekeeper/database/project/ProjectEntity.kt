package com.chengjinfang.sitekeeper.database.project

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.Project

@Entity(tableName = "projects")
data class ProjectEntity(
    @PrimaryKey val id: String,
    val name: String,
    val location: String,
    val status: String,
    val customerName: String,
    val customerPhone: String,
    val startDate: String,
    val expectedEndDate: String,
    val managerName: String,
    val contractAmount: String,
    val paidAmount: String,
    val paymentStatus: String,
    val materialCost: String,
    val laborCost: String
)

data class ProjectSummary(
    val id: String,
    val name: String,
    val location: String,
    val status: String,
    val managerName: String,
    val expectedEndDate: String,
    val contractAmount: String,
    val paidAmount: String,
    val paymentStatus: String,
    val dailyLogCount: Int = 0,
    val openTodoCount: Int = 0,
    val financialRecordCount: Int = 0,
    val materialItemCount: Int = 0
)

fun Project.toEntity(): ProjectEntity =
    ProjectEntity(
        id = id,
        name = name,
        location = location,
        status = status,
        customerName = customerName,
        customerPhone = customerPhone,
        startDate = startDate,
        expectedEndDate = expectedEndDate,
        managerName = managerName,
        contractAmount = contractAmount,
        paidAmount = paidAmount,
        paymentStatus = paymentStatus,
        materialCost = materialCost,
        laborCost = laborCost
    )

fun ProjectEntity.toSummary(
    dailyLogCount: Int = 0,
    openTodoCount: Int = 0,
    financialRecordCount: Int = 0,
    materialItemCount: Int = 0
): ProjectSummary =
    ProjectSummary(
        id = id,
        name = name,
        location = location,
        status = status,
        managerName = managerName,
        expectedEndDate = expectedEndDate,
        contractAmount = contractAmount,
        paidAmount = paidAmount,
        paymentStatus = paymentStatus,
        dailyLogCount = dailyLogCount,
        openTodoCount = openTodoCount,
        financialRecordCount = financialRecordCount,
        materialItemCount = materialItemCount
    )
