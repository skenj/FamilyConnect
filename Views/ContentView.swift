import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: String = "home"
    @State private var showingImportedRecipe = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadRoot
            } else {
                iPhoneRoot
            }
        }
        .task {
            await cloudKitService.bootstrap()
        }
        .onChange(of: cloudKitService.pendingRecipeURL) { _, url in
            guard url != nil else { return }
            selectedTab = "meals"
            showingImportedRecipe = true
        }
        .sheet(isPresented: $showingImportedRecipe, onDismiss: {
            cloudKitService.pendingRecipeURL = nil
        }) {
            ImportRecipeSheet(initialURL: cloudKitService.pendingRecipeURL ?? "")
                .environmentObject(cloudKitService)
        }
        .overlay(alignment: .top) {
            if let error = cloudKitService.error {
                ErrorBanner(message: error) { cloudKitService.error = nil }
                    .padding()
            }
        }
    }

    private var iPhoneRoot: some View {
        TabView(selection: $selectedTab) {
            // Home
            HomeView(onNavigateToChat: { selectedTab = "chat" })
                .tabItem { Label("Home", systemImage: "house") }
                .tag("home")

            // Calendar
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag("calendar")

            // Chat
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag("chat")

            // Meals
            MealsView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag("meals")

            // Family (replaces More)
            FamilyTabView()
                .tabItem { Label("Family", systemImage: "person.3") }
                .tag("family")
        }
    }

    private var iPadRoot: some View {
        NavigationSplitView {
            List {
                sidebarButton("home",     title: "Home",     systemImage: "house")
                sidebarButton("calendar", title: "Calendar", systemImage: "calendar")
                sidebarButton("chat",     title: "Chat",     systemImage: "bubble.left.and.bubble.right")
                sidebarButton("meals",    title: "Meals",    systemImage: "fork.knife")
                sidebarButton("family",   title: "Family",   systemImage: "person.3")
            }
            .navigationTitle("FamilyConnect")
        } detail: {
            detailView
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case "home":     HomeView(onNavigateToChat: { selectedTab = "chat" })
        case "calendar": CalendarView()
        case "chat":     ChatView()
        case "meals":    MealsView()
        case "family":   FamilyTabView()
        default:         HomeView(onNavigateToChat: { selectedTab = "chat" })
        }
    }

    private func sidebarButton(_ id: String, title: String, systemImage: String) -> some View {
        Button { selectedTab = id } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(selectedTab == id ? Color.accentColor : Color.primary)
        }
    }
}

// MARK: - Family Tab (replaces More)
// Contains Family, Location, and a discrete Settings cog in the toolbar
struct FamilyTabView: View {
    @State private var showSettings = false
    @State private var selectedSection: FamilySection = .members

    enum FamilySection: String, CaseIterable {
        case members = "Members"
        case location = "Location"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(FamilySection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                switch selectedSection {
                case .members:
                    FamilyView()
                case .location:
                    LocationView()
                }
            }
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Discrete settings cog top right
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.leading)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
        }
        .padding()
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.primary)
    }
}
