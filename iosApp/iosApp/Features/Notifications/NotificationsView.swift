import SwiftUI

// MARK: - NotificationsView

struct NotificationsView: View {

    @ObservedObject var viewModel: NotificationsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = viewModel.error {
                    errorState(message: error)
                } else if viewModel.notifications.isEmpty {
                    emptyState
                } else {
                    notificationList
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") {
                            viewModel.markAllRead()
                        }
                        .font(AppTypography.caption1)
                    }
                }
            }
            // Surface mark-read action errors as an alert
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.actionError != nil },
                    set: { if !$0 { viewModel.dismissActionError() } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.dismissActionError() }
            } message: {
                Text(viewModel.actionError ?? "")
            }
        }
        .onAppear { viewModel.loadNotifications() }
    }

    // MARK: - List

    private var notificationList: some View {
        List(viewModel.notifications) { item in
            NotificationRow(item: item) {
                if !item.isRead { viewModel.markRead(item.id) }
            }
            .listRowBackground(
                item.isRead
                    ? AppColors.backgroundSecondary
                    : AppColors.primary.opacity(0.06)
            )
        }
        .listStyle(.plain)
        .refreshable { viewModel.loadNotifications() }
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text("No notifications")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Friend requests and acceptances will appear here.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { viewModel.loadNotifications() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - NotificationRow

private struct NotificationRow: View {

    let item: NotificationDisplayItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                // Unread indicator dot
                Circle()
                    .fill(item.isRead ? Color.clear : AppColors.primary)
                    .frame(width: 8, height: 8)

                // Type icon
                Image(systemName: item.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(item.isRead ? AppColors.textSecondary : AppColors.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        (item.isRead ? AppColors.textSecondary : AppColors.primary).opacity(0.1),
                        in: Circle()
                    )

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(item.isRead ? AppTypography.body : AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(item.body)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NotificationBannerOverlay

/// In-app banner shown at the top of the screen when a new notification arrives.
/// Slides in from the top and auto-dismisses after 4 seconds.
///
/// The auto-dismiss task is stored so it can be cancelled if the user
/// manually dismisses the banner first, preventing a double-dismiss.
struct NotificationBannerOverlay: View {

    let item: NotificationDisplayItem
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var autoDismissTask: Task<Void, Never>? = nil

    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: item.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(item.body)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.primary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.4)) { isVisible = true }
            scheduleAutoDismiss()
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }

    // MARK: - Private

    private func dismiss() {
        autoDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) { isVisible = false }
        // Allow the slide-out animation to complete before removing from hierarchy.
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            onDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
