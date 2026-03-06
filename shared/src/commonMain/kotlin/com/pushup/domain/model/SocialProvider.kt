package com.pushup.domain.model

/**
 * Supported OAuth social login providers.
 *
 * Using a sealed enum instead of a raw [String] prevents typos (e.g. `"Apple"`,
 * `"GOOGLE"`) that would compile but fail at runtime with an opaque server error.
 *
 * The [apiValue] is the exact string expected by the Supabase Auth
 * `POST /auth/v1/token?grant_type=id_token` endpoint.
 */
enum class SocialProvider(val apiValue: String) {
    /** Apple Sign-In. Pass the `identityToken` from `ASAuthorizationAppleIDCredential`. */
    APPLE("apple"),

    /** Google Sign-In. Pass the `idToken` from the Google credential. */
    GOOGLE("google"),
}
