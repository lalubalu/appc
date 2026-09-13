import SwiftUI

// MARK: - AI Adventure Planner
//
// Ask for how long you've got, get an itinerary of real nearby places shaped by
// the current weather and time of day.
//
// Everything shown here comes back from the server already grounded: the model
// picks only from places the app fetched from its providers, and any stop it
// invents is dropped before the response is sent. So there is no "AI might be
// making this up" disclaimer to write — the constraint is structural.

struct AdventurePlannerView: View {
    let places: [Place]
    let latitude: Double
    let longitude: Double

    @AppStorage("interestCategories") private var interestCategoriesRaw = ""

    @State private var duration: Int = 120
    @State private var plan: AdventurePlan?
    @State private var isPlanning = false
    @State private var errorMessage: String?
    /// Set when the server refuses on quota. Presenting the paywall from here
    /// rather than replacing the screen is what preserves the in-progress
    /// request: `duration` and the loaded `places` stay exactly as they were,
    /// so dismissing the paywall returns the user to a filled-in form, and
    /// subscribing re-runs it for them without retyping anything.
    @State private var quotaWall: QuotaWall?
    @State private var pendingRetry = false
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct QuotaWall: Identifiable {
        let id = UUID()
        let limit: Int
        let resetsOn: Date?
    }

    private let durations = [60, 120, 180, 240]

    private var interests: [String] {
        interestCategoriesRaw.split(separator: ",").map(String.init)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VerdureBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        header
                        durationPicker
                        planButton
                        if let errorMessage { errorCard(errorMessage) }
                        if let plan {
                            planCard(plan)
                            remainingFooter(plan)
                        }
                    }
                    .padding(Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .sheet(item: $quotaWall, onDismiss: { Task { await paywallDismissed() } }) { wall in
                PaywallView()
                    .environment(store)
                    .onAppear { pendingRetry = true }
                    .accessibilityLabel("Verdure Plus. You have used all \(wall.limit) free plans this month.")
            }
            .navigationTitle("Adventure Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(VType.body(16, .semibold))
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "Plan something")
            Text("How long have you got?")
                .font(VType.display(28))
                .foregroundStyle(Palette.ink)
            Text("We'll build a route from real places near you, shaped by today's weather.")
                .font(VType.body(15))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        Haptics.tap()
                        duration = minutes
                    } label: {
                        // Four chips share one row, so at accessibility text
                        // sizes the label has to shrink rather than truncate —
                        // "3 hrs" clipped to "3 h" reads as a different option.
                        Text(label(for: minutes))
                            .font(VType.body(15, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(duration == minutes ? Palette.teal.onColor : Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(ClayPressButtonStyle(
                        style: duration == minutes ? .accent(.teal) : .surface,
                        radius: Radius.chip
                    ))
                    .accessibilityLabel(accessibleLabel(for: minutes))
                    .accessibilityAddTraits(duration == minutes ? [.isSelected] : [])
                }
            }
        }
    }

    private var planButton: some View {
        ClayButton(isPlanning ? "Planning…" : "Plan my adventure",
                   systemImage: isPlanning ? nil : "sparkles",
                   kind: .spruce,
                   fullWidth: true) {
            Task { await runPlan() }
        }
        .disabled(isPlanning)
        .opacity(isPlanning ? 0.7 : 1)
        .accessibilityHint("Builds an itinerary from places near you")
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.gold.base)
                .accessibilityHidden(true)
            Text(message)
                .font(VType.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .claySurface(.surface, radius: Radius.sm)
        .accessibilityElement(children: .combine)
    }

    private func planCard(_ plan: AdventurePlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(plan.title)
                    .font(VType.display(24))
                    .foregroundStyle(Palette.ink)
                if let summary = plan.weatherSummary, let temp = plan.temperatureF {
                    Text("\(temp)°F and \(summary) · about \(plan.totalMinutes) min")
                        .font(VType.body(13, .medium))
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    Text("About \(plan.totalMinutes) min")
                        .font(VType.body(13, .medium))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .accessibilityElement(children: .combine)

            if !plan.intro.isEmpty {
                Text(plan.intro)
                    .font(VType.body(15))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(plan.stops) { stop in
                stopRow(stop)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .claySurface(.surface, radius: Radius.md, elevation: 1.2)
    }

    private func stopRow(_ stop: AdventureStop) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Fixed-size badge: the circle can't grow with the text without
            // pushing the stop description off the row, so the digit scales
            // inside it instead. Hidden from VoiceOver — the order is already
            // spoken in the combined label below.
            Text("\(stop.order)")
                .font(VType.num(15, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Palette.spruce.onColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.spruce.base))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(VType.body(16, .semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(stop.minutes) min")
                    .font(VType.body(12, .medium))
                    .foregroundStyle(Palette.inkSoft)
                Text(stop.why)
                    .font(VType.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(stop.order): \(stop.name), \(stop.minutes) minutes. \(stop.why)")
    }

    // MARK: - Actions

    private func runPlan() async {
        isPlanning = true
        errorMessage = nil
        defer { isPlanning = false }
        do {
            plan = try await AdventurePlannerService().plan(
                places: places,
                interests: interests,
                timeOfDay: AdventurePlannerService.currentTimeOfDay(),
                durationMinutes: duration,
                latitude: latitude,
                longitude: longitude
            )
            Haptics.success()
        } catch AdventurePlannerError.quotaExhausted(let limit, let resetsOn) {
            // Not an error state. The form stays populated underneath.
            plan = nil
            quotaWall = QuotaWall(limit: limit, resetsOn: resetsOn)
        } catch {
            plan = nil
            errorMessage = error.localizedDescription
        }
    }

    /// After the paywall closes: if they subscribed, run the plan they already
    /// asked for. If they didn't, leave the form untouched and say nothing —
    /// they just declined, which isn't an error worth an alert.
    private func paywallDismissed() async {
        guard pendingRetry else { return }
        pendingRetry = false
        if store.isPlus { await runPlan() }
    }

    @ViewBuilder
    private func remainingFooter(_ plan: AdventurePlan) -> some View {
        if let left = plan.plansRemaining {
            HStack(spacing: 6) {
                Image(systemName: left == 0 ? "lock.fill" : "sparkles")
                Text(left == 1 ? "1 free plan left this month"
                               : "\(left) free plans left this month")
            }
            .font(VType.scaledBody(13, .medium))
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
        }
    }

    private func label(for minutes: Int) -> String {
        minutes < 120 ? "1 hr" : "\(minutes / 60) hrs"
    }

    private func accessibleLabel(for minutes: Int) -> String {
        minutes < 120 ? "1 hour" : "\(minutes / 60) hours"
    }
}
