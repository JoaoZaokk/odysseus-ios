import XCTest
@testable import Odysseus

/// 1.11 replaced SwiftWhisper with the whisper.cpp xcframework and added the
/// Parakeet engine plus one language-tuned checkpoint per app language. The
/// catalog is data, so these pin the invariants the download manager and the
/// transcriber rely on instead of discovering them on a phone.
final class VoiceCatalogTests: XCTestCase {

    private var shipped: [VoiceModel] { VoiceCatalog.all.filter { !$0.isCustom } }

    func testIDsAndURLsAreUnique() {
        let ids = shipped.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate ids: \(Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys)")
        let urls = shipped.map(\.url.absoluteString)
        XCTAssertEqual(Set(urls).count, urls.count)
    }

    func testEveryURLIsAnHTTPSHuggingFaceResolveLink() {
        for m in shipped {
            XCTAssertEqual(m.url.scheme, "https", m.id)
            XCTAssertEqual(m.url.host, "huggingface.co", m.id)
            XCTAssertTrue(m.url.path.contains("/resolve/main/"), "\(m.id): \(m.url)")
            XCTAssertTrue(m.filename.hasSuffix(".bin"), "\(m.id): \(m.filename)")
            XCTAssertGreaterThan(m.bytes, 10_000_000, m.id)
        }
    }

    func testEngineFollowsTheIDPrefix() {
        for m in shipped {
            switch m.engine {
            case .parakeet: XCTAssertTrue(m.id.hasPrefix("p-"), m.id)
            case .whisper:  XCTAssertTrue(m.id.hasPrefix("w-"), m.id)
            }
        }
        let custom = CustomVoiceModel(id: "u-1", name: "x", urlString: "https://huggingface.co/a/b/resolve/main/c.bin", bytes: 1).model
        XCTAssertEqual(custom?.engine, .whisper)
        XCTAssertEqual(custom?.lang, .universal)
    }

    func testParakeetModelsExistAndHaveNoCoreMLEncoder() {
        let parakeet = shipped.filter { $0.engine == .parakeet }
        XCTAssertGreaterThanOrEqual(parakeet.count, 3, "v3 in three quantizations at least")
        for m in parakeet {
            XCTAssertNil(VoiceCatalog.coreMLZipURL(forID: m.id), "\(m.id) has no Core ML encoder")
            XCTAssertEqual(m.task, .stt)
        }
    }

    func testEveryLanguageBucketHasALabelAndACode() {
        for l in VoiceLang.allCases {
            XCTAssertFalse(l.label.isEmpty, l.rawValue)
            if l == .universal {
                XCTAssertNil(l.whisperCode)
            } else {
                let code = try? XCTUnwrap(l.whisperCode, l.rawValue)
                XCTAssertEqual(code?.count, 2, "\(l.rawValue): \(code ?? "nil")")
            }
        }
        XCTAssertEqual(VoiceLang.allCases.first, .universal)
    }

    func testEveryTunedLanguageShipsAtLeastOneModel() {
        let tuned = Set(shipped.map(\.lang)).subtracting([.universal])
        for l in VoiceLang.allCases where l != .universal {
            XCTAssertTrue(tuned.contains(l), "\(l.rawValue) is in the filter menu but has no model")
        }
    }

    func testFilteringByLanguageKeepsTheUniversalModels() {
        let pt = VoiceCatalog.filtered(task: .stt, lang: .portuguese)
        XCTAssertTrue(pt.contains { $0.lang == .portuguese })
        XCTAssertTrue(pt.contains { $0.lang == .universal })
        XCTAssertFalse(pt.contains { $0.lang == .german })
        let universal = VoiceCatalog.filtered(task: .stt, lang: .universal)
        XCTAssertTrue(universal.allSatisfy { $0.lang == .universal })
    }

    func testNewBucketsAreNamedInTheAppLanguage() {
        let key = "app.language"
        let before = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.set("pt-BR", forKey: key)
        XCTAssertEqual(VoiceLang.german.label, "Alemão")
        XCTAssertEqual(VoiceLang.hebrew.label, "Hebraico")
        UserDefaults.standard.set("en", forKey: key)
        XCTAssertEqual(VoiceLang.german.label, "German")
        XCTAssertEqual(VoiceLang.finnish.label, "Finnish")
        UserDefaults.standard.set("ja", forKey: key)
        XCTAssertEqual(VoiceLang.spanish.label, "スペイン語")
    }

    func testLegacyBilingualRawValueDecodesAsUniversal() throws {
        let decoded = try JSONDecoder().decode([VoiceLang].self, from: Data(#"["bilingual","german","nope"]"#.utf8))
        XCTAssertEqual(decoded, [.universal, .german, .universal])
    }
}
