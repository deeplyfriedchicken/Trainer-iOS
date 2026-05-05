import SwiftUI

struct ClientsView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var selectedClient: Client? = nil
    @State private var showAdd = false
    @State private var showEdit: Client? = nil
    @State private var showDelete: Client? = nil

    private var filtered: [Client] {
        guard !search.isEmpty else { return store.clients }
        return store.clients.filter {
            $0.fullName.localizedCaseInsensitiveContains(search) ||
            $0.plan.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            if let client = selectedClient {
                ClientDetailView(client: binding(for: client), onBack: { selectedClient = nil })
                    .id(client.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
            } else {
                listView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedClient?.id)
        .sheet(isPresented: $showAdd) {
            ClientFormSheet(mode: .add)
        }
        .sheet(item: $showEdit) { client in
            ClientFormSheet(mode: .edit(client))
        }
        .sheet(item: $showDelete) { client in
            DeleteConfirmSheet(name: client.fullName) {
                showDelete = nil
                store.deleteClient(id: client.id)
            } onCancel: { showDelete = nil }
        }
    }

    private var floatingButtons: some View {
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

    private var listView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clients")
                            .font(.display(28))
                            .foregroundStyle(.white)
                        Text("\(store.clients.count) total · \(store.clients.filter { $0.status == .active }.count) active")
                            .font(.mono(12))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    Spacer()
                    PillButton(title: "Add", icon: "plus", style: .primary) { showAdd = true }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.3))
                    TextField("Search clients…", text: $search)
                        .font(.body(14))
                        .foregroundStyle(.white)
                        .tint(.neonPink)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            List {
                ForEach(filtered) { client in
                    ClientRow(client: client, onTap: { withAnimation { selectedClient = client } })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { showDelete = client } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { showEdit = client } label: {
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
        .overlay(alignment: .bottomTrailing) { floatingButtons }
    }

    private func binding(for client: Client) -> Binding<Client> {
        let s = store
        return Binding(
            get: { s.clients.first(where: { $0.id == client.id }) ?? client },
            set: { updated in
                if let i = s.clients.firstIndex(where: { $0.id == updated.id }) {
                    s.clients[i] = updated
                }
            }
        )
    }
}

// MARK: - Client Row

struct ClientRow: View {
    let client: Client
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                AvatarView(initials: client.initials, colorIndex: client.colorIndex)

                VStack(alignment: .leading, spacing: 2) {
                    Text(client.fullName)
                        .font(.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(client.plan)
                        .font(.body(12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Client Form Sheet

enum ClientFormMode {
    case add
    case edit(Client)
}

struct ClientFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: ClientFormMode

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var status: ClientStatus = .active

    init(mode: ClientFormMode) {
        self.mode = mode
        if case .edit(let c) = mode {
            _firstName = State(initialValue: c.firstName)
            _lastName  = State(initialValue: c.lastName)
            _email     = State(initialValue: c.email)
            _status    = State(initialValue: c.status)
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

                        FormField(label: "Email", text: $email, placeholder: "client@example.com")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Status")
                                .font(.mono(11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .textCase(.uppercase)
                                .tracking(0.8)
                            Picker("Status", selection: $status) {
                                ForEach(ClientStatus.allCases, id: \.self) { s in
                                    Text(s.rawValue.capitalized).tag(s)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 20)

                        HStack(spacing: 10) {
                            PillButton(title: "Cancel", style: .secondary, fullWidth: true) { dismiss() }
                            PillButton(title: isAdd ? "Add Client" : "Save Changes", style: .primary, fullWidth: true) { save() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isAdd ? "New Client" : "Edit Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var isAdd: Bool { if case .add = mode { return true }; return false }

    private func save() {
        if case .add = mode {
            let client = Client(
                firstName: firstName, lastName: lastName, email: email,
                plan: "Training",
                sessions: 0, lastSeen: "New", status: status,
                trainerId: nil, colorIndex: store.clients.count % 5,
                videos: [], workouts: [], workoutPlans: []
            )
            store.addClient(client)
        } else if case .edit(let original) = mode {
            var updated = original
            updated.firstName = firstName; updated.lastName = lastName
            updated.email = email
            updated.status = status
            store.updateClient(updated)
        }
        dismiss()
    }
}

// MARK: - Delete Confirm Sheet

struct DeleteConfirmSheet: View {
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

                Text("Remove Client?")
                    .font(.display(22))
                    .foregroundStyle(.white)

                Text("\(name) will be permanently removed from your roster.")
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    PillButton(title: "Cancel", style: .secondary, fullWidth: true, action: onCancel)
                    PillButton(title: "Delete", style: .danger, fullWidth: true, action: onDelete)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
        .presentationDetents([.height(280)])
        .presentationBackground(Color(hex: "0c0c1c"))
    }
}
