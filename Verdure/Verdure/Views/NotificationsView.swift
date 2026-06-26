import SwiftUI

// MARK: - Notifications inbox

struct NotificationsInboxView: View {
    @Environment(\.dismiss) private var dismiss
    private var manager: NotificationManager { .shared }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                if manager.inbox.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.inbox) { note in row(note) }
                    }
                    .padding(Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .background(VerdureBackground())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if manager.unreadCount > 0 {
                        Button("Mark all read") { withAnimation { manager.markAllRead() } }
                            .font(VType.body(13, .semibold)).tint(Palette.spruce.base)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            .onAppear { manager.refreshPermissionStatus() }
        }
    }

    private func row(_ note: AppNotification) -> some View {
        HStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: note.kind.icon, kind: note.kind.kind, size: 46, radius: Radius.chip)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title).font(VType.display(15, .semibold)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note.message).font(VType.body(13)).foregroundStyle(Palette.inkSoft)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 6) {
                Text(note.timeAgo).font(VType.body(11, .medium)).foregroundStyle(Palette.inkFaint)
                if !note.isRead { Circle().fill(Palette.teal.base).frame(width: 8, height: 8) }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .claySurface(.surface, radius: Radius.md, elevation: note.isRead ? 0.5 : 0.9)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(note.isRead ? Color.clear : note.kind.kind.accent.base.opacity(0.35), lineWidth: 1.5))
        .opacity(note.isRead ? 0.85 : 1)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: "bell.slash", kind: .spruce, size: 66, radius: Radius.md)
            Text("You're all caught up").font(VType.display(19, .semibold)).foregroundStyle(Palette.ink)
            Text("Reminders, badges, and community activity will show up here.")
                .font(VType.body(14)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 90).padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Notification settings (from Profile → Settings)

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private var manager: NotificationManager { .shared }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Master enable
                    HStack(spacing: Spacing.md) {
                        ClayIconTile(systemImage: "bell.fill", kind: .gold, size: 44, radius: Radius.chip)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push notifications").font(VType.display(16, .semibold)).foregroundStyle(Palette.ink)
                            Text(manager.permissionGranted ? "Allowed in iOS Settings" : "Tap to allow")
                                .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { manager.enabled },
                            set: { on in
                                manager.enabled = on
                                if on && !manager.permissionGranted { Task { await manager.requestPermission() } }
                            })).labelsHidden().tint(Palette.spruce.base)
                    }
                    .padding(Spacing.md).claySurface(.surface, radius: Radius.md)

                    Text("WHAT YOU'LL BE NOTIFIED ABOUT")
                        .font(VType.body(11, .bold)).tracking(1).foregroundStyle(Palette.inkSoft)
                        .padding(.top, Spacing.sm)

                    VStack(spacing: 0) {
                        typeRow("calendar.badge.clock", "Event reminders", "Before events you've saved", .spruce)
                        divider
                        typeRow("rosette", "Badges & milestones", "When you unlock something new", .gold)
                        divider
                        typeRow("diamond.fill", "Daily Gem", "A new neighborhood fact each day", .terracotta)
                        divider
                        typeRow("bubble.left.and.bubble.right.fill", "Community activity", "Mentions and nearby posts", .teal)
                    }
                    .padding(.vertical, 6).claySurface(.surface, radius: Radius.md)

                    if !manager.permissionGranted {
                        Text("Notifications are off in iOS Settings. Turning the switch on will ask for permission.")
                            .font(VType.body(12)).foregroundStyle(Palette.inkFaint)
                            .padding(.horizontal, Spacing.xs)
                    }
                }
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .background(VerdureBackground())
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            .onAppear { manager.refreshPermissionStatus() }
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.surfaceShadow.opacity(0.4)).frame(height: 1).padding(.leading, 64)
    }

    private func typeRow(_ icon: String, _ title: String, _ subtitle: String, _ kind: ClayStyle.ClayAccentKind) -> some View {
        HStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: icon, kind: kind, size: 38, radius: Radius.chip)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(VType.body(15, .semibold)).foregroundStyle(Palette.ink)
                Text(subtitle).font(VType.body(12)).foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                .foregroundStyle(manager.enabled ? Palette.spruce.base : Palette.inkFaint)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
        .opacity(manager.enabled ? 1 : 0.5)
    }
}
