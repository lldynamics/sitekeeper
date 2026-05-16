package com.chengjinfang.sitekeeper

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.chengjinfang.sitekeeper.ui.SitekeeperApp
import com.chengjinfang.sitekeeper.ui.theme.SitekeeperTheme

class MainActivity : ComponentActivity() {
    private val appContainer: AppContainer by lazy {
        AppContainer(applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            SitekeeperTheme {
                SitekeeperApp(
                    projectRepository = appContainer.projectRepository,
                    seedInitialData = appContainer::seedInitialData
                )
            }
        }
    }
}
