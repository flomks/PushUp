package com.pushup.domain.model

/**
 * The available exercise types in the app.
 *
 * Each exercise type has a stable [id] that is used as the database key
 * (both in the local SQLDelight table and in the Supabase `exercise_levels` table).
 * The [id] values intentionally match the Swift `WorkoutType.rawValue` strings so
 * that both platforms use the same identifiers.
 */
enum class ExerciseType(val id: String) {
    PUSH_UPS("pushUps"),
    PLANK("plank"),
    JUMPING_JACKS("jumpingJacks"),
    SQUATS("squats"),
    CRUNCHES("crunches"),
    JOGGING("jogging");

    companion object {
        /**
         * Resolves an [ExerciseType] from its stable [id] string.
         *
         * @throws NoSuchElementException if [id] does not match any known type.
         */
        fun fromId(id: String): ExerciseType =
            entries.first { it.id == id }
    }
}
