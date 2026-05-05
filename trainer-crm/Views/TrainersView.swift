import SwiftUI

struct TrainersView: View {
    @Environment(AppStore.self) private var store
    @State private var showAdd = false
    @State private var showEdit: Trainer? = nil
    @State private var showDelete: Trainer? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trainers")
                        .font(.display(28))
                        .foregroundStyle(.white)
                    Text("\(store.trainers.count) staff members")
                        .font(.mono(12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                PillButton(title: "Add", icon: "plus", style: .cyan) { showAdd = true }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            List {
                ForEach(store.trainers) { trainer in
                    TrainerCard(trainer: trainer, clientCount: store.clientCount(for: trainer.id))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { showDelete = trainer } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { showEdit = trainer } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.neonCyan)
                        }
                }
                .padding(.bottom, 16)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.refreshData() }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { store.signOut() } label: {
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
        .sheet(isPresented: $showAdd) {
            TrainerFormSheet(mode: .add)
        }
        .sheet(item: $showEdit) { trainer in
            TrainerFormSheet(mode: .edit(trainer))
        }
        .sheet(item: $showDelete) { trainer in
            DeleteTrainerSheet(name: trainer.fullName) {
                showDelete = nil
                store.deleteTrainer(id: trainer.id)
            } onCancel: { showDelete = nil }
        }
    }
}

// MARK: - Trainer Card

struct TrainerCard: View {
    let trainer: Trainer
    let clientCount: Int

    private var roleColor: Color { trainer.role == .trainerManager ? .neonPink : trainer.role == .admin ? .neonGreen : .neonCyan }

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(initials: trainer.initials, colorIndex: trainer.colorIndex, size: 56, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 6) {
                Text(trainer.fullName)
                    .font(.body(15, weight: .bold))
                    .foregroundStyle(.white)
                TagChip(label: trainer.role.displayName, color: roleColor)
            }

            Spacer()

            HStack(spacing: 14) {
                VStack(spacing: 1) {
                    Text("\(clientCount)")
                        .font(.display(18))
                        .foregroundStyle(.white)
                    Text("Clients")
                        .font(.mono(9))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                VStack(spacing: 1) {
                    Text("\(trainer.sessions)")
                        .font(.display(18))
                        .foregroundStyle(.white)
                    Text("Sessions")
                        .font(.mono(9))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Trainer Form Sheet

enum TrainerFormMode { case add; case edit(Trainer) }

extension TrainerFormMode: Identifiable {
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let t): return t.id
        }
    }
}

struct TrainerFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: TrainerFormMode

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var role: TrainerRole = .trainer

    init(mode: TrainerFormMode) {
        self.mode = mode
        if case .edit(let t) = mode {
            _firstName      = State(initialValue: t.firstName)
            _lastName       = State(initialValue: t.lastName)
            _email          = State(initialValue: t.email)
            _role           = State(initialValue: t.role)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            FormField(label: "First Name", text: $firstName, placeholder: "First")
                                .frame(maxWidth: .infinity)
                            FormField(label: "Last Name", text: $lastName, placeholder: "Last")
                                .frame(maxWidth: .infinity)
                        }

                        FormField(label: "Email", text: $email, placeholder: "trainer@example.com")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Role")
                                .font(.mono(11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .textCase(.uppercase)
                                .tracking(0.8)
                            Picker("Role", selection: $role) {
                                ForEach(TrainerRole.allCases.filter { $0 != .admin }, id: \.self) { r in
                                    Text(r.displayName).tag(r)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.neonCyan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        HStack(spacing: 10) {
                            PillButton(title: "Cancel", style: .secondary, fullWidth: true) { dismiss() }
                            PillButton(title: isAdd ? "Add Trainer" : "Save Changes", style: .cyan, fullWidth: true) { save() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isAdd ? "New Trainer" : "Edit Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var isAdd: Bool { if case .add = mode { return true }; return false }

    private func save() {
        if case .add = mode {
            store.addTrainer(Trainer(
                firstName: firstName, lastName: lastName, email: email,
                role: role,
                sessions: 0,
                colorIndex: store.trainers.count % 5
            ))
        } else if case .edit(let original) = mode {
            var t = original
            t.firstName = firstName; t.lastName = lastName
            t.email = email
            t.role = role
            store.updateTrainer(t)
        }
        dismiss()
    }
}

// MARK: - Delete Trainer Sheet

struct DeleteTrainerSheet: View {
    let name: String
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

                Text("Remove Trainer?")
                    .font(.display(22))
                    .foregroundStyle(.white)

                Text("\(name) will be removed from the team.")
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    PillButton(title: "Cancel", style: .secondary, fullWidth: true, action: onCancel)
                    PillButton(title: "Delete", style: .danger, fullWidth: true, action: onDelete)
                }
                .padding(.horizontal, 20).padding(.top, 4)
            }
        }
        .presentationDetents([.height(280)])
        .presentationBackground(Color(hex: "0c0c1c"))
    }
}
