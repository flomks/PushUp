package com.sinura.domain.usecase.sync

import com.sinura.data.api.CloudSyncApi
import com.sinura.domain.usecase.GetUserSettingsUseCase
import com.sinura.domain.usecase.UpdateUserSettingsUseCase

/**
 * Syncs [com.sinura.domain.model.UserSettings.dashboardWidgetOrderJson] with
 * Supabase `user_settings.dashboard_widget_order_json` (same row as credit / privacy settings).
 *
 * **Empty dashboard:** the app persists an explicit JSON array `[]`. That is *not* the same as SQL `NULL`
 * ([UserSettings.dashboardWidgetOrderJson] unset = “never synced / use in-app default until user edits”).
 */
class UserSettingsDashboardSyncUseCase(
    private val getUserSettingsUseCase: GetUserSettingsUseCase,
    private val updateUserSettingsUseCase: UpdateUserSettingsUseCase,
    private val cloudSyncApi: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
) {

    /**
     * Seeds local layout from the server only while [UserSettings.dashboardWidgetOrderJson] is still `null`.
     *
     * Once the user has any persisted value on this device — including explicit empty `"[]"` —
     * we do **not** overwrite from cloud. Otherwise every [SyncFromCloudUseCase] pull could resurrect
     * stale server JSON after the user removed all widgets locally (a common single-device bug).
     */
    suspend fun mergeFromRemote(userId: String) {
        if (!networkMonitor.isConnected()) return
        val remoteJson = runCatching {
            cloudSyncApi.getUserSettingsDashboardWidgetOrderJson(userId)
        }.getOrNull()
        if (remoteJson.isNullOrBlank()) return
        val local = getUserSettingsUseCase(userId)
        if (local.dashboardWidgetOrderJson != null) return
        updateUserSettingsUseCase(local.copy(dashboardWidgetOrderJson = remoteJson))
    }

    /** PATCHes the current local JSON to Supabase (call after local DB update). Empty layout uses `"[]"`. */
    suspend fun pushToRemote(userId: String) {
        if (!networkMonitor.isConnected()) return
        val local = getUserSettingsUseCase(userId)
        val json = local.dashboardWidgetOrderJson ?: return
        runCatching {
            cloudSyncApi.patchUserSettingsDashboardWidgetOrderJson(userId, json)
        }
    }
}
