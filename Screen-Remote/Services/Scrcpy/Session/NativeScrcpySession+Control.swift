import AppKit
import Darwin
import Foundation

extension NativeScrcpySession {
    func sendKeyEvent(
        keyCode: UInt32,
        action: ScrcpyKeyAction,
        repeatCount: UInt32 = 0,
        metaState: UInt32 = 0
    ) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(14)
        bytes.append(0) // SC_CONTROL_MSG_TYPE_INJECT_KEYCODE
        bytes.append(action.rawValue)
        Self.appendBigEndian(keyCode, to: &bytes)
        Self.appendBigEndian(repeatCount, to: &bytes)
        Self.appendBigEndian(metaState, to: &bytes)
        enqueueControlMessage(Data(bytes))
    }

    func sendText(_ text: String) {
        for payload in Self.utf8Chunks(text, maximumByteCount: 300) {
            var bytes = [UInt8]()
            bytes.reserveCapacity(payload.count + 5)
            bytes.append(1) // SC_CONTROL_MSG_TYPE_INJECT_TEXT
            Self.appendBigEndian(UInt32(payload.count), to: &bytes)
            bytes.append(contentsOf: payload)
            enqueueControlMessage(Data(bytes))
        }
    }

    func requestClipboard(copyKey: UInt8) {
        guard copyKey <= 2 else { return }
        enqueueControlMessage(Data([8, copyKey])) // SC_CONTROL_MSG_TYPE_GET_CLIPBOARD
    }

    func setClipboardAndPaste(_ text: String) {
        let payload = Self.utf8Prefix(text, maximumByteCount: (1 << 18) - 14)
        var bytes = [UInt8]()
        bytes.reserveCapacity(payload.count + 14)
        bytes.append(9) // SC_CONTROL_MSG_TYPE_SET_CLIPBOARD
        Self.appendBigEndian(UInt64.max, to: &bytes) // No acknowledgement requested.
        bytes.append(1)
        Self.appendBigEndian(UInt32(payload.count), to: &bytes)
        bytes.append(contentsOf: payload)
        enqueueControlMessage(Data(bytes))
    }

    func sendStartApp(_ packageName: String) {
        let encodedName = Array(packageName.utf8.prefix(255))
        guard !encodedName.isEmpty else { return }
        var bytes = [UInt8]()
        bytes.reserveCapacity(encodedName.count + 2)
        bytes.append(16) // SC_CONTROL_MSG_TYPE_START_APP
        bytes.append(UInt8(encodedName.count))
        bytes.append(contentsOf: encodedName)
        enqueueControlMessage(Data(bytes))
    }

    func sendTouch(action: ScrcpyTouchAction, point: CGPoint, screenSize: CGSize) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.pointerMessage(
            action: action,
            pointerID: UInt64.max - 1,
            point: point,
            screenSize: screenSize,
            pressure: action == .up ? 0 : 1,
            actionButton: 0,
            buttons: 0
        )
        enqueueControlMessage(message)
    }

    func sendMouseMove(
        point: CGPoint,
        screenSize: CGSize,
        buttons: UInt32
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.pointerMessage(
            action: buttons == 0 ? .hoverMove : .move,
            pointerID: UInt64.max,
            point: point,
            screenSize: screenSize,
            pressure: 1,
            actionButton: 0,
            buttons: buttons
        )
        enqueueControlMessage(message)
    }

    func sendMouseButton(
        action: ScrcpyTouchAction,
        button: ScrcpyMouseButton,
        point: CGPoint,
        screenSize: CGSize,
        buttons: UInt32
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.pointerMessage(
            action: action,
            pointerID: UInt64.max,
            point: point,
            screenSize: screenSize,
            pressure: action == .up ? 0 : 1,
            actionButton: button.rawValue,
            buttons: buttons
        )
        enqueueControlMessage(message)
    }

    func sendMouseScroll(
        point: CGPoint,
        screenSize: CGSize,
        horizontal: CGFloat,
        vertical: CGFloat,
        buttons: UInt32
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.scrollMessage(
            point: point,
            screenSize: screenSize,
            horizontal: horizontal,
            vertical: vertical,
            buttons: buttons
        )
        enqueueControlMessage(message)
    }

    private static func pointerMessage(
        action: ScrcpyTouchAction,
        pointerID: UInt64,
        point: CGPoint,
        screenSize: CGSize,
        pressure: Float,
        actionButton: UInt32,
        buttons: UInt32
    ) -> Data {
        let width = UInt16(clamping: max(Int(screenSize.width.rounded()), 1))
        let height = UInt16(clamping: max(Int(screenSize.height.rounded()), 1))
        let pointX = UInt32(clamping: max(Int(point.x.rounded()), 0))
        let pointY = UInt32(clamping: max(Int(point.y.rounded()), 0))

        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        bytes.append(2) // SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT
        bytes.append(action.rawValue)
        appendBigEndian(pointerID, to: &bytes)
        appendBigEndian(pointX, to: &bytes)
        appendBigEndian(pointY, to: &bytes)
        appendBigEndian(width, to: &bytes)
        appendBigEndian(height, to: &bytes)
        let encodedPressure = UInt16(clamping: Int((max(min(pressure, 1), 0) * 65_535).rounded()))
        appendBigEndian(encodedPressure, to: &bytes)
        appendBigEndian(actionButton, to: &bytes)
        appendBigEndian(buttons, to: &bytes)
        return Data(bytes)
    }

    private static func scrollMessage(
        point: CGPoint,
        screenSize: CGSize,
        horizontal: CGFloat,
        vertical: CGFloat,
        buttons: UInt32
    ) -> Data {
        let width = UInt16(clamping: max(Int(screenSize.width.rounded()), 1))
        let height = UInt16(clamping: max(Int(screenSize.height.rounded()), 1))
        let pointX = UInt32(clamping: max(Int(point.x.rounded()), 0))
        let pointY = UInt32(clamping: max(Int(point.y.rounded()), 0))
        let horizontalValue = scaledScrollValue(horizontal)
        let verticalValue = scaledScrollValue(vertical)

        var bytes = [UInt8]()
        bytes.reserveCapacity(21)
        bytes.append(3) // SC_CONTROL_MSG_TYPE_INJECT_SCROLL_EVENT
        appendBigEndian(pointX, to: &bytes)
        appendBigEndian(pointY, to: &bytes)
        appendBigEndian(width, to: &bytes)
        appendBigEndian(height, to: &bytes)
        appendBigEndian(horizontalValue, to: &bytes)
        appendBigEndian(verticalValue, to: &bytes)
        appendBigEndian(buttons, to: &bytes)
        return Data(bytes)
    }

    func startControlReceiver(
        socket: Int32,
        onClipboardChanged: @escaping (String) -> Void,
        log: @escaping (String) -> Void
    ) {
        DispatchQueue(label: "com.screenremote.scrcpy.native.control.receiver", qos: .userInitiated).async {
            while let type = Self.receiveControlBytes(socket: socket, count: 1)?.first {
                switch type {
                case 0: // DEVICE_MSG_TYPE_CLIPBOARD
                    guard let lengthData = Self.receiveControlBytes(socket: socket, count: 4) else { return }
                    let length = Int(Self.readBigEndianUInt32(lengthData))
                    guard length <= (1 << 18) - 5,
                          let payload = Self.receiveControlBytes(socket: socket, count: length),
                          let text = String(data: payload, encoding: .utf8) else {
                        log("Native scrcpy received an invalid clipboard message")
                        return
                    }
                    onClipboardChanged(text)
                case 1: // DEVICE_MSG_TYPE_ACK_CLIPBOARD
                    guard Self.receiveControlBytes(socket: socket, count: 8) != nil else { return }
                case 2: // DEVICE_MSG_TYPE_UHID_OUTPUT
                    guard let header = Self.receiveControlBytes(socket: socket, count: 4) else { return }
                    let length = Int(header[2]) << 8 | Int(header[3])
                    guard Self.receiveControlBytes(socket: socket, count: length) != nil else { return }
                default:
                    log("Native scrcpy received an unknown control message type: \(type)")
                    return
                }
            }
        }
    }

    private static let scrollNoiseThreshold: CGFloat = 0.001
    private static let scrollCurveScale: CGFloat = 20

    private static func scaledScrollValue(_ delta: CGFloat) -> Int16 {
        guard abs(delta) >= scrollNoiseThreshold else { return 0 }
        let direction = delta >= 0 ? 1.0 : -1.0
        let smoothed = tanh(Double(abs(delta / scrollCurveScale)))
        let payload = smoothed * Double(Int16.max) * direction
        return Int16(clamping: Int(payload.rounded()))
    }

    private static func utf8Chunks(_ text: String, maximumByteCount: Int) -> [[UInt8]] {
        var chunks = [[UInt8]]()
        var current = [UInt8]()
        for scalar in text.unicodeScalars {
            let bytes = Array(String(scalar).utf8)
            if current.count + bytes.count > maximumByteCount, !current.isEmpty {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }
            current.append(contentsOf: bytes)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func utf8Prefix(_ text: String, maximumByteCount: Int) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(min(text.utf8.count, maximumByteCount))
        for scalar in text.unicodeScalars {
            let bytes = Array(String(scalar).utf8)
            guard result.count + bytes.count <= maximumByteCount else { break }
            result.append(contentsOf: bytes)
        }
        return result
    }

    private static func receiveControlBytes(socket: Int32, count: Int) -> Data? {
        if count == 0 { return Data() }
        var data = Data(count: count)
        let receivedAll = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            var offset = 0
            while offset < count {
                let received = Darwin.recv(socket, baseAddress.advanced(by: offset), count - offset, 0)
                if received > 0 {
                    offset += received
                } else if received < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        return receivedAll ? data : nil
    }

    private static func readBigEndianUInt32(_ data: Data) -> UInt32 {
        data.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        let bigEndian = value.bigEndian
        withUnsafeBytes(of: bigEndian) { bytes.append(contentsOf: $0) }
    }
}
