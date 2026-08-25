import SwiftUI

/// Small, durable visual vocabulary for a utility that is seen many times a day.
enum JustRightTheme {
    static let accent = Color(red: 0.10, green: 0.52, blue: 0.38)
    static let warning = Color.orange
    static let critical = Color.red
    static let subtleFill = Color(nsColor: .quaternarySystemFill)
}

struct LimitPresetButton: View {
    let value: Int
    @Binding var selection: Int

    var body: some View {
        Button("\(value)") {
            selection = value
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selection == value ? JustRightTheme.accent : .secondary)
        .accessibilityLabel("Set charge limit to \(value) percent")
    }
}
