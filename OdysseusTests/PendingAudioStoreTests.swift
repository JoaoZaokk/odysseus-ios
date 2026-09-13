import XCTest
@testable import Odysseus

/// The recording is on disk before any engine is touched, and "pending" is
/// the file's existence — so a kill while loading a model costs a retry.
final class PendingAudioStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pending-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    private func tone(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.05)) * 0.5 }
    }

    func testWAVRoundTrip() throws {
        let frames = tone(seconds: 0.5)
        let data = WAV.encode(frames, sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + frames.count * 2)
        let back = try XCTUnwrap(WAV.decode(data))
        XCTAssertEqual(back.sampleRate, 16_000)
        XCTAssertEqual(back.frames.count, frames.count)
        for i in stride(from: 0, to: frames.count, by: 997) {
            XCTAssertEqual(back.frames[i], frames[i], accuracy: 1.0 / 32767 + 0.0001)
        }
        XCTAssertNil(WAV.decode(Data("not a wav at all, honestly".utf8)))
    }

    func testSaveListFramesDelete() throws {
        let frames = tone(seconds: 1.5)
        let p = try XCTUnwrap(PendingAudioStore.save(frames: frames, engine: "model", modelID: "w-turbo-q5", language: "pt", in: dir))
        XCTAssertEqual(p.seconds, 1.5, accuracy: 0.001)
        XCTAssertEqual(p.attempts, 0)
        let listed = PendingAudioStore.list(in: dir)
        XCTAssertEqual(listed, [p])
        XCTAssertEqual(PendingAudioStore.frames(of: p, in: dir)?.count, frames.count)
        // No .part left behind: the write is rename-based.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".part") })
        XCTAssertEqual(Set(names), ["\(p.id).wav", "\(p.id).json"])

        let bumped = PendingAudioStore.bumpAttempts(p, in: dir)
        XCTAssertEqual(bumped.attempts, 1)
        XCTAssertEqual(PendingAudioStore.list(in: dir).first?.attempts, 1, "attempts are persisted before the engine loads")

        PendingAudioStore.delete(p, in: dir)
        XCTAssertTrue(PendingAudioStore.list(in: dir).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    func testOrphansAreHandledWithoutABook() throws {
        // A wav with no sidecar is still offered (duration from the header).
        let frames = tone(seconds: 2)
        try WAV.encode(frames, sampleRate: 16_000).write(to: dir.appendingPathComponent("lonely.wav"))
        // A sidecar with no wav is garbage and goes away.
        try Data("{}".utf8).write(to: dir.appendingPathComponent("ghost.json"))
        let listed = PendingAudioStore.list(in: dir)
        XCTAssertEqual(listed.map(\.id), ["lonely"])
        XCTAssertEqual(listed[0].seconds, 2, accuracy: 0.01)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ghost.json").path))
    }

    func testPurgeKeepsNewestFiveAndDropsOldTakes() throws {
        for i in 0..<7 {
            var p = try XCTUnwrap(PendingAudioStore.save(frames: tone(seconds: 0.4), engine: "model", modelID: "m", language: nil, in: dir))
            p.at = Date().addingTimeInterval(Double(-i * 3600))
            PendingAudioStore.write(p, in: dir)
        }
        var old = try XCTUnwrap(PendingAudioStore.save(frames: tone(seconds: 0.4), engine: "model", modelID: "m", language: nil, in: dir))
        old.at = Date().addingTimeInterval(-8 * 24 * 3600)
        PendingAudioStore.write(old, in: dir)
        PendingAudioStore.purge(in: dir)
        let left = PendingAudioStore.list(in: dir)
        XCTAssertEqual(left.count, 5)
        XCTAssertFalse(left.contains { $0.id == old.id })
    }
}
