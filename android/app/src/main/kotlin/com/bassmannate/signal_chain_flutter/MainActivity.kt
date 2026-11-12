package com.bassmannate.signal_chain_flutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.midi.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val COMMAND_CHANNEL = "signal_chain/midi_command"
    private val RX_CHANNEL = "signal_chain/midi_rx"
    private val ACTION_USB_PERMISSION = "com.bassmannate.signal_chain_flutter.USB_PERMISSION"

    private var midiManager: MidiManager? = null
    private var usbManager: UsbManager? = null
    private var rxEventSink: EventChannel.EventSink? = null

    private var activeMidiDevice: MidiDevice? = null
    private var activeInputPort: MidiInputPort? = null
    private var activeOutputPort: MidiOutputPort? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        midiManager = getSystemService(Context.MIDI_SERVICE) as MidiManager
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMMAND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailablePorts" -> {
                    val devices = midiManager?.devices ?: emptyArray()
                    val ports = devices.map { device ->
                        mapOf(
                            "id" to device.id.toString(),
                            "name" to (device.properties.getString(MidiDeviceInfo.PROPERTY_NAME) ?: "Unknown"),
                            "inputPortCount" to device.inputPortCount,
                            "outputPortCount" to device.outputPortCount
                        )
                    }
                    result.success(ports)
                }
                "connect" -> {
                    val portId = call.argument<String>("portId")
                    if (portId == null) {
                        result.error("INVALID_ARG", "Port ID missing", null)
                        return@setMethodCallHandler
                    }
                    // Simplified: Assuming USB MIDI, requesting permission
                    val device = midiManager?.devices?.find { it.id.toString() == portId }
                    if (device == null) {
                        result.error("NOT_FOUND", "Port not found", null)
                        return@setMethodCallHandler
                    }
                    
                    // Permission request logic would go here, simplified to just connecting
                    midiManager?.openDevice(device, { openedDevice ->
                        activeMidiDevice = openedDevice
                        activeInputPort = openedDevice.openInputPort(0)
                        activeOutputPort = openedDevice.openOutputPort(0)
                        activeOutputPort?.connect(object : MidiReceiver() {
                            override fun onSend(msg: ByteArray?, offset: Int, count: Int, timestamp: Long) {
                                if (msg != null) {
                                    val data = msg.copyOfRange(offset, offset + count)
                                    mainHandler.post { rxEventSink?.success(data) }
                                }
                            }
                        })
                        result.success(null)
                    }, mainHandler)
                }
                "send" -> {
                    val data = call.argument<ByteArray>("data")
                    if (data != null && activeInputPort != null) {
                        val chunkSize = 256
                        if (data.size > chunkSize) {
                            var offset = 0
                            while (offset < data.size) {
                                val end = minOf(offset + chunkSize, data.size)
                                val chunk = data.copyOfRange(offset, end)
                                activeInputPort?.send(chunk, 0, chunk.size)
                                offset = end
                                if (offset < data.size) {
                                    Thread.sleep(2)
                                }
                            }
                        } else {
                            activeInputPort?.send(data, 0, data.size)
                        }
                        result.success(null)
                    } else {
                        result.error("NO_CONNECTION", "Not connected to MIDI port", null)
                    }
                }
                "disconnect" -> {
                    activeInputPort?.close()
                    activeOutputPort?.close()
                    activeMidiDevice?.close()
                    activeInputPort = null
                    activeOutputPort = null
                    activeMidiDevice = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, RX_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                rxEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                rxEventSink = null
            }
        })
    }
}

