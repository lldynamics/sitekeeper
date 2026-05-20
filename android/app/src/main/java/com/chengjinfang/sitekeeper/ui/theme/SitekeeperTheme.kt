package com.chengjinfang.sitekeeper.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val SitekeeperLightColors = lightColorScheme(
    primary = Color(0xFF256C5C),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD7F1E7),
    onPrimaryContainer = Color(0xFF062019),
    secondary = Color(0xFF6B5E2E),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF3E7B5),
    onSecondaryContainer = Color(0xFF211B00),
    tertiary = Color(0xFF6E5871),
    onTertiary = Color.White,
    background = Color(0xFFFBFCF8),
    onBackground = Color(0xFF1A1C19),
    surface = Color(0xFFFBFCF8),
    onSurface = Color(0xFF1A1C19),
    surfaceVariant = Color(0xFFE0E5DD),
    onSurfaceVariant = Color(0xFF44483F)
)

@Composable
fun SitekeeperTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = SitekeeperLightColors,
        content = content
    )
}
