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
                    TrainerCard(trainer: trainer)
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
            SignOutButton { store.signOut() }
        }
        .sheet(isPresented: $showAdd) {
            TrainerFormSheet(mode: .add)
        }
        .sheet(item: $showEdit) { trainer in
            TrainerFormSheet(mode: .edit(trainer))
        }
        .sheet(item: $showDelete) { trainer in
            DeleteConfirmSheet(
                title: "Remove Trainer?",
                message: "\(trainer.fullName) will be removed from the team."
            ) {
                showDelete = nil
                store.deleteTrainer(id: trainer.id)
            } onCancel: { showDelete = nil }
        }
    }
}

// MARK: - Trainer Card

struct TrainerCard: View {
    let trainer: Trainer

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
        DarkSheet(title: isAdd ? "New Trainer" : "Edit Trainer") {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    FormField(label: "First Name", text: $firstName, placeholder: "First", clearable: true)
                        .frame(maxWidth: .infinity)
                    FormField(label: "Last Name", text: $lastName, placeholder: "Last", clearable: true)
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

