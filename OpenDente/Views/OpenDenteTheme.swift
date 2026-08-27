import SwiftUI

/// The shared visual language for just-right.
///
/// Daily-use surfaces stay quiet. The emerald midpoint is the only brand accent,
/// and spacing is restricted to the 4-point scale from the design system.
enum JustRightTheme {
    enum Space {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
        static let x12: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 16
    }

    static let accent = adaptiveColor(
        light: NSColor(srgbRed: 0.10, green: 0.52, blue: 0.38, alpha: 1),
        dark: NSColor(srgbRed: 0.25, green: 0.72, blue: 0.54, alpha: 1)
    )
    static let canvas = adaptiveColor(
        light: NSColor(srgbRed: 0.969, green: 0.953, blue: 0.918, alpha: 1),
        dark: NSColor(srgbRed: 0.075, green: 0.075, blue: 0.071, alpha: 1)
    )
    static let surface = adaptiveColor(
        light: NSColor(srgbRed: 0.992, green: 0.987, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.110, alpha: 1)
    )
    static let elevatedSurface = adaptiveColor(
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.155, green: 0.155, blue: 0.145, alpha: 1)
    )
    static let subtleFill = adaptiveColor(
        light: NSColor(srgbRed: 0.91, green: 0.90, blue: 0.87, alpha: 1),
        dark: NSColor(srgbRed: 0.19, green: 0.19, blue: 0.18, alpha: 1)
    )
    static let line = adaptiveColor(
        light: NSColor(srgbRed: 0.82, green: 0.80, blue: 0.75, alpha: 1),
        dark: NSColor(srgbRed: 0.27, green: 0.27, blue: 0.25, alpha: 1)
    )
    static let warning = adaptiveColor(
        light: NSColor(srgbRed: 0.66, green: 0.37, blue: 0.08, alpha: 1),
        dark: NSColor(srgbRed: 0.94, green: 0.64, blue: 0.25, alpha: 1)
    )
    static let critical = adaptiveColor(
        light: NSColor(srgbRed: 0.69, green: 0.16, blue: 0.15, alpha: 1),
        dark: NSColor(srgbRed: 0.95, green: 0.40, blue: 0.36, alpha: 1)
    )

    static let displayFont = Font.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()
    static let pageTitleFont = Font.system(size: 24, weight: .semibold)
    static let titleFont = Font.system(size: 16, weight: .semibold)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let labelFont = Font.system(size: 11, weight: .medium)
    static let dataFont = Font.system(size: 12, weight: .medium, design: .monospaced).monospacedDigit()

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct JustRightMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.primary)
                .frame(width: size * 0.32, height: size * 0.72)
                .offset(x: -size * 0.22)
            Capsule()
                .fill(Color.primary)
                .frame(width: size * 0.32, height: size * 0.72)
                .offset(x: size * 0.22)
            Circle()
                .fill(JustRightTheme.accent)
                .frame(width: size * 0.24, height: size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct JRPageHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x2) {
            Text(title)
                .font(JustRightTheme.pageTitleFont)
            Text(detail)
                .font(JustRightTheme.bodyFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, JustRightTheme.Space.x2)
    }
}

struct JRSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x4) {
            VStack(alignment: .leading, spacing: JustRightTheme.Space.x1) {
                Text(title)
                    .font(JustRightTheme.titleFont)
                if let detail {
                    Text(detail)
                        .font(JustRightTheme.bodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JustRightTheme.Space.x2)
    }
}

struct JRSettingRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: JustRightTheme.Space.x6) {
            VStack(alignment: .leading, spacing: JustRightTheme.Space.x1) {
                Text(title)
                    .font(JustRightTheme.bodyFont)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: JustRightTheme.Space.x4)
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JRMetricRow: View {
    let label: String
    let value: String
    var tone: Color = .primary

    var body: some View {
        HStack(spacing: JustRightTheme.Space.x4) {
            Text(label)
                .font(JustRightTheme.labelFont)
                .foregroundStyle(.secondary)
            Spacer(minLength: JustRightTheme.Space.x4)
            Text(value)
                .font(JustRightTheme.dataFont)
                .foregroundStyle(tone)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

struct JRDivider: View {
    var body: some View {
        Rectangle()
            .fill(JustRightTheme.line.opacity(0.7))
            .frame(height: 1)
    }
}

struct JRNotice: View {
    enum Tone {
        case neutral, warning, critical

        var color: Color {
            switch self {
            case .neutral: JustRightTheme.accent
            case .warning: JustRightTheme.warning
            case .critical: JustRightTheme.critical
            }
        }
    }

    let title: String
    let detail: String
    var tone: Tone = .neutral
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: JustRightTheme.Space.x3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(tone.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: JustRightTheme.Space.x1) {
                Text(title)
                    .font(JustRightTheme.labelFont)
                    .foregroundStyle(tone.color)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: JustRightTheme.Space.x2)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(JRSecondaryButtonStyle(compact: true))
            }
        }
        .padding(.vertical, JustRightTheme.Space.x2)
    }
}

struct JRPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 10)
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 40)
            .background(
                RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                    .fill(JustRightTheme.accent.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Rectangle())
    }
}

struct JRSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 32 : 40)
            .background(
                RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                    .fill(configuration.isPressed ? JustRightTheme.subtleFill : JustRightTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                    .stroke(JustRightTheme.line, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Rectangle())
    }
}

struct JRIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(configuration.isPressed ? JustRightTheme.subtleFill : Color.clear))
            .contentShape(Circle())
    }
}

struct LimitPresetButton: View {
    let value: Int
    @Binding var selection: Int

    var body: some View {
        let selected = selection == value
        Button("\(value)") {
            selection = value
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(selected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                .fill(selected ? JustRightTheme.accent : JustRightTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                .stroke(selected ? Color.clear : JustRightTheme.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityLabel("Set charge limit to \(value) percent")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

extension View {
    func justRightCanvas() -> some View {
        self
            .tint(JustRightTheme.accent)
            .background(JustRightTheme.canvas)
    }
}
