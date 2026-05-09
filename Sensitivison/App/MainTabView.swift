import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PhotosView()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            DocumentsView()
                .tabItem { Label("Documents", systemImage: "doc.fill") }
            NotesView()
                .tabItem { Label("Notes", systemImage: "note.text") }
            CardsView()
                .tabItem { Label("Cards", systemImage: "creditcard.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
