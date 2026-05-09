import SwiftUI
import SwiftData

struct CardsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cryptoVault: CryptoVault
    @Query private var cards: [VaultCard]
    @State private var isAddingCard = false

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView("No cards yet",
                        systemImage: "creditcard.fill",
                        description: Text("Tap + to add a card"))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(cards) { card in
                                CardView(card: card, vault: cryptoVault)
                                    .swipeActions { Button("Delete", role: .destructive) { modelContext.delete(card) } }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Cards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { isAddingCard = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add card")
                }
            }
            .sheet(isPresented: $isAddingCard) { AddCardView() }
        }
    }
}
