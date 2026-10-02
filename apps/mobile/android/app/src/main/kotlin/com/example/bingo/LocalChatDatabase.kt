package com.example.bingo

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class LocalChatDatabase(context: Context) :
    SQLiteOpenHelper(context, "bingo_local.db", null, DATABASE_VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE local_users (
                user_id TEXT PRIMARY KEY,
                active_conversation_id TEXT
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE local_conversations (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                timeline_json TEXT
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX local_conversations_user_updated " +
                "ON local_conversations(user_id, updated_at DESC)",
        )
        db.execSQL(
            """
            CREATE TABLE local_messages (
                id TEXT NOT NULL,
                conversation_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                role TEXT NOT NULL,
                message_type TEXT NOT NULL DEFAULT 'chat',
                content TEXT NOT NULL,
                created_at INTEGER,
                assistant_role TEXT,
                run_id TEXT,
                status TEXT NOT NULL DEFAULT 'completed',
                call_status TEXT,
                call_duration_seconds INTEGER,
                PRIMARY KEY (conversation_id, ordinal),
                FOREIGN KEY (conversation_id) REFERENCES local_conversations(id)
                    ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        createRoleOrderTable(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE local_conversations ADD COLUMN timeline_json TEXT")
        }
        if (oldVersion < 3) {
            db.execSQL("ALTER TABLE local_messages ADD COLUMN created_at INTEGER")
        }
        if (oldVersion < 4) {
            db.execSQL("ALTER TABLE local_messages ADD COLUMN assistant_role TEXT")
        }
        if (oldVersion < 5) {
            db.execSQL("ALTER TABLE local_messages ADD COLUMN run_id TEXT")
            db.execSQL(
                "ALTER TABLE local_messages ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'",
            )
        }
        if (oldVersion < 6) {
            db.execSQL(
                "ALTER TABLE local_messages ADD COLUMN message_type TEXT NOT NULL DEFAULT 'chat'",
            )
            db.execSQL("ALTER TABLE local_messages ADD COLUMN call_status TEXT")
            db.execSQL("ALTER TABLE local_messages ADD COLUMN call_duration_seconds INTEGER")
        }
        if (oldVersion < 7) {
            createRoleOrderTable(db)
        }
    }

    private fun createRoleOrderTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE local_role_order (
                user_id TEXT NOT NULL,
                role_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                PRIMARY KEY (user_id, role_id)
            )
            """.trimIndent(),
        )
    }

    fun loadRoleOrder(userId: String): List<String> {
        val roleIds = mutableListOf<String>()
        readableDatabase.query(
            "local_role_order",
            arrayOf("role_id"),
            "user_id = ?",
            arrayOf(userId),
            null,
            null,
            "ordinal ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) roleIds += cursor.getString(0)
        }
        return roleIds
    }

    fun saveRoleOrder(userId: String, roleIds: List<String>) {
        writableDatabase.transaction {
            delete("local_role_order", "user_id = ?", arrayOf(userId))
            roleIds.distinct().forEachIndexed { index, roleId ->
                insertOrThrow("local_role_order", null, ContentValues().apply {
                    put("user_id", userId)
                    put("role_id", roleId)
                    put("ordinal", index)
                })
            }
        }
    }

    fun listConversations(userId: String): List<Map<String, Any>> {
        val items = mutableListOf<Map<String, Any>>()
        readableDatabase.query(
            "local_conversations",
            arrayOf("id", "title", "updated_at"),
            "user_id = ?",
            arrayOf(userId),
            null,
            null,
            "updated_at DESC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                items += mapOf(
                    "id" to cursor.getString(0),
                    "title" to cursor.getString(1),
                    "updated_at" to cursor.getLong(2),
                )
            }
        }
        return items
    }

    fun loadActive(userId: String): Map<String, Any?>? {
        val conversationId = readableDatabase.query(
            "local_users",
            arrayOf("active_conversation_id"),
            "user_id = ?",
            arrayOf(userId),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
        }
        return conversationId?.let { loadConversation(userId, it) }
    }

    fun loadConversation(userId: String, conversationId: String): Map<String, Any?>? {
        val conversation = readableDatabase.query(
            "local_conversations",
            arrayOf("id", "title", "timeline_json"),
            "id = ? AND user_id = ?",
            arrayOf(conversationId, userId),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                Triple(
                    cursor.getString(0),
                    cursor.getString(1),
                    if (cursor.isNull(2)) null else cursor.getString(2),
                )
            } else {
                null
            }
        } ?: return null

        val messages = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(
            "local_messages",
            arrayOf(
                "id",
                "role",
                "message_type",
                "content",
                "created_at",
                "assistant_role",
                "run_id",
                "status",
                "call_status",
                "call_duration_seconds",
            ),
            "conversation_id = ?",
            arrayOf(conversationId),
            null,
            null,
            "ordinal ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                messages += mapOf(
                    "id" to cursor.getString(0),
                    "role" to cursor.getString(1),
                    "message_type" to cursor.getString(2),
                    "content" to cursor.getString(3),
                    "created_at" to if (cursor.isNull(4)) null else cursor.getLong(4),
                    "assistant_role" to if (cursor.isNull(5)) null else cursor.getString(5),
                    "run_id" to if (cursor.isNull(6)) null else cursor.getString(6),
                    "status" to cursor.getString(7),
                    "call_status" to if (cursor.isNull(8)) null else cursor.getString(8),
                    "call_duration_seconds" to if (cursor.isNull(9)) null else cursor.getInt(9),
                )
            }
        }
        return mapOf(
            "id" to conversation.first,
            "title" to conversation.second,
            "timeline_json" to conversation.third,
            "messages" to messages,
        )
    }

    fun saveConversation(
        userId: String,
        conversationId: String,
        title: String,
        messages: List<Map<*, *>>,
        updatedAt: Long,
        timelineJson: String,
    ) {
        writableDatabase.transaction {
            val conversation = ContentValues().apply {
                put("id", conversationId)
                put("user_id", userId)
                put("title", title)
                put("updated_at", updatedAt)
                put("timeline_json", timelineJson)
            }
            insertWithOnConflict(
                "local_conversations",
                null,
                conversation,
                SQLiteDatabase.CONFLICT_REPLACE,
            )
            delete("local_messages", "conversation_id = ?", arrayOf(conversationId))
            messages.forEachIndexed { index, message ->
                insert("local_messages", null, ContentValues().apply {
                    put("id", message["id"] as String)
                    put("conversation_id", conversationId)
                    put("ordinal", index)
                    put("role", message["role"] as String)
                    put("message_type", message["message_type"] as? String ?: "chat")
                    put("content", message["content"] as String)
                    (message["created_at"] as? Number)?.let {
                        put("created_at", it.toLong())
                    }
                    (message["assistant_role"] as? String)?.let {
                        put("assistant_role", it)
                    }
                    (message["run_id"] as? String)?.let {
                        put("run_id", it)
                    }
                    put("status", message["status"] as? String ?: "completed")
                    (message["call_status"] as? String)?.let {
                        put("call_status", it)
                    }
                    (message["call_duration_seconds"] as? Number)?.let {
                        put("call_duration_seconds", it.toInt())
                    }
                })
            }
            setActive(this, userId, conversationId)
        }
    }

    fun setActive(userId: String, conversationId: String?) {
        writableDatabase.transaction { setActive(this, userId, conversationId) }
    }

    private fun setActive(db: SQLiteDatabase, userId: String, conversationId: String?) {
        db.insertWithOnConflict(
            "local_users",
            null,
            ContentValues().apply {
                put("user_id", userId)
                put("active_conversation_id", conversationId)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    private inline fun SQLiteDatabase.transaction(block: SQLiteDatabase.() -> Unit) {
        beginTransaction()
        try {
            block()
            setTransactionSuccessful()
        } finally {
            endTransaction()
        }
    }

    private companion object {
        const val DATABASE_VERSION = 7
    }
}
