import Foundation

/// Incremental RIFF/WAVE reader for audio that arrives in pieces.
///
/// Streaming TTS forces a choice of wire format, and raw `pcm` is the obvious
/// one until you look for its contract: Fish documents "16-bit, mono" for
/// wav/pcm together but never says whether `pcm` is little-endian, and there
/// are reports of 32-bit float coming back from the same family of servers.
/// Guessing that wrong produces white noise at full volume in the user's ear,
/// which is not an acceptable failure mode.
///
/// So the streaming path asks for `wav` instead. The RIFF header arrives in the
/// first bytes and *states* the sample rate, bit depth and channel count, and
/// both dialects (Fish and OpenAI) support it. The declared chunk sizes are
/// ignored on purpose — a server that streams a WAV it hasn't finished writing
/// has no way to know them, and commonly sends 0 or 0xFFFFFFFF.
struct WAVStreamDecoder {

    struct Format: Equatable {
        var sampleRate: Double
        var channels: Int
        var bitsPerSample: Int
        var isFloat: Bool
    }

    enum Failure: LocalizedError, Equatable {
        case notRIFF
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notRIFF: return "O áudio recebido não é WAV."
            case .unsupported(let what): return "Formato de áudio não suportado: \(what)."
            }
        }
    }

    /// Nil until the `fmt ` chunk has arrived.
    private(set) var format: Format?

    private var pending = Data()
    /// True once the `data` chunk's payload has begun — everything from there on
    /// is audio.
    private var inAudio = false

    /// Feeds newly arrived bytes and returns whatever *whole frames* became
    /// playable. A partial frame is held back until the rest of it arrives, so
    /// the caller never has to align anything.
    mutating func append(_ bytes: Data) throws -> Data {
        pending.append(bytes)
        if !inAudio { try parseHeader() }
        guard inAudio, let format else { return Data() }

        let frame = format.channels * (format.bitsPerSample / 8)
        guard frame > 0 else { throw Failure.unsupported("bloco de 0 byte") }
        let whole = (pending.count / frame) * frame
        guard whole > 0 else { return Data() }
        let out = pending.prefix(whole)
        pending.removeFirst(whole)
        return Data(out)
    }

    /// Walks the chunk list until `data` starts. Returns without consuming
    /// anything when a chunk is still incomplete — the next `append` retries.
    private mutating func parseHeader() throws {
        if format == nil && pending.count >= 12 {
            guard pending.prefix(4).elementsEqual("RIFF".utf8),
                  pending[pending.startIndex + 8 ..< pending.startIndex + 12].elementsEqual("WAVE".utf8)
            else { throw Failure.notRIFF }
        }
        // 12 header bytes, then id(4) + size(4) + payload, payload padded to even.
        var cursor = 12
        while true {
            guard pending.count >= cursor + 8 else { break }
            let id = String(decoding: slice(cursor, 4), as: UTF8.self)
            let size = Int(u32(at: cursor + 4))
            let body = cursor + 8

            if id == "data" {
                pending.removeFirst(body)
                inAudio = true
                guard format != nil else { throw Failure.unsupported("WAV sem cabeçalho fmt") }
                return
            }
            // A streamed non-data chunk can declare a size it cannot know for
            // the same reason `data` does. Waiting for 4 GB of LIST would grow
            // `pending` for the whole response and then report "no audio" for a
            // perfectly good WAV, so an implausible header chunk is an error.
            guard size <= 1 << 20 else {
                throw Failure.unsupported("chunk \(id) declara \(size) bytes")
            }
            guard pending.count >= body + size else { break }   // wait for the rest
            if id == "fmt " { try readFmt(at: body, size: size) }
            cursor = body + size + (size % 2)                   // RIFF pads to even
        }
    }

    private mutating func readFmt(at offset: Int, size: Int) throws {
        guard size >= 16 else { throw Failure.unsupported("fmt truncado") }
        var tag = Int(u16(at: offset))
        let channels = Int(u16(at: offset + 2))
        let rate = Double(u32(at: offset + 4))
        let bits = Int(u16(at: offset + 14))
        // WAVE_FORMAT_EXTENSIBLE hides the real tag in the first two bytes of
        // the sub-format GUID, 24 bytes into the chunk.
        if tag == 0xFFFE, size >= 26 { tag = Int(u16(at: offset + 24)) }

        guard tag == 1 || tag == 3 else { throw Failure.unsupported("codec \(tag)") }
        guard channels == 1 || channels == 2 else { throw Failure.unsupported("\(channels) canais") }
        guard rate > 0 else { throw Failure.unsupported("taxa 0") }
        let isFloat = tag == 3
        guard isFloat ? bits == 32 : (bits == 16 || bits == 32) else {
            throw Failure.unsupported("\(bits) bits")
        }
        format = Format(sampleRate: rate, channels: channels, bitsPerSample: bits, isFloat: isFloat)
    }

    private func slice(_ offset: Int, _ count: Int) -> Data {
        let s = pending.startIndex + offset
        return pending[s ..< s + count]
    }

    private func u16(at offset: Int) -> UInt16 {
        let b = [UInt8](slice(offset, 2))
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    private func u32(at offset: Int) -> UInt32 {
        let b = [UInt8](slice(offset, 4))
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    /// Converts whole frames to mono Float32 in −1…1, which is the one format
    /// the playback graph speaks. Stereo is downmixed rather than kept: the
    /// engines here are all mono, and a stereo reply would otherwise force a
    /// second connection format on the player node mid-reply.
    static func monoFloat(_ frames: Data, _ f: Format) -> [Float] {
        let bytes = [UInt8](frames)
        let width = f.bitsPerSample / 8
        let stride = f.channels * width
        guard stride > 0, bytes.count >= stride else { return [] }
        var out = [Float]()
        out.reserveCapacity(bytes.count / stride)
        for i in Swift.stride(from: 0, to: bytes.count - stride + 1, by: stride) {
            var sum: Float = 0
            for c in 0..<f.channels {
                let o = i + c * width
                if f.isFloat {
                    let raw = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8
                            | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
                    sum += Float(bitPattern: raw)
                } else if width == 2 {
                    let raw = UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8
                    sum += Float(Int16(bitPattern: raw)) / 32768
                } else {
                    let raw = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8
                            | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
                    sum += Float(Int32(bitPattern: raw)) / 2147483648
                }
            }
            out.append(sum / Float(f.channels))
        }
        return out
    }
}
