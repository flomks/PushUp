package com.sinura.data.api.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Subset of `public.user_settings` columns read via PostgREST for dashboard layout sync.
 */
@Serializable
data class UserSettingsCloudRowDTO(
    @SerialName("dashboard_widget_order_json")
    val dashboardWidgetOrderJson: String? = null,
)
