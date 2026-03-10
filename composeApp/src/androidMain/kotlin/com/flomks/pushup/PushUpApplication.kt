package com.flomks.pushup

import android.app.Application
import com.flomks.pushup.di.presentationModule
import com.pushup.di.initKoin

/**
 * Application entry point for the PushUp Android app.
 *
 * Initialises Koin with the shared modules, the Android platform module,
 * and the Compose presentation module (ViewModels).
 *
 * Registered in AndroidManifest.xml via `android:name=".PushUpApplication"`.
 */
class PushUpApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        initKoin(
            context = this,
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseAnonKey = BuildConfig.SUPABASE_ANON_KEY,
            isDebug = BuildConfig.DEBUG,
            presentationModule,
        )
    }
}
