#if os(iOS)
import UIKit
import SwiftUI

/// Pushes the chosen font family into the UIKit chrome, which never consults
/// `Font.ody`: bar button titles, segmented pickers, the search bar field.
///
/// Called at launch and on every font change. A proxy only reaches views made
/// after the call; `OdysseusApp` rebuilds the root on a font change, so the
/// whole tree is made again right after.
///
/// Only the font is set. Colours and bar backgrounds stay with `themedNavBar`
/// — a global `UINavigationBarAppearance` here would fight it.
@MainActor
enum NativeAppearance {
    static func apply(_ family: AppFontFamily) {
        let bar = font(family, size: 17, weight: .regular)
        let barBold = font(family, size: 17, weight: .semibold)
        for state: UIControl.State in [.normal, .highlighted, .disabled, .focused] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: bar], for: state)
        }
        UINavigationBar.appearance().titleTextAttributes = [.font: barBold]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: font(family, size: 34, weight: .bold)]

        let seg = font(family, size: 13, weight: .regular)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: seg], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: font(family, size: 13, weight: .semibold)], for: .selected)

        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = font(family, size: 17, weight: .regular)
    }

    /// The UIKit twin of `Appearance.font(size:weight:)`. Mono, Serif and
    /// Rounded are system designs, not named fonts — only "Anthropic Sans"
    /// resolves by name — so the design goes through the descriptor.
    static func font(_ family: AppFontFamily, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        if let name = family.customName, let custom = UIFont(name: name, size: size) {
            return custom
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch family {
        case .mono: design = .monospaced
        case .serif: design = .serif
        case .rounded: design = .rounded
        case .sans, .anthropic: design = .default
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
#endif
