package com.sinura.routes

import com.sinura.web.publicWebRoutes
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

class PublicWebRoutesTest {

    @Test
    fun `root serves modern landing page`() = testApplication {
        application {
            routing {
                publicWebRoutes()
            }
        }

        val response = client.get("/")

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals(ContentType.Text.Html.contentType, response.contentType()?.contentType)
        val body = response.bodyAsText()
        assertContains(body, "PushUp Web")
        assertContains(body, "Freund hinzufuegen")
        assertContains(body, "/run/night-crew-berlin")
    }

    @Test
    fun `friend page sanitizes code and exposes deep link`() = testApplication {
        application {
            routing {
                publicWebRoutes()
            }
        }

        val response = client.get("/friend/ab-12<script>")

        assertEquals(HttpStatusCode.OK, response.status)
        val body = response.bodyAsText()
        assertContains(body, "AB12 SCRI PT")
        assertContains(body, "pushup://friend-code/AB12SCRIPT")
        assertContains(body, "In PushUp oeffnen")
    }

    @Test
    fun `run share preview renders share id`() = testApplication {
        application {
            routing {
                publicWebRoutes()
            }
        }

        val response = client.get("/run/crew-night_42")

        assertEquals(HttpStatusCode.OK, response.status)
        val body = response.bodyAsText()
        assertContains(body, "shareId: crew-night_42")
        assertContains(body, "Run Share")
    }
}
