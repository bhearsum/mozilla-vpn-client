/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

package com.mozilla.vpn

import android.content.Context
import java.io.File
import java.time.LocalDateTime
import android.util.Log as nativeLog

/*
 * Drop in replacement for android.util.Log 
 * Also stores a copy of all logs in tmp/mozilla_deamon_logs.txt
*/
class Log {
    private var file: File
    private constructor(context: Context) {
        val tempDIR = context.cacheDir
        file = File(tempDIR, "mozilla_deamon_logs.txt")
    }

    companion object {
        var instance: Log? = null
        fun init(ctx: Context) {
            if (instance == null) {
                instance = Log(ctx)
            }
        }
        fun i(tag: String, message: String) {
            instance?.write("[info] - ($tag) - $message")
            nativeLog.i(tag, message)
        }
        fun v(tag: String, message: String) {
            instance?.write("($tag) - $message")
            nativeLog.v(tag, message)
        }
        fun e(tag: String, message: String) {
            instance?.write("[error] - ($tag) - $message")
            nativeLog.e(tag, message)
        }

        fun getContent(): String? {
            return try {
                instance?.file?.readText()
            } catch (e: Exception) {
                "=== Failed to read Daemon Logs === \n ${e.localizedMessage} "
            }
        }

        fun clearFile() {
            instance?.file?.writeText("")
        }
    }
    private fun write(message: String) {
        LocalDateTime.now()
        file.appendText("[${LocalDateTime.now()}] $message  \n")
    }
}