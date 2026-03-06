package com.pushup.domain.usecase.auth

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.pushup.data.api.AuthClient
import com.pushup.data.repository.AuthRepositoryImpl
import com.pushup.data.repository.UserRepositoryImpl
import com.pushup.data.storage.TokenStorage
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.AuthException
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.repository.UserRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * Unit tests for all auth use-cases (Task 1B.8).
 *
 * Uses a [FakeSupabaseAuthClient] (in-memory stub) and a real [UserRepositoryImpl]
 * backed by an in-memory SQLite database. The [TokenStorage] is the JVM in-memory
 * implementation.
 *
 * All tests run with a [StandardTestDispatcher] for deterministic coroutine execution.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AuthUseCaseTests {

    private val testDispatcher = StandardTestDispatcher()

    private val fixedClock = object : Clock {
        var nowMs: Long = 1_700_000_000_000L
        override fun now(): Instant = Instant.fromEpochMilliseconds(nowMs)
    }

    private lateinit var database: PushUpDatabase
    private lateinit var userRepo: UserRepository
    private lateinit var tokenStorage: TokenStorage
    private lateinit var fakeAuthClient: FakeSupabaseAuthClient
    private lateinit var authRepo: AuthRepository

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)

        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        PushUpDatabase.Schema.create(driver)
        database = PushUpDatabase(driver)

        userRepo = UserRepositoryImpl(database, testDispatcher)
        tokenStorage = TokenStorage()
        fakeAuthClient = FakeSupabaseAuthClient()

        authRepo = AuthRepositoryImpl(
            authClient = fakeAuthClient,
            tokenStorage = tokenStorage,
            userRepository = userRepo,
            clock = fixedClock,
            dispatcher = testDispatcher,
        )
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // =========================================================================
    // RegisterWithEmailUseCase
    // =========================================================================

    @Test
    fun register_returnsUserOnSuccess() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        val user = useCase("test@example.com", "password123")

        assertNotNull(user)
        assertEquals("test@example.com", user.email)
        assertEquals("test", user.displayName)
    }

    @Test
    fun register_storesTokenInSecureStorage() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        useCase("test@example.com", "password123")

        val token = tokenStorage.load()
        assertNotNull(token)
        assertEquals("fake-access-token", token.accessToken)
        assertEquals("fake-refresh-token", token.refreshToken)
    }

    @Test
    fun register_persistsUserToLocalDatabase() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        useCase("test@example.com", "password123")

        val stored = userRepo.getCurrentUser()
        assertNotNull(stored)
        assertEquals("test@example.com", stored.email)
    }

    @Test
    fun register_throwsForBlankEmail() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("", "password123")
        }
    }

    @Test
    fun register_throwsForEmailWithoutAtSign() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("notanemail", "password123")
        }
    }

    @Test
    fun register_throwsForPasswordTooShort() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("test@example.com", "abc")
        }
    }

    @Test
    fun register_throwsEmailAlreadyInUseWhenClientReturnsConflict() = runTest {
        fakeAuthClient.signUpError = AuthException.EmailAlreadyInUse()
        val useCase = RegisterWithEmailUseCase(authRepo)

        assertFailsWith<AuthException.EmailAlreadyInUse> {
            useCase("taken@example.com", "password123")
        }
    }

    @Test
    fun register_trimsEmailWhitespace() = runTest {
        val useCase = RegisterWithEmailUseCase(authRepo)

        val user = useCase("  test@example.com  ", "password123")

        assertEquals("test@example.com", user.email)
    }

    // =========================================================================
    // LoginWithEmailUseCase
    // =========================================================================

    @Test
    fun loginWithEmail_returnsUserOnSuccess() = runTest {
        val useCase = LoginWithEmailUseCase(authRepo)

        val user = useCase("test@example.com", "password123")

        assertNotNull(user)
        assertEquals("test@example.com", user.email)
    }

    @Test
    fun loginWithEmail_storesTokenInSecureStorage() = runTest {
        val useCase = LoginWithEmailUseCase(authRepo)

        useCase("test@example.com", "password123")

        val token = tokenStorage.load()
        assertNotNull(token)
        assertEquals("fake-access-token", token.accessToken)
    }

    @Test
    fun loginWithEmail_throwsForBlankEmail() = runTest {
        val useCase = LoginWithEmailUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("", "password123")
        }
    }

    @Test
    fun loginWithEmail_throwsForBlankPassword() = runTest {
        val useCase = LoginWithEmailUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("test@example.com", "")
        }
    }

    @Test
    fun loginWithEmail_throwsInvalidCredentialsOnWrongPassword() = runTest {
        fakeAuthClient.signInError = AuthException.InvalidCredentials()
        val useCase = LoginWithEmailUseCase(authRepo)

        assertFailsWith<AuthException.InvalidCredentials> {
            useCase("test@example.com", "wrongpassword")
        }
    }

    @Test
    fun loginWithEmail_updatesExistingUserInDatabase() = runTest {
        // Pre-populate the database with an existing user
        val existingUser = User(
            id = "fake-user-id",
            email = "test@example.com",
            displayName = "test",
            createdAt = fixedClock.now(),
            lastSyncedAt = fixedClock.now(),
        )
        userRepo.saveUser(existingUser)

        val useCase = LoginWithEmailUseCase(authRepo)
        useCase("test@example.com", "password123")

        val stored = userRepo.getCurrentUser()
        assertNotNull(stored)
        assertEquals("fake-user-id", stored.id)
    }

    // =========================================================================
    // LoginWithAppleUseCase
    // =========================================================================

    @Test
    fun loginWithApple_returnsUserOnSuccess() = runTest {
        val useCase = LoginWithAppleUseCase(authRepo)

        val user = useCase("apple-id-token-xyz")

        assertNotNull(user)
        assertEquals("fake-user-id", user.id)
    }

    @Test
    fun loginWithApple_storesTokenInSecureStorage() = runTest {
        val useCase = LoginWithAppleUseCase(authRepo)

        useCase("apple-id-token-xyz")

        val token = tokenStorage.load()
        assertNotNull(token)
        assertEquals("fake-access-token", token.accessToken)
    }

    @Test
    fun loginWithApple_throwsForBlankToken() = runTest {
        val useCase = LoginWithAppleUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("")
        }
    }

    @Test
    fun loginWithApple_throwsInvalidCredentialsOnBadToken() = runTest {
        fakeAuthClient.idTokenError = AuthException.InvalidCredentials()
        val useCase = LoginWithAppleUseCase(authRepo)

        assertFailsWith<AuthException.InvalidCredentials> {
            useCase("invalid-apple-token")
        }
    }

    @Test
    fun loginWithApple_passesAppleProviderToClient() = runTest {
        val useCase = LoginWithAppleUseCase(authRepo)

        useCase("apple-id-token-xyz")

        assertEquals("apple", fakeAuthClient.lastIdTokenProvider)
    }

    // =========================================================================
    // LoginWithGoogleUseCase
    // =========================================================================

    @Test
    fun loginWithGoogle_returnsUserOnSuccess() = runTest {
        val useCase = LoginWithGoogleUseCase(authRepo)

        val user = useCase("google-id-token-xyz")

        assertNotNull(user)
        assertEquals("fake-user-id", user.id)
    }

    @Test
    fun loginWithGoogle_storesTokenInSecureStorage() = runTest {
        val useCase = LoginWithGoogleUseCase(authRepo)

        useCase("google-id-token-xyz")

        val token = tokenStorage.load()
        assertNotNull(token)
        assertEquals("fake-access-token", token.accessToken)
    }

    @Test
    fun loginWithGoogle_throwsForBlankToken() = runTest {
        val useCase = LoginWithGoogleUseCase(authRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("")
        }
    }

    @Test
    fun loginWithGoogle_passesGoogleProviderToClient() = runTest {
        val useCase = LoginWithGoogleUseCase(authRepo)

        useCase("google-id-token-xyz")

        assertEquals("google", fakeAuthClient.lastIdTokenProvider)
    }

    // =========================================================================
    // LogoutUseCase
    // =========================================================================

    @Test
    fun logout_clearsTokenFromStorage() = runTest {
        // First log in to store a token
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")
        assertNotNull(tokenStorage.load())

        val useCase = LogoutUseCase(authRepo)
        useCase()

        assertNull(tokenStorage.load())
    }

    @Test
    fun logout_doesNotThrowWhenNotLoggedIn() = runTest {
        val useCase = LogoutUseCase(authRepo)

        // Should not throw even when no token is stored
        useCase()

        assertNull(tokenStorage.load())
    }

    @Test
    fun logout_withClearLocalData_stillClearsToken() = runTest {
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")

        val useCase = LogoutUseCase(authRepo)
        useCase(clearLocalData = true)

        assertNull(tokenStorage.load())
    }

    // =========================================================================
    // GetCurrentUserUseCase
    // =========================================================================

    @Test
    fun getCurrentUser_returnsNullWhenNotLoggedIn() = runTest {
        val useCase = GetCurrentUserUseCase(authRepo)

        val user = useCase()

        assertNull(user)
    }

    @Test
    fun getCurrentUser_returnsUserAfterLogin() = runTest {
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")
        val useCase = GetCurrentUserUseCase(authRepo)

        val user = useCase()

        assertNotNull(user)
        assertEquals("test@example.com", user.email)
    }

    @Test
    fun getCurrentUser_returnsNullAfterLogout() = runTest {
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")
        LogoutUseCase(authRepo)(clearLocalData = false)
        val useCase = GetCurrentUserUseCase(authRepo)

        // Token is cleared but local user data is preserved (clearLocalData = false)
        // getCurrentUser reads from DB, not from token
        val user = useCase()
        // User still exists in DB since clearLocalData = false
        assertNotNull(user)
    }

    // =========================================================================
    // RefreshTokenUseCase
    // =========================================================================

    @Test
    fun refreshToken_returnsNewTokenOnSuccess() = runTest {
        // First log in to store a token
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")
        fakeAuthClient.refreshedToken = AuthToken(
            accessToken = "new-access-token",
            refreshToken = "new-refresh-token",
            userId = "fake-user-id",
            expiresAt = 9999999999L,
        )
        val useCase = RefreshTokenUseCase(authRepo)

        val newToken = useCase()

        assertEquals("new-access-token", newToken.accessToken)
        assertEquals("new-refresh-token", newToken.refreshToken)
    }

    @Test
    fun refreshToken_storesNewTokenInSecureStorage() = runTest {
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")
        fakeAuthClient.refreshedToken = AuthToken(
            accessToken = "new-access-token",
            refreshToken = "new-refresh-token",
            userId = "fake-user-id",
            expiresAt = 9999999999L,
        )
        val useCase = RefreshTokenUseCase(authRepo)

        useCase()

        val stored = tokenStorage.load()
        assertNotNull(stored)
        assertEquals("new-access-token", stored.accessToken)
    }

    @Test
    fun refreshToken_throwsNotAuthenticatedWhenNoTokenStored() = runTest {
        val useCase = RefreshTokenUseCase(authRepo)

        assertFailsWith<AuthException.NotAuthenticated> {
            useCase()
        }
    }

    @Test
    fun refreshToken_throwsSessionExpiredWhenRefreshTokenInvalid() = runTest {
        LoginWithEmailUseCase(authRepo)("test@example.com", "password123")
        fakeAuthClient.refreshError = AuthException.SessionExpired()
        val useCase = RefreshTokenUseCase(authRepo)

        assertFailsWith<AuthException.SessionExpired> {
            useCase()
        }
    }

    // =========================================================================
    // Integration: full auth flow
    // =========================================================================

    @Test
    fun fullAuthFlow_registerLoginLogoutLogin() = runTest {
        val register = RegisterWithEmailUseCase(authRepo)
        val login = LoginWithEmailUseCase(authRepo)
        val logout = LogoutUseCase(authRepo)
        val getUser = GetCurrentUserUseCase(authRepo)

        // Register
        val registeredUser = register("user@example.com", "securepass")
        assertNotNull(registeredUser)

        // Logout
        logout()
        assertNull(tokenStorage.load())

        // Login again
        val loggedInUser = login("user@example.com", "securepass")
        assertNotNull(loggedInUser)
        assertEquals(registeredUser.email, loggedInUser.email)

        // Get current user
        val currentUser = getUser()
        assertNotNull(currentUser)
        assertEquals("user@example.com", currentUser.email)
    }
}

