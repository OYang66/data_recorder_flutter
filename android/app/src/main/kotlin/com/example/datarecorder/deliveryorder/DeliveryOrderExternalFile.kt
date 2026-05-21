package com.example.datarecorder.deliveryorder

data class DeliveryOrderExternalFile(
    val path: String,
    val fileName: String,
    val mimeType: String?,
    val source: String = "android_intent"
) {
    fun toChannelMap(): Map<String, Any?> = mapOf(
        "path" to path,
        "fileName" to fileName,
        "mimeType" to mimeType,
        "source" to source
    )
}
