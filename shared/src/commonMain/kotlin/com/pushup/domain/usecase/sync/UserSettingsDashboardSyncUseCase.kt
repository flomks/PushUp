package com.pushup.domain.usecase.sync

import com.pushup.data.api.CloudSyncApi
import com.pushup.domain.usecase.GetUserSettingsUseCase
import com.pushup.domain.usecase.UpdateUserSettingsUseCase

/**
 * Syncs [com.pushup.domain.model.UserSettings.dashboardWidgetOrderJson] with
 * Supabase `user_settings.dashboard_widget_order_json` (same row as credit / privacy settings).
 */
class UserSettingsDashboardSyncUseCase(
    private val getUserSettingsUseCase: GetUserSettingsUseCase,
    private val updateUserSettingsUseCase: UpdateUserSettingsUseCase,
    private val cloudSyncApi: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
) {

    /** Overwrites local JSON when the server has a non-blank value (used after full cloud pull). */
    suspend fun mergeFromRemote(userId: String) {
        if (!networkMonitor.isConnected()) return
        val remoteJson = runCatching {
            cloudSyncApi.getUserSettingsDashboardWidgetOrderJson(userId)
        }.getOrNull()
        if (remoteJson.isNullOrBlank()) return
        val local = getUserSettingsUseCase(userId)
        if (local.dashboardWidgetOrderJson == remoteJson) return
        updateUserSettingsUseCase(local.copy(dashboardWidgetOrderJson = remoteJson))
    }

    /** PATCHes the current local JSON to Supabase (call after local DB update). */
    suspend fun pushToRemote(userId: String) {
        if (!networkMonitor.isConnected()) return
        val local = getUserSettingsUseCase(userId)
        val json = local.dashboardWidgetOrderJson ?: return
        runCatching {
            cloudSyncApi.patchUserSettingsDashboardWidgetOrderJson(userId, json)
        }
    }
}
