import Foundation

// MARK: - Legal surfaces
//
// App Review 3.1.2 requires an auto-renewable subscription to link to its Terms
// of Use (EULA) and Privacy Policy INSIDE the app, and 5.1.1 requires the policy
// to be reachable from the app. Both documents ship in the binary so the links
// are live even before the marketing site's domain resolves; the web copies are
// offered as well. The text below is the single source for the in-app pages —
// the website mirrors it (Verdure Website/src/app/privacy, /terms).

enum Legal {
    /// Canonical public site. The listing's Support/Privacy URLs are built from
    /// this; deploying the site is a pre-submission blocker in AppStore/LISTING.md.
    static let siteBase = "https://verdure.app"

    /// Apple's standard Licensed Application End User License Agreement — the
    /// EULA declared for the app in App Store Connect, and always reachable.
    static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicyURL = URL(string: "\(siteBase)/privacy")!
    static let termsOfUseURL = URL(string: "\(siteBase)/terms")!
    static let supportURL = URL(string: "\(siteBase)/support")!

    /// The single source of truth for the support address. Declared HERE rather
    /// than on ModerationService: that type is @MainActor, so a nonisolated
    /// static like this one cannot read from it (it did not compile).
    static let contactEmail = "support@verdure.app"
    static let lastUpdated = "September 27, 2026"

    /// Subscription facts, stated once so the paywall, the terms and the store
    /// listing cannot disagree. Prices shown to the user come from StoreKit.
    enum Subscription {
        static let name = "Verdure+"
        static let monthlyLength = "1 month"
        static let yearlyLength = "1 year"
        /// $49.99 vs 12 × $4.99 = $59.88 → 16.5%, rounded to 17. Never claim more.
        static let yearlySavingsPercent = 17
    }

    // MARK: - Terms of Use

    struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let termsSections: [Section] = [
        Section(title: "Agreement",
                body: "These Terms of Use (\"Terms\") are an agreement between you and Verdure (\"we\", \"us\") covering the Verdure iOS app and related services. By creating an account, browsing as a guest, or subscribing, you agree to them. Apple's standard Licensed Application End User License Agreement also applies to the app; where the two conflict, Apple's terms govern the license and these Terms govern everything else."),
        Section(title: "Who can use Verdure",
                body: "You must be at least 13 years old to create an account. If you are under 18, use Verdure with a parent or guardian's permission. You are responsible for keeping your sign-in details private and for everything done through your account."),
        Section(title: "Verdure+ subscription",
                body: "Verdure+ is an optional auto-renewable subscription available as a \(Subscription.monthlyLength) plan or a \(Subscription.yearlyLength) plan. The price and subscription length are shown in the app before you buy and are charged to your Apple ID at confirmation of purchase. The subscription renews automatically at the same price and length unless you turn off auto-renew at least 24 hours before the current period ends. You can manage or cancel it in your Apple ID account settings; cancelling stops future renewals but does not refund the current period, and refund requests are handled by Apple. Member benefits are those listed on the paywall in the version of the app you are using — nothing else is promised. If a benefit is withdrawn we will say so in the app before your next renewal."),
        Section(title: "Points and rewards",
                body: "Points are earned by verified activity in Verdure — checking in at events with your location and a proof photo, and collecting places you physically visit. Points have no cash value, cannot be bought, sold or transferred, and are not your property. Daily earning is capped, and cash gift-card redemptions are limited to a rolling twelve-month value per member and a monthly programme-wide budget; when either limit is reached the app tells you and redemption pauses. Partner perks are fulfilled by the partner on the partner's terms. We may withhold, reverse or cancel points and redemptions obtained through fraud, misrepresentation, automation or abuse, and may close accounts that do so. Rewards are delivered by email to the address on your account and may take several business days."),
        Section(title: "Your content and conduct",
                body: "You own what you post. By posting you give us a licence to show it to other Verdure users as part of the service. Don't post anything unlawful, harassing, hateful, sexually explicit, dangerous, deceptive, or that you don't have the right to share. Every post, event and profile can be reported; reports are reviewed by a person within 24 hours, content reported by several people is hidden immediately, and unreviewed reports lead to removal at the 24-hour mark. You can block any member. We may remove content or suspend accounts that break these rules. Questions about a moderation decision: \(Legal.contactEmail)."),
        Section(title: "Events and safety",
                body: "Events are published by community organizers or gathered from public calendars and ticketing feeds. We don't run them and can't guarantee they take place as listed. Use your own judgement about where you go and who you meet, especially outdoors. Never trespass, and follow the rules of the venue or park."),
        Section(title: "Your account",
                body: "You can delete your account at any time from Profile › Settings › Delete Account. Deletion permanently removes your profile, points, collection, posts, events, RSVPs, photos and any gift cards not yet sent; delivered gift cards are unaffected. We may close inactive or abusive accounts."),
        Section(title: "Disclaimers and liability",
                body: "Verdure is provided \"as is\". To the fullest extent permitted by law we disclaim warranties of any kind and are not liable for indirect, incidental or consequential damages, or for any loss arising from events, places or people you encounter through the app. Nothing here limits rights you have under consumer law that cannot be excluded."),
        Section(title: "Changes",
                body: "We may update these Terms. If a change is material we will tell you in the app before it takes effect, and continuing to use Verdure afterwards means you accept it. The date at the top is the current version."),
        Section(title: "Contact",
                body: "Verdure — \(Legal.contactEmail). Support: \(Legal.siteBase)/support."),
    ]

