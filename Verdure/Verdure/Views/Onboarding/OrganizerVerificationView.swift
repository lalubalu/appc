import SwiftUI

/// Verification flow to gain Organizer status. Presented from sign-up (when the
/// user chooses Organizer) and from Profile → Settings → "Become an Organizer".
/// On a successful submission it grants organizer status (sets @AppStorage).
struct OrganizerVerificationView: View {
    @AppStorage("accountType") private var accountTypeRaw = AccountType.visitor.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase { case form, verifying, done }
    @State private var phase: Phase = .form
    @State private var org = ""
    @State private var role = ""
    @State private var officialEmail = ""
    @State private var website = ""
    @State private var agreed = false
    @State private var appear = false

    private var isValid: Bool {
        !org.trimmingCharacters(in: .whitespaces).isEmpty &&
        !role.trimmingCharacters(in: .whitespaces).isEmpty &&
        officialEmail.contains("@") && agreed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VerdureBackground()
                switch phase {
                case .form: formView
                case .verifying: verifyingView
                case .done: doneView
                }
            }
            .navigationTitle("Become an Organizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase == .form {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appear = true } }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                labeled("ORGANIZATION NAME") {
                    ClayField(placeholder: "e.g. Green Community Alliance", text: $org)
                }
                labeled("YOUR ROLE") {
                    ClayField(placeholder: "e.g. Events Coordinator", text: $role)
                }
                labeled("OFFICIAL EMAIL") {
                    ClayField(placeholder: "you@organization.org", text: $officialEmail,
                              contentType: .emailAddress, keyboard: .emailAddress, autocap: false)
                }
                labeled("WEBSITE (OPTIONAL)") {
                    ClayField(placeholder: "https://…", text: $website,
                              keyboard: .URL, autocap: false)
                }

                Button { Haptics.soft(); withAnimation(.spring(response: 0.4)) { agreed.toggle() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(agreed ? Palette.spruce.base : Palette.inkFaint)
                        Text("I confirm I'm authorized to host events for this organization.")
                            .font(VType.body(13, .medium)).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(ClayBackground(style: .inset, radius: Radius.sm))
                }
                .buttonStyle(.plain)

                ClayButton("Submit for Verification", systemImage: "checkmark.shield.fill",
                           kind: .spruce, fullWidth: true) { submit() }
                    .disabled(!isValid).opacity(isValid ? 1 : 0.5)

                Text("Verification usually takes under a minute in this demo. In production this is reviewed by the Verdure team.")
                    .font(VType.body(12)).foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 2)
            }
            .padding(Spacing.lg)
            .padding(.bottom, 40)
            .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ClayIconTile(systemImage: "megaphone.fill", kind: .spruce, size: 64, radius: Radius.md)
                .breathing(scale: 1.05, duration: 2.6)
            Text("Host events for your community")
                .font(VType.display(24, .semibold)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Organizers can create and manage local events. Tell us a bit about you to get verified.")
                .font(VType.body(14)).foregroundStyle(Palette.inkSoft).lineSpacing(3)
        }
    }

    private func labeled<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(VType.body(10, .bold)).tracking(0.8).foregroundStyle(Palette.inkSoft)
            content()
        }
    }

    // MARK: - Verifying

    private var verifyingView: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                PulseHalo(color: Palette.spruce.base.opacity(0.6), size: 120, lineWidth: 2)
                PulseHalo(color: Palette.teal.base.opacity(0.5), size: 150, lineWidth: 1.5)
                ClayIconTile(systemImage: "shield.lefthalf.filled", kind: .spruce, size: 80, radius: Radius.md)
                    .breathing(scale: 1.08, duration: 1.4)
            }
            Text("Verifying…").font(VType.display(24, .semibold)).foregroundStyle(Palette.ink)
            Text("Checking your organization details").font(VType.body(14)).foregroundStyle(Palette.inkSoft)
            ProgressView().tint(Palette.spruce.base)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                PulseHalo(color: Palette.spruce.base.opacity(0.6), size: 150, lineWidth: 2)
                ClayIconTile(systemImage: "checkmark.seal.fill", kind: .spruce, size: 96, radius: Radius.md)
                    .breathing(scale: 1.06, duration: 2.4)
            }
            VStack(spacing: 8) {
                Text("You're verified!").font(VType.display(28, .bold)).foregroundStyle(Palette.ink)
                Text("You can now create and host events from the Events tab.")
                    .font(VType.body(15)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
            }
            ClayButton("Start Organizing", systemImage: "arrow.right", kind: .spruce, fullWidth: true) {
                dismiss()
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(Spacing.lg)
    }

    private func submit() {
        Haptics.tap()
        withAnimation(.spring(response: 0.4)) { phase = .verifying }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            accountTypeRaw = AccountType.organizer.rawValue
            Haptics.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { phase = .done }
        }
    }
}

#Preview {
    OrganizerVerificationView()
}
