import SwiftUI

// Cross-platform shims so the one shared SwiftUI source builds for both iOS and
// macOS. The iOS app keeps using the real UIKit-backed modifiers (these macOS
// stand-ins only compile when targeting macOS).

// MARK: - Toolbar placements (both platforms)

extension ToolbarItemPlacement {
    /// Leading edge of the bar. `.topBarLeading` on iOS, `.navigation` on macOS.
    static var odyLeading: ToolbarItemPlacement {
        #if os(macOS)
        return .navigation
        #else
        return .topBarLeading
        #endif
    }

    /// Trailing edge of the bar. `.topBarTrailing` on iOS, `.primaryAction` on macOS.
    static var odyTrailing: ToolbarItemPlacement {
        #if os(macOS)
        return .primaryAction
        #else
        return .topBarTrailing
        #endif
    }
}

// MARK: - iOS-only view modifiers, stubbed to no-ops on macOS

#if os(macOS)

/// Mirrors `NavigationBarItem.TitleDisplayMode` (iOS-only) so call sites compile.
enum ODYTitleDisplayMode { case automatic, inline, large }

/// Mirrors `UIKeyboardType` (iOS-only). Only the cases the app uses are needed,
/// but a few extras are here for completeness.
enum ODYKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad
    case phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch
}

/// Mirrors `TextInputAutocapitalization` (iOS-only).
enum ODYTextInputAutocapitalization { case never, words, sentences, characters }

extension View {
    /// No-op on macOS — the navigation bar has no inline/large title mode there.
    func navigationBarTitleDisplayMode(_ mode: ODYTitleDisplayMode) -> some View { self }

    /// No-op on macOS — there's no software keyboard to hint.
    func keyboardType(_ type: ODYKeyboardType) -> some View { self }

    /// No-op on macOS — autocapitalization is a touch-keyboard concept.
    func textInputAutocapitalization(_ style: ODYTextInputAutocapitalization?) -> some View { self }
}

#endif
