import SwiftUI
import AVFoundation

// MARK: - Thumbnail cache

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let memory = NSCache<NSString, UIImage>()
    private let diskDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("video_thumbnails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func diskURL(for id: String) -> URL {
        diskDir.appendingPathComponent(id).appendingPathExtension("jpg")
    }

    func get(_ id: String) -> UIImage? {
        if let img = memory.object(forKey: id as NSString) { return img }
        guard let data = try? Data(contentsOf: diskURL(for: id)),
              let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: id as NSString)
        return img
    }

    func set(_ image: UIImage, for id: String) {
        memory.setObject(image, forKey: id as NSString)
        if let data = image.jpegData(compressionQuality: 0.75) {
            try? data.write(to: diskURL(for: id))
        }
    }
}

// MARK: - Thumbnail generation

func generateThumbnail(from url: URL, size: CGSize) async -> UIImage? {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = size
    generator.requestedTimeToleranceBefore = .positiveInfinity
    generator.requestedTimeToleranceAfter = .positiveInfinity
    do {
        // Seek 0.5 s in rather than frame zero — recordings start with black
        // frames while the camera sensor auto-adjusts exposure.
        let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        return UIImage(cgImage: cgImage)
    } catch {
        return nil
    }
}

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
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
    var keyboardType: UIKeyboardType = .default
    var multiline: Bool = false
    var clearable: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.mono(11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.8)
            if multiline {
                TextEditor(text: $text)
                    .font(.body(14))
                    .foregroundStyle(.white)
                    .tint(.neonPink)
                    .frame(minHeight: 70)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .scrollContentBackground(.hidden)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 0) {
                    TextField(placeholder, text: $text)
                        .font(.body(14))
                        .foregroundStyle(.white)
                        .tint(.neonPink)
                        .keyboardType(keyboardType)
                        .focused($isFocused)
                    if clearable && !text.isEmpty {
                        Button {
                            text = ""
                            isFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Dark Sheet

struct DarkSheet<Content: View>: View {
    let title: String
    var detents: Set<PresentationDetent> = [.medium]
    var cancelAction: (() -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    content
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if let cancel = cancelAction {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                            .foregroundStyle(Color.neonPink)
                    }
                }
            }
        }
        .presentationDetents(detents)
        .presentationBackground(Color(hex: "0c0c1c"))
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var bordered: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(Color.white.opacity(0.2))
            Text(title)
                .font(.body(13))
                .foregroundStyle(Color.white.opacity(0.3))
            if let subtitle {
                Text(subtitle)
                    .font(.body(12))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(bordered ? Color.white.opacity(0.03) : Color.clear)
        .overlay(borderOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if bordered {
            RoundedRectangle(cornerRadius: 18)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(Color.white.opacity(0.10))
        }
    }
}

// MARK: - Number Badge

struct NumberBadge: View {
    let number: Int
    var color: Color = .neonPink

    var body: some View {
        Text("\(number)")
            .font(.display(13))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.20), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Sign Out Button

struct SignOutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.neonRed)
                .frame(width: 46, height: 46)
                .background(Color.neonRed.opacity(0.12))
                .overlay(Circle().stroke(Color.neonRed.opacity(0.30), lineWidth: 1))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Delete Confirm Sheet

struct DeleteConfirmSheet: View {
    var title: String = "Remove?"
    let message: String
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.neonRed.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.neonRed.opacity(0.25), lineWidth: 1))
                    Image(systemName: "trash")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.neonRed)
                }
                .frame(width: 56, height: 56)
                .padding(.top, 16)

                Text(title)
                    .font(.display(22))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    PillButton(title: "Cancel", style: .secondary, fullWidth: true, action: onCancel)
                    PillButton(title: "Delete", style: .danger, fullWidth: true, action: onDelete)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
        .presentationDetents([.height(280)])
        .presentationBackground(Color(hex: "0c0c1c"))
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

// MARK: - Vid Pill

struct VidPill: View {
    enum Style {
        case cyan
        case neutral
        case dot(color: Color)
    }

    let label: String
    var icon: String? = nil
    var style: Style = .neutral

    private var fg: Color {
        if case .cyan = style { return .neonCyan }
        return Color.white.opacity(0.8)
    }
    private var bg: Color {
        if case .cyan = style { return Color.neonCyan.opacity(0.10) }
        return Color.white.opacity(0.06)
    }
    private var border: Color {
        if case .cyan = style { return Color.neonCyan.opacity(0.30) }
        return Color.white.opacity(0.10)
    }

    var body: some View {
        HStack(spacing: 5) {
            if case .dot(let color) = style {
                Circle()
                    .fill(color)
                    .shadow(color: color, radius: 3)
                    .frame(width: 6, height: 6)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(fg)
            }
            Text(label)
                .font(.mono(11, weight: .bold))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(bg)
        .overlay(Capsule().stroke(border, lineWidth: 1))
        .clipShape(Capsule())
    }
}

// MARK: - Exercise Grip Handle (6-dot reorder handle)

struct ExerciseGripHandle: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 4) {
                    Circle().fill(Color.neonCyan).frame(width: 3, height: 3)
                    Circle().fill(Color.neonCyan).frame(width: 3, height: 3)
                }
            }
        }
        .frame(width: 32, height: 36)
        .background(Color.neonCyan.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.neonCyan.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

// MARK: - Session Stat Box

struct SessionStatBox: View {
    let label: String
    let value: Int
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.mono(9.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.45))
                .tracking(0.08)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.display(22))
                    .foregroundStyle(color)
                Text("/10")
                    .font(.body(12))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
