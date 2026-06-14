package com.example.datarecorder

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean

class FastVoiceAudioRecorder(
    private val sampleRate: Int = 16_000,
    private val channelConfig: Int = AudioFormat.CHANNEL_IN_MONO,
    private val audioFormat: Int = AudioFormat.ENCODING_PCM_16BIT
) {
    private val running = AtomicBoolean(false)
    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null

    fun start(
        onPcmData: (ByteArray) -> Unit,
        onError: (Throwable) -> Unit
    ) {
        if (running.get()) return

        val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        if (bufferSize <= 0) {
            onError(IllegalStateException("无法初始化录音缓冲区"))
            return
        }

        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            onError(IllegalStateException("无法初始化麦克风"))
            return
        }

        audioRecord = recorder
        running.set(true)
        recordThread = Thread {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buffer = ByteArray(bufferSize)
            try {
                recorder.startRecording()
                while (running.get()) {
                    val readSize = recorder.read(buffer, 0, buffer.size)
                    if (readSize <= 0) {
                        if (running.get()) {
                            throw IllegalStateException("读取麦克风数据失败：$readSize")
                        }
                        break
                    }
                    onPcmData(buffer.copyOf(readSize))
                }
            } catch (error: Throwable) {
                if (running.get()) {
                    onError(error)
                }
            } finally {
                running.set(false)
                runCatching {
                    if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        recorder.stop()
                    }
                }
                runCatching { recorder.release() }
                if (audioRecord === recorder) {
                    audioRecord = null
                }
                if (recordThread === Thread.currentThread()) {
                    recordThread = null
                }
            }
        }.apply {
            name = "FastVoiceAudioRecorder"
            start()
        }
    }

    fun stop() {
        running.set(false)
        val thread = recordThread
        audioRecord?.let { recorder ->
            runCatching {
                if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop()
                }
            }
        }
        thread?.interrupt()
        if (thread != null && thread !== Thread.currentThread()) {
            runCatching { thread.join(400) }
        }
        if (recordThread === thread && thread?.isAlive != true) {
            recordThread = null
        }
    }

    fun release() {
        stop()
    }
}
