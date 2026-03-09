package com.flomks.pushup

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import com.flomks.pushup.di.presentationModule
import com.pushup.di.initKoin

fun main() {
    initKoin(presentationModule)
    application {
        Window(
            onCloseRequest = ::exitApplication,
            title = "PushUp",
        ) {
            App()
        }
    }
}