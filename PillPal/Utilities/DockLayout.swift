import SwiftUI

enum DockLayout {
    // Keeps content slightly above the custom dock and center plus button.
    static let contentBottomInset: CGFloat = 92
}

extension View {
    func dockSafeContentInset() -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: DockLayout.contentBottomInset)
        }
    }
}
