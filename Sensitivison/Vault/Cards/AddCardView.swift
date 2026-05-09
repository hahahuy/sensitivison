import SwiftUI
import SwiftData

struct AddCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cryptoVault: CryptoVault

    @State private var number = ""
    @State private var expiry = ""
    @State private var cvv = ""
    @State private var holder = ""
    @State private var pin = ""
    @State private var cardType = "visa"

    private var canSave: Bool { !number.isEmpty && !expiry.isEmpty && !cvv.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Details") {
                    TextField("Card Number", text: $number)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Card number")
                    TextField("Expiry MM/YY", text: $expiry)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Expiry date")
                    SecureField("CVV", text: $cvv)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("CVV, secure field")
                }
                Section("Personal") {
                    TextField("Cardholder Name", text: $holder)
                        .textInputAutocapitalization(.characters)
                        .accessibilityLabel("Cardholder name")
                    SecureField("PIN (optional)", text: $pin)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("PIN, secure field")
                }
                Section("Card Type") {
                    Picker("Type", selection: $cardType) {
                        Text("Visa").tag("visa")
                        Text("Mastercard").tag("mastercard")
                        Text("Other").tag("other")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        guard let encNumber = try? cryptoVault.encryptString(number),
              let encCVV = try? cryptoVault.encryptString(cvv),
              let encPIN = try? cryptoVault.encryptString(pin.isEmpty ? "" : pin),
              let encHolder = try? cryptoVault.encryptString(holder),
              let encExpiry = try? cryptoVault.encryptString(expiry) else { return }
        let card = VaultCard(encryptedNumber: encNumber, encryptedCVV: encCVV,
                             encryptedPIN: encPIN, encryptedHolder: encHolder,
                             encryptedExpiry: encExpiry, cardType: cardType)
        modelContext.insert(card)
        dismiss()
    }
}
