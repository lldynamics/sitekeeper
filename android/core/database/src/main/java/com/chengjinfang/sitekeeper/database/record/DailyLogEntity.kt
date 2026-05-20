package com.chengjinfang.sitekeeper.database.record

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.DailyLog
import com.chengjinfang.sitekeeper.model.backup.LogPhoto

@Entity(
    tableName = "daily_logs",
    indices = [Index("projectId")]
)
data class DailyLogEntity(
    @PrimaryKey val id: String,
    val projectId: String?,
    val date: String,
    val weather: String,
    val content: String,
    val workers: String,
    val safety: String,
    val materials: String,
    val tomorrowPlan: String,
    val photoFileName: String?,
    val photosJson: String,
    val linkedConstructionMethodIdsJson: String
)

data class DailyLogSummary(
    val id: String,
    val date: String,
    val weather: String,
    val content: String,
    val workers: String,
    val safety: String,
    val materials: String,
    val tomorrowPlan: String,
    val photoFileNames: List<String>,
    val linkedConstructionMethodIds: List<String>
) {
    val photoCount: Int
        get() = photoFileNames.size
}

fun DailyLog.toEntity(): DailyLogEntity =
    DailyLogEntity(
        id = id,
        projectId = projectId,
        date = date,
        weather = weather,
        content = content,
        workers = workers,
        safety = safety,
        materials = materials,
        tomorrowPlan = tomorrowPlan,
        photoFileName = photoFileName,
        photosJson = BackupSnapshotJson.encodeLogPhotos(photos),
        linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIDs)
    )

fun DailyLogEntity.toSummary(): DailyLogSummary =
    DailyLogSummary(
        id = id,
        date = date,
        weather = weather,
        content = content,
        workers = workers,
        safety = safety,
        materials = materials,
        tomorrowPlan = tomorrowPlan,
        photoFileNames = mergedDailyLogPhotoFileNames(
            legacyPhotoFileName = photoFileName,
            photos = BackupSnapshotJson.decodeLogPhotos(photosJson)
        ),
        linkedConstructionMethodIds = BackupSnapshotJson.decodeStringList(linkedConstructionMethodIdsJson)
    )

fun DailyLogEntity.toBackupLogPhotos(): List<LogPhoto> =
    BackupSnapshotJson.decodeLogPhotos(photosJson)

fun mergedDailyLogPhotoFileNames(
    legacyPhotoFileName: String?,
    photos: List<LogPhoto>
): List<String> =
    buildList {
        legacyPhotoFileName
            ?.takeIf { it.isNotBlank() }
            ?.let { add(it) }
        photos
            .map { it.fileName }
            .filter(String::isNotBlank)
            .forEach { fileName ->
                if (fileName !in this) {
                    add(fileName)
                }
            }
    }
