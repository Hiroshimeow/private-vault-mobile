package io.hiroshimeow.private_vault_clonehost.runtime

import android.app.Application
import android.app.Instrumentation
import android.content.Context

internal object GuestApplicationBootstrap {
    fun create(context: Context, classLoader: ClassLoader, applicationClass: String?): Result<Application> = runCatching {
        val className = applicationClass?.takeIf { it.isNotBlank() } ?: Application::class.java.name
        Instrumentation().newApplication(classLoader, className, context).also { it.onCreate() }
    }
}
