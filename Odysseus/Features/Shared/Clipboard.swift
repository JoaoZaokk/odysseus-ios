import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One place for "put this on the clipboard" on both targets.
enum Clipboard {
    static func copy(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
    }
}
