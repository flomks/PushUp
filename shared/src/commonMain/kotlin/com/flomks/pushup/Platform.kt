package com.flomks.pushup

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform