import SwiftUI

struct CommunityView: View {
    @State private var newPostText = ""
    @State private var showNewPost = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    // Compose prompt
                    composePrompt

                    // Community posts
                    LazyVStack(spacing: 12) {
                        ForEach(SampleData.communityPosts) { post in
                            PostCard(post: post)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Community")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewPost = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .tint(Color.connectifyGreen)
                }
            }
            .sheet(isPresented: $showNewPost) {
                newPostSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Compose Prompt

    private var composePrompt: some View {
        Button { showNewPost = true } label: {
            HStack(spacing: Spacing.md) {
                AvatarCircle(initials: "ME", size: 36)

                Text("Share a discovery...")
                    .font(CFont.body(15))
                    .foregroundStyle(.tertiaryText)

                Spacer()

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondaryText)
            }
            .padding(Spacing.md)
            .background(.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(.subtleBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - New Post Sheet

    private var newPostSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    AvatarCircle(initials: "ME", size: 40)

                    TextField("What did you discover today?", text: $newPostText, axis: .vertical)
                        .font(CFont.body(16))
                        .lineLimit(5...10)
                }
                .padding(.horizontal, Spacing.md)

                Divider()

                // Attachment options
                HStack(spacing: Spacing.lg) {
                    attachmentButton(icon: "photo.fill", label: "Photo")
                    attachmentButton(icon: "mappin", label: "Location")
                    attachmentButton(icon: "face.smiling", label: "Feeling")
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)

                Spacer()
            }
            .padding(.top, Spacing.md)
            .background(.pageSurface)
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showNewPost = false }
                        .foregroundStyle(.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        // Placeholder
                        showNewPost = false
                    }
                    .font(CFont.headline(15))
                    .foregroundStyle(newPostText.isEmpty ? .tertiaryText : Color.connectifyGreen)
                    .disabled(newPostText.isEmpty)
                }
            }
        }
    }

    private func attachmentButton(icon: String, label: String) -> some View {
        Button {
            // Placeholder
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(CFont.caption(11))
            }
            .foregroundStyle(.secondaryText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post Card

private struct PostCard: View {
    let post: CommunityPost
    @State private var isLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Author header
            HStack(spacing: Spacing.sm) {
                AvatarCircle(initials: post.authorInitials, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(CFont.headline(14))
                        .foregroundStyle(.primaryText)

                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                        Text(post.placeName)
                            .font(CFont.caption(12))
                    }
                    .foregroundStyle(.secondaryText)
                }

                Spacer()

                Text(post.timeAgo)
                    .font(CFont.caption(12))
                    .foregroundStyle(.tertiaryText)
            }

            // Content
            Text(post.content)
                .font(CFont.body(15))
                .foregroundStyle(.primaryText)
                .lineSpacing(3)

            // Image placeholder
            if post.imagePlaceholder != nil {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(
                        LinearGradient(
                            colors: [Color.connectifyGreen.opacity(0.12), Color.accentSky.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiaryText)
                    }
            }

            // Actions
            HStack(spacing: Spacing.xl) {
                actionButton(
                    icon: isLiked ? "heart.fill" : "heart",
                    count: post.likeCount + (isLiked ? 1 : 0),
                    tint: isLiked ? .accentCoral : nil
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        isLiked.toggle()
                    }
                }

                actionButton(icon: "bubble.right", count: post.commentCount) {
                    // Placeholder
                }

                actionButton(icon: "arrow.turn.up.right", count: nil) {
                    // Placeholder
                }

                Spacer()

                Button {
                    // Placeholder: bookmark
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }

    private func actionButton(icon: String, count: Int?, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                if let count {
                    Text("\(count)")
                        .font(CFont.caption(12))
                }
            }
            .foregroundStyle(tint ?? .secondaryText)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CommunityView()
}
