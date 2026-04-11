package com.flomks.sinura

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import com.flomks.sinura.di.presentationModule
import com.sinura.di.initKoin

fun main() {
    initKoin(presentationModule)
    application {
        Window(
            onCloseRequest = ::exitApplication,
            title = "Sinura",
        ) {
            App()
        }
    }
}