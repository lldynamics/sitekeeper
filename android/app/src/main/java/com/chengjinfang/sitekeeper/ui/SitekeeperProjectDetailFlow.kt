package com.chengjinfang.sitekeeper.ui

import androidx.compose.runtime.Composable
import com.chengjinfang.sitekeeper.database.project.ProjectDetail

@Composable
internal fun ProjectDetailScreen(
    detail: ProjectDetail,
    onBack: () -> Unit,
    overviewActions: ProjectOverviewActions,
    dailyTodoActions: ProjectDailyTodoActions,
    financeMaterialActions: ProjectFinanceMaterialActions,
    assetsActions: ProjectAssetsActions,
    commercialActions: ProjectCommercialActions
) {
    ProjectDetailScreenContent(
        detail = detail,
        onBack = onBack,
        overviewActions = overviewActions,
        dailyTodoActions = dailyTodoActions,
        financeMaterialActions = financeMaterialActions,
        assetsActions = assetsActions,
        commercialActions = commercialActions
    )
}
