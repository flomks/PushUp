package com.flomks.sinura

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform