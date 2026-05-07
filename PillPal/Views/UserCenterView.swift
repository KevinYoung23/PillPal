import SwiftUI

struct UserCenterView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileCard
                    planSummaryCard
                    settingsButton
                }
                .padding(20)
            }
            .dockSafeContentInset()
            .navigationTitle("User Center")
        }
    }

    private var settingsButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack {
                Label("Settings", systemImage: "gearshape")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("PillPal User")
                    .font(.headline)
                Text("Manage plans, medications, and follow-ups")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var planSummaryCard: some View {
        HStack {
            NavigationLink {
                MyPlansListView()
            } label: {
                statItem(title: "Plans", value: "\(appStore.plans.count)")
            }
            .buttonStyle(.plain)
            Divider()
            NavigationLink {
                MedicationsListView()
            } label: {
                statItem(
                    title: "Medications",
                    value: "\(appStore.plans.reduce(0) { $0 + $1.medications.count })"
                )
            }
            .buttonStyle(.plain)
            Divider()
            NavigationLink {
                FollowUpsListView()
            } label: {
                statItem(
                    title: "Follow-up",
                    value: "\(appStore.plans.reduce(0) { $0 + $1.followUp.count })"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

}

private struct MyPlansListView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if appStore.plans.isEmpty {
                    Text("No plans yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appStore.plans) { plan in
                        NavigationLink {
                            MedicationDetailView(planId: plan.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(DateTimeUtils.formatDisplayDate(plan.createdAt))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(plan.medications.count) medication(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                NotificationService.shared.cancelNotifications(for: plan.id)
                                appStore.deletePlan(plan.id)
                            } label: {
                                Label("Delete Plan", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .dockSafeContentInset()
        .navigationTitle("My Plans")
    }
}

private struct FollowUpsListView: View {
    @EnvironmentObject private var appStore: AppStore

    private var followUps: [FollowUpItem] {
        appStore.plans
            .flatMap(\.followUp)
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if followUps.isEmpty {
                    Text("No follow-up items yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(followUps) { followUp in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DateTimeUtils.formatDisplayDate(followUp.date))
                                .font(.subheadline.weight(.semibold))
                            Text(followUp.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
        }
        .dockSafeContentInset()
        .navigationTitle("Follow-up")
    }
}
