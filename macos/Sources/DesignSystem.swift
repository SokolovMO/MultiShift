import AppKit
import SwiftUI

/// Independent neutral tokens shared by every owned surface. No accent-color dependency.
enum Mono {
    static let ink = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let windowColor = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.075 : 0.965, alpha: 1)
    }
    static let canvas = Color(nsColor: windowColor)
    static let card = color(light: 0.99, dark: 0.115)
    static let inset = color(light: 0.935, dark: 0.15)
    static let line = color(light: 0.0, dark: 1.0, lightAlpha: 0.075, darkAlpha: 0.12)
    static let selection = color(light: 0.0, dark: 1.0, lightAlpha: 0.075, darkAlpha: 0.105)
    static let sidebarExpanded = MultiInterfaceMetrics.sidebarExpanded
    static let sidebarCollapsed = MultiInterfaceMetrics.sidebarCollapsed
    static let sidebarMotion = Animation.timingCurve(1.0 / 3, 1, 2.0 / 3, 1, duration: MultiInterfaceMetrics.sidebarDuration)
    static let spring = Animation.timingCurve(0.23, 1, 0.32, 1, duration: MultiInterfaceMetrics.navigationDuration)

    private static func color(light: CGFloat, dark: CGFloat,
                              lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : spring
    }
}

struct MonoSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = MultiInterfaceMetrics.Radius.lg
    var floating = false

    func body(content: Content) -> some View {
        content
            .background {
                if floating && !opaque {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Mono.card.opacity(0.65))
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Mono.card)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(contrast == .increased ? Mono.ink.opacity(0.45) : Mono.line, lineWidth: 1))
            .shadow(color: .black.opacity(floating ? (scheme == .dark ? 0.22 : 0.07) : 0.025),
                    radius: floating ? 14 : 3, x: 0, y: floating ? 6 : 1)
    }
}

extension View {
    func monoSurface(radius: CGFloat = MultiInterfaceMetrics.Radius.lg, floating: Bool = false) -> some View {
        modifier(MonoSurface(radius: radius, floating: floating))
    }
}

typealias MonoButtonStyle = MultiActionButtonStyle

struct Keycap: View {
    let text: String
    var active = false
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: 23, minHeight: 23)
            .padding(.horizontal, 3)
            .foregroundStyle(Mono.ink)
            .background(active ? Mono.selection : Mono.inset, in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.xs))
            .overlay(RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.xs).strokeBorder(Mono.line, lineWidth: 1))
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 1).fill(Mono.line).frame(height: 2).padding(.horizontal, 3) }
    }
}

struct ActionRowStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration, selected: selected) }
    private struct Row: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label.foregroundStyle(Mono.ink)
                .background(selected || hovered || configuration.isPressed ? Mono.selection : .clear,
                            in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm).strokeBorder(selected ? Mono.line : .clear, lineWidth: 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.1), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: size * 0.56, weight: .black))
            .foregroundStyle(Mono.ink)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Mono.card, Mono.inset], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(Mono.line, lineWidth: 0.7))
            .shadow(color: .black.opacity(0.08), radius: size * 0.13, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

struct PaneHeading: View {
    let title: String
    let subtitle: String
    var symbol = "slider.horizontal.3"
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: MultiInterfaceMetrics.Space.sm) {
                Text(title).font(.system(size: 20, weight: .semibold)).tracking(-0.45)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Mono.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Mono.secondary).padding(.top, 3)
        }.foregroundStyle(Mono.ink)
            .background {
                if ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] != nil {
                    MultiMeasurement(kind: "heading", radius: 0)
                }
            }
    }
}

extension OperationStatus {
    var symbol: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle"
        case .failed, .undoFailed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        case .undone: return "arrow.uturn.backward.circle"
        case .running: return "clock"
        }
    }
}


/// Native editing and keyboard traversal with an explicit neutral focus indicator.
struct MonoTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        Editor(configuration: configuration)
    }
    private struct Editor<Content: View>: View {
        let configuration: Content
        @FocusState private var focused: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.textFieldStyle(.plain).focused($focused)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Mono.inset, in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm)
                    .strokeBorder(focused ? Mono.ink.opacity(0.65) : Mono.line, lineWidth: focused ? 1.5 : 0.7))
                .opacity(enabled ? 1 : 0.5)
        }
    }
}
