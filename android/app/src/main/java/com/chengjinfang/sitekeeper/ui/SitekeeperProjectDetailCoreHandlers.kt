package com.chengjinfang.sitekeeper.ui

import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal fun buildProjectOverviewActions(
    projectId: String,
    projectRepository: ProjectRepository,
    scope: CoroutineScope
): ProjectOverviewActions =
    ProjectOverviewActions(
        onUpdateProject = { name, location, managerName, contractAmount, expectedEndDate ->
            scope.launch {
                projectRepository.updateProject(
                    projectId = projectId,
                    name = name,
                    location = location,
                    managerName = managerName,
                    contractAmount = contractAmount,
                    expectedEndDate = expectedEndDate
                )
            }
        },
        onSetProjectArchived = { archived ->
            scope.launch {
                projectRepository.setProjectArchived(
                    projectId = projectId,
                    archived = archived
                )
            }
        }
    )
