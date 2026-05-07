import SwiftUI

struct MainDockView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var selectedTab: Tab = .reminders
    @State private var showAddMenu = false
    @State private var showNewPlanFlow = false
    @State private var showPlanPicker = false
    @State private var appendTargetPlanId: UUID?

    private enum Tab {
        case reminders
        case user
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .reminders:
                    HomeView()
                case .user:
                    UserCenterView()
                }
            }

            if showAddMenu {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            showAddMenu = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(4)

                addOptionMenu
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            bottomDock
                .zIndex(6)
        }
        .sheet(isPresented: $showNewPlanFlow) {
            AddPrescriptionFlowView(targetPlanId: nil)
                .environmentObject(appStore)
        }
        .sheet(isPresented: $showPlanPicker) {
            PlanSelectionSheetView(
                plans: appStore.plans,
                onCreateNew: {
                    showPlanPicker = false
                    showNewPlanFlow = true
                },
                onSelectPlan: { planId in
                    showPlanPicker = false
                    appendTargetPlanId = planId
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { appendTargetPlanId != nil },
                set: { presenting in
                    if !presenting {
                        appendTargetPlanId = nil
                    }
                }
            )
        ) {
            if let appendTargetPlanId {
                AddPrescriptionFlowView(targetPlanId: appendTargetPlanId)
                    .environmentObject(appStore)
            }
        }
    }

    private var addOptionMenu: some View {
        VStack {
            Spacer()
            HStack(spacing: 18) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showAddMenu = false
                    }
                    showNewPlanFlow = true
                } label: {
                    Label("Add New Plan", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock.add.option.newPlan")

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showAddMenu = false
                    }
                    showPlanPicker = true
                } label: {
                    Label("Add Prescription", systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock.add.option.addPrescription")
            }
            .padding(.bottom, 108)
            .padding(.horizontal, 24)
            .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity), removal: .opacity))
        }
    }

    private var bottomDock: some View {
        ZStack(alignment: .bottom) {
            HStack {
                dockTabButton(
                    title: "Reminders",
                    systemImage: "list.bullet.clipboard",
                    selected: selectedTab == .reminders
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        selectedTab = .reminders
                    }
                }

                Spacer(minLength: 80)

                dockTabButton(
                    title: "User",
                    systemImage: "person.crop.circle",
                    selected: selectedTab == .user
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        selectedTab = .user
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 2)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    showAddMenu.toggle()
                }
            } label: {
                Image(systemName: showAddMenu ? "xmark" : "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 10, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .offset(y: -28)
            .accessibilityIdentifier("dock.add.button")
        }
    }

    private func dockTabButton(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct PlanSelectionSheetView: View {
    let plans: [MedicationPlan]
    var onCreateNew: () -> Void
    var onSelectPlan: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("No current plan")
                            .font(.headline)
                        Text("Create a new plan first, then you can add more prescriptions to it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        Button("Create New Plan Instead") {
                            dismiss()
                            onCreateNew()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(plans) { plan in
                                Button {
                                    dismiss()
                                    onSelectPlan(plan.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(DateTimeUtils.formatDisplayDate(plan.createdAt))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("\(plan.medications.count) medication(s) • \(plan.followUp.count) follow-up")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Choose Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