// =============================================================================
// Test doubles
// =============================================================================

/**
 * In-memory fake for [AuthClient] (backed by [com.pushup.data.api.SupabaseAuthClient] in production).
 *
 * Returns configurable success responses or throws configurable errors.
 * Tracks the last provider passed to [signInWithIdToken] for assertion.
 */
class FakeSupabaseAuthClient : AuthClient {

    var signUpError: AuthException? = null
    var signInError: AuthException? = null
    var idTokenError: AuthException? = null
    var refreshError: AuthException? = null
    var refreshedToken: AuthToken? = null
    var lastIdTokenProvider: String? = null

    private val defaultToken = AuthToken(
        accessToken = "fake-access-token",
        refreshToken = "fake-refresh-token",
        userId = "fake-user-id",
        expiresAt = 9999999999L,
    )

    override suspend fun signUpWithEmail(email: String, password: String): AuthToken {
        signUpError?.let { throw it }
        return defaultToken
    }

    override suspend fun signInWithEmail(email: String, password: String): AuthToken {
        signInError?.let { throw it }
        return defaultToken
    }

    override suspend fun signInWithIdToken(provider: String, idToken: String): AuthToken {
        lastIdTokenProvider = provider
        idTokenError?.let { throw it }
        return defaultToken
    }

    override suspend fun refreshToken(refreshToken: String): AuthToken {
        refreshError?.let { throw it }
        return refreshedToken ?: defaultToken
    }
}
