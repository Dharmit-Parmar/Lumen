import Darwin
import Foundation

private let maxPayload: UInt64 = 8_388_608
private let maxConfig = 65_536
private let annexBStart: [UInt8] = [0, 0, 0, 1]

private struct InspectorError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func readExact(_ socket: Int32, count: Int, allowCleanEOF: Bool = false) throws -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: count)
    var offset = 0
    while offset < count {
        let received = bytes.withUnsafeMutableBytes { buffer in
            recv(socket, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
        }
        if received < 0 {
            if errno == EINTR { continue }
            throw InspectorError("receive failed: \(String(cString: strerror(errno)))")
        }
        if received == 0 {
            if allowCleanEOF && offset == 0 { return nil }
            throw InspectorError("connection closed in the middle of a message")
        }
        offset += received
    }
    return bytes
}

private func bigEndian(_ bytes: ArraySlice<UInt8>) -> UInt64 {
    bytes.reduce(0) { ($0 << 8) | UInt64($1) }
}

private func annexBNALTypes(_ payload: [UInt8]) throws -> [UInt8] {
    guard payload.starts(with: annexBStart) else {
        throw InspectorError("video access unit is not Annex-B with four-byte start codes")
    }
    var starts = [0]
    var index = 4
    while index + 4 <= payload.count {
        if payload[index] == 0, payload[index + 1] == 0,
           payload[index + 2] == 0, payload[index + 3] == 1 {
            starts.append(index)
            index += 4
        } else {
            index += 1
        }
    }
    return try starts.indices.map { position in
        let nalStart = starts[position] + 4
        let nalEnd = position + 1 < starts.count ? starts[position + 1] : payload.count
        guard nalStart < nalEnd else { throw InspectorError("empty NAL unit in access unit") }
        return payload[nalStart] & 0x1F
    }
}

private func inspect(_ socket: Int32) throws {
    var configured = false
    var sawKeyframe = false
    var lastTimestamp: UInt64 = 0

    while true {
        guard let header = try readExact(socket, count: 16, allowCleanEOF: true) else {
            if !configured { throw InspectorError("connection ended before config") }
            return
        }
        let length = bigEndian(header[3..<7])
        let type = header[7]
        let timestamp = bigEndian(header[8..<16])
        guard header[0] == 0x4C, header[1] == 0x55, header[2] == 1 else {
            throw InspectorError("bad magic or unsupported protocol version")
        }
        guard (1...3).contains(type) else { throw InspectorError("unknown message type \(type)") }
        guard length > 0, length <= maxPayload else { throw InspectorError("invalid payload length \(length)") }
        if type == 1 && length > maxConfig { throw InspectorError("config payload exceeds \(maxConfig) bytes") }
        guard let payload = try readExact(socket, count: Int(length)) else { fatalError("unreachable") }

        if type == 1 {
            guard !configured, timestamp == 0, payload.count >= 14 else {
                throw InspectorError("invalid or repeated config message")
            }
            let codec = payload[0]
            let width = bigEndian(payload[1..<3])
            let height = bigEndian(payload[3..<5])
            let fps = bigEndian(payload[5..<7])
            let rotation = bigEndian(payload[7..<9])
            let mirror = payload[9]
            let spsLength = Int(bigEndian(payload[10..<12]))
            let ppsLengthOffset = 12 + spsLength
            guard ppsLengthOffset + 2 <= payload.count else { throw InspectorError("truncated SPS in config") }
            let ppsLength = Int(bigEndian(payload[ppsLengthOffset..<(ppsLengthOffset + 2)]))
            guard ppsLengthOffset + 2 + ppsLength == payload.count else {
                throw InspectorError("invalid PPS length in config")
            }
            guard spsLength > 0, ppsLength > 0 else {
                throw InspectorError("config is missing SPS or PPS")
            }
            let spsType = payload[12] & 0x1F
            let ppsType = payload[ppsLengthOffset + 2] & 0x1F
            guard codec == 1, width > 0, height > 0, fps > 0 else {
                throw InspectorError("unsupported codec or invalid video dimensions/rate")
            }
            guard [0, 90, 180, 270].contains(rotation), mirror <= 1 else {
                throw InspectorError("invalid rotation or mirror flag")
            }
            guard spsType == 7, ppsType == 8 else {
                throw InspectorError("config is missing valid SPS/PPS NAL units")
            }
            configured = true
            print("config \(width)x\(height) \(fps)fps rotation=\(rotation) mirror=\(mirror == 1) sps=\(spsLength)B pps=\(ppsLength)B")
            fflush(stdout)
            continue
        }

        guard configured else { throw InspectorError("video received before config") }
        let nalTypes = try annexBNALTypes(payload)
        if type == 2 {
            guard nalTypes.contains(5) else { throw InspectorError("keyframe message contains no IDR NAL unit") }
            sawKeyframe = true
        } else {
            guard sawKeyframe else { throw InspectorError("delta frame received before keyframe") }
            guard !nalTypes.contains(5) else { throw InspectorError("IDR NAL unit must use the keyframe message type") }
            guard nalTypes.contains(where: { (1...4).contains($0) }) else {
                throw InspectorError("delta message contains no non-IDR slice NAL unit")
            }
        }
        guard timestamp >= lastTimestamp else { throw InspectorError("capture timestamps moved backwards") }
        lastTimestamp = timestamp
        print("\(type == 2 ? "keyframe" : "delta") \(length)B capture=\(timestamp)us")
        fflush(stdout)
    }
}

private func connect(host: String, port: Int) throws -> Int32 {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP
    var addresses: UnsafeMutablePointer<addrinfo>?
    let lookup = getaddrinfo(host, String(port), &hints, &addresses)
    guard lookup == 0, let first = addresses else {
        throw InspectorError("cannot resolve \(host): \(String(cString: gai_strerror(lookup)))")
    }
    defer { freeaddrinfo(first) }

    var address = first
    var lastError: Int32 = ECONNREFUSED
    while true {
        let descriptor = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
        if descriptor >= 0 {
            var noDelay: Int32 = 1
            _ = setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))
            if Darwin.connect(descriptor, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 {
                return descriptor
            }
            lastError = errno
            Darwin.close(descriptor)
        } else {
            lastError = errno
        }
        guard let next = address.pointee.ai_next else { break }
        address = next
    }
    throw InspectorError("connect failed: \(String(cString: strerror(lastError)))")
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count <= 2 else { throw InspectorError("usage: inspect_stream [host] [port]") }
    let host = arguments.first ?? "127.0.0.1"
    let port = arguments.count == 2 ? Int(arguments[1]) : 5000
    guard let port, (1...65535).contains(port) else { throw InspectorError("port must be between 1 and 65535") }
    let socket = try connect(host: host, port: port)
    defer { Darwin.close(socket) }
    try inspect(socket)
}

do {
    try run()
} catch {
    fputs("stream error: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
