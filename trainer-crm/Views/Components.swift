import SwiftUI

// MARK: - Avatar

struct AvatarView: View {
    let initials: String
    let colorIndex: Int
    var size: CGFloat = 46
    var cornerRadius: CGFloat = 15

    private var col: AvatarColor { paletteColor(colorIndex) }

    var body: some View {
        Text(initials)
            .font(.display(size * 0.35, weight: .heavy))
            .foregroundStyle(col.text)
            .frame(width: size, height: size)
            .background(col.bg)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(col.border, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Pill Button

struct PillButton: View {
    enum Style { case primary, secondary, cyan, danger }
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(bgColor)
            .foregroundStyle(fgColor)
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var bgColor: Color {
        switch style {
        case .primary:   return Color.neonPink
        case .secondary: return Color.white.opacity(0.08)
        case .cyan:      return Color.neonCyan.opacity(0.15)
        case .danger:    return Color.neonRed.opacity(0.12)
        }
    }
    private var fgColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return Color.white.opacity(0.8)
        case .cyan:      return .neonCyan
        case .danger:    return .neonRed
        }
    }
    private var borderColor: Color {
        switch style {
        case .primary:   return .clear
        case .secondary: return Color.white.opacity(0.12)
        case .cyan:      return Color.neonCyan.opacity(0.35)
        case .danger:    return Color.neonRed.opacity(0.25)
        }
    }
    private var shadowColor: Color {
        switch style {
        case .primary: return Color.neonPink.opacity(0.35)
        case .cyan:    return Color.neonCyan.opacity(0.15)
        default:       return .clear
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let systemImage: String
    var tint: Color = Color.white.opacity(0.7)
    var bg: Color = Color.white.opacity(0.08)
    var border: Color = Color.white.opacity(0.10)
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(bg)
                .overlay(RoundedRectangle(cornerRadius: size * 0.33).stroke(border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.33))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let label: String
    var color: Color = .neonPink

    var body: some View {
        Text(label)
            .font(.mono(11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
            .clipShape(Capsule())
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = ""

    var body: some View {
        HStack {
            Text(title)
                .font(.mono(12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1.2)
            Spacer()
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.neonPink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.display(22))
                .foregroundStyle(.white)
            Text(label)
                .font(.mono(10))
                .foregroundStyle(Color.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Form Field

struct FormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.mono(11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.8)
            TextField(placeholder, text: $text)
                .font(.body(14))
                .foregroundStyle(.white)
                .tint(.neonPink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Bottom Sheet

struct BottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                // Title
                HStack {
                    Text(title)
                        .font(.display(22))
                        .foregroundStyle(.white)
                    Spacer()
                    IconButton(systemImage: "xmark") { isPresented = false }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

                ScrollView {
                    content
                        .padding(.top, 16)
                }
                .frame(maxHeight: 480)

                Spacer(minLength: 0)
            }
            .padding(.bottom, 34)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Toast Notification

struct ToastNotification: View {
    enum Style { case error, success }

    let message: String
    var style: Style = .error
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var accentColor: Color { style == .error ? .neonRed : .neonGreen }
    private var icon: String { style == .error ? "wifi.slash" : "checkmark.circle.fill" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(message)
                .font(.body(13))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accentColor.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: accentColor.opacity(0.2), radius: 16)
        .padding(.horizontal, 16)
        .offset(y: min(dragOffset, 0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        onDismiss()
                    } else {
                        withAnimation(.spring()) { dragOffset = 0 }
                    }
                }
        )
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    let status: ClientStatus
    var body: some View {
        Circle()
            .fill(status == .active ? Color.neonGreen : Color.white.opacity(0.2))
            .frame(width: 8, height: 8)
            .shadow(color: status == .active ? Color.neonGreen.opacity(0.8) : .clear, radius: 4)
    }
}
