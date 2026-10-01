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
            VStack(spacing: 8) {
                if let error = cloudKitService.error {
                    ErrorBanner(message: error) {
                        cloudKitService.error = nil
                    }
                }
            }
            .padding()
        }
    }

    private var iPhoneRoot: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag("home")
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag("calendar")
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag("chat")
            MealsView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag("meals")
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag("more")
        }
    }

    private var iPadRoot: some View {
        NavigationSplitView {
            List {
                sidebarButton("home", title: "Home", systemImage: "house")
                sidebarButton("calendar", title: "Calendar", systemImage: "calendar")
                sidebarButton("chat", title: "Chat", systemImage: "bubble.left.and.bubble.right")
                sidebarButton("meals", title: "Meals", systemImage: "fork.knife")
                sidebarButton("location", title: "Location", systemImage: "location")
                sidebarButton("family", title: "Family", systemImage: "person.3")
                sidebarButton("settings", title: "Settings", systemImage: "gear")
            }
            .navigationTitle("FamilyConnect")
        } detail: {
            detailView
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case "home": HomeView()
        case "calendar": CalendarView()
        case "chat": ChatView()
        case "meals": MealsView()
        case "location": LocationView()
        case "more": MoreView()
        case "settings": SettingsView()
        default: FamilyView()
        }
    }

    private func sidebarButton(_ id: String, title: String, systemImage: String) -> some View {
        Button {
            selectedTab = id
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(selectedTab == id ? Color.accentColor : Color.primary)
        }
    }
}

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Family") {
                    NavigationLink {
                        FamilyView()
                    } label: {
                        Label("My Family", systemImage: "person.3")
                    }
                    NavigationLink {
                        LocationView()
                    } label: {
                        Label("Location", systemImage: "location")
                    }
                }
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
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
