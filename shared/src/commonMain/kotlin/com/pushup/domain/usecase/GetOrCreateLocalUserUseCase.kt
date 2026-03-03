package com.pushup.domain.usecase

import com.pushup.domain.model.User
import com.pushup.domain.repository.UserRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Get or create a local "Guest" user.
 *
 * This is a stub implementation for Phase 1A. It checks whether a local user
 * already exists in the database. If one is found it is returned immediately.
 * If no user exists, a new "Guest" user is created with a generated ID,
 * persisted to the local database, and returned.
 *
 * This will be replaced by real authentication in Phase 1B.
 *
 * @property userRepository Repository used to read and persist the user.
 * @property clock Clock used to generate creation timestamps.
 * @property idGenerator Strategy for generating unique user IDs.
 */
class GetOrCreateLocalUserUseCase(
    private val userRepository: UserRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {

    /**
     * Returns the existing local user, or creates and persists a new Guest user.
     *
     * @return The current (or newly created) [User].
     */
    suspend operator fun invoke(): User {
        val existing = userRepository.getCurrentUser()
        if (existing != null) return existing

        val now = clock.now()
        val guestUser = User(
            id = idGenerator.generate(),
            email = "guest@local",
            displayName = "Guest",
            createdAt = now,
            lastSyncedAt = now,
        )
        userRepository.saveUser(guestUser)
        return guestUser
    }
}