    // MARK: - Privacy Policy (mirrors the website; both change together)

    static let privacySections: [Section] = [
        Section(title: "The short version",
                body: "We collect your account details, your location when you check in, and the photos you choose to attach as proof of attendance. We use them to run the app — points, collections, rewards and events. Nothing is sold and nothing is used to target you across other apps or websites. Verdure does show offers from local partners, always labelled; partners are never given your personal information, and a partner offer never changes the order of what we recommend."),
        Section(title: "What we collect",
                body: "Account: your email address, display name, and birth year to apply age safeguards (passwords are handled by Firebase Authentication and never stored by us). If you choose to identify as a student, we store that status and any school you provide to recommend relevant activities. You can optionally save the youngest child's age in your household for family event recommendations and warnings. Location: with your permission, your precise location to show what's nearby, to check you're close enough to collect a place, and to verify event check-ins; the coordinates at check-in are kept as an attendance record. Photos: only the images you explicitly pick as proof of attendance. Posts, events and RSVPs you create are shown to other users with your display name. Private group plans, invitations and shortlist votes are visible to accepted friends in that plan. Subscription status, so member benefits unlock; Apple handles payment and we never see card details. Game state: points, places, events, streak and badges. Interests, saved events, viewed events, your more/less feedback, and ranked-feed impressions and actions are stored with your account to order and evaluate recommendations."),
        Section(title: "What we do not do",
                body: "No tracking across other apps or websites, and no third-party advertising or analytics SDKs. No selling or sharing your personal information with data brokers. No background location — it is read only while you use the app. No contacts, health or browsing data. We keep first-party app-use analytics tied to a random per-install identifier, with no names, post content or precise location in those records. When enabled, ranked-feed impressions and actions are linked to your account so we can evaluate recommendations; they include event IDs, position and score signals. Switch off Product Analytics in Profile › Settings to stop both kinds of new analytics records."),
        Section(title: "Who processes data for us",
                body: "Google Firebase (Authentication, Firestore, Cloud Functions, Cloud Storage) runs accounts, game state and proof photos. Apple processes subscription payments. Gift cards are delivered by our fulfilment partner using the email on your account. Local partners whose offers you redeem receive only the fact that a code was claimed — never your name, email, location or activity. Public place and event information comes from open sources such as OpenStreetMap, the National Park Service, public library and civic calendars and ticketing feeds — those are content lookups; your personal data is not sent to them."),
        Section(title: "How long we keep it",
                body: "Account and game data is kept while your account exists. Attendance records and proof photos are kept while they may need to be verified and are deleted with the account. Deleting your account in Profile › Settings removes everything above immediately; records of gift cards already delivered are kept in anonymised form for accounting."),
        Section(title: "Your choices and rights",
                body: "Grant or revoke location in iOS Settings › Privacy & Security › Location Services › Verdure. Turn notifications off in the app or in iOS Settings. Delete your account from Profile › Settings. Depending on where you live (for example the EEA/UK under GDPR or California under the CCPA) you may have additional rights to access, correct, port or delete your information; we honour these requests wherever you are — email \(Legal.contactEmail)."),
        Section(title: "Children",
                body: "Verdure is not directed to children under 13 and we don't knowingly collect their information. If you believe a child has created an account, contact us and we will remove it."),
        Section(title: "Security",
                body: "Data travels over encrypted connections and is stored behind access rules that restrict each account to its own data. Points, check-ins, redemptions and moderation decisions are validated on our servers rather than trusted from the app."),
        Section(title: "Changes",
                body: "If we change how we handle data we will update this policy and its date, and surface material changes in the app."),
    ]
}
