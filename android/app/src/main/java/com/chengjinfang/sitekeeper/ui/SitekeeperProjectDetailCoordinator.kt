package com.chengjinfang.sitekeeper.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.project.ProjectRepository

@Composable
internal fun ProjectDetailCoordinatorScreen(
    detail: ProjectDetail,
    projectRepository: ProjectRepository,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val projectId = detail.project.id

    val overviewActions = buildProjectOverviewActions(
        projectId = projectId,
        projectRepository = projectRepository,
        scope = scope
    )
    val dailyTodoActions = buildProjectDailyTodoActions(
        projectId = projectId,
        projectRepository = projectRepository,
        scope = scope
    )
    val financeMaterialActions = buildProjectFinanceMaterialActions(
        projectId = projectId,
        projectRepository = projectRepository,
        scope = scope
    )
    val assetsActions = buildProjectAssetsActions(
        projectId = projectId,
        projectRepository = projectRepository,
        scope = scope,
        context = context
    )
    val commercialActions = buildProjectCommercialActions(
        projectId = projectId,
        projectRepository = projectRepository,
        scope = scope
    )

    ProjectDetailScreen(
        detail = detail,
        onBack = onBack,
        overviewActions = overviewActions,
        dailyTodoActions = dailyTodoActions,
        financeMaterialActions = financeMaterialActions,
        assetsActions = assetsActions,
        commercialActions = commercialActions
    )
}
