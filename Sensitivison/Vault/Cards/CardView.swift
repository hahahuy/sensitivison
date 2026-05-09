import SwiftUI
import UIKit

struct CardView: View {
    let card: VaultCard
    let vault: CryptoVault
    @State private var isFlipped = false
    @State private var pinVisible = false

    private var decryptedNumber: String { (try? vault.decryptString(card.encryptedNumber)) ?? "•••• •••• •••• ••••" }
    private var decryptedCVV: String { (try? vault.decryptString(card.encryptedCVV)) ?? "•••" }
    private var decryptedPIN: String { (try? vault.decryptString(card.encryptedPIN)) ?? "••••" }
    private var decryptedHolder: String { (try? vault.decryptString(card.encryptedHolder)) ?? "" }
    private var decryptedExpiry: String { (try? vault.decryptString(card.encryptedExpiry)) ?? "" }
    private var last4: String { String(decryptedNumber.filter(\.isNumber).suffix(4)) }

    private var cardGradient: LinearGradient {
        switch card.cardType {
        case "visa": return LinearGradient(colors: [.blue, Color(red: 0.05, green: 0.28, blue: 0.63)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "mastercard": return LinearGradient(colors: [Color(red: 0.5, green: 0.1, blue: 0.1), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        ZStack {
            frontFace.opacity(isFlipped ? 0 : 1)
            backFace.opacity(isFlipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (0, 1, 0))
        .animation(.easeInOut(duration: 0.4), value: isFlipped)
        .onTapGesture { isFlipped.toggle() }
        .accessibilityLabel("Card ending \(last4), expires \(decryptedExpiry)")
        .accessibilityHint(isFlipped ? "Tap to hide details" : "Tap to reveal full card details")
    }

    private var frontFace: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(cardGradient)
            .frame(height: 200)
            .overlay(
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(card.cardType.capitalized).font(.caption).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                    Spacer()
                    Text("•••• •••• •••• \(last4)").font(.title3.monospaced()).foregroundStyle(.white)
                    HStack {
                        Text(decryptedHolder).font(.caption).foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text(decryptedExpiry).font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    Text("Tap to reveal").font(.caption2).foregroundStyle(.white.opacity(0.5))
                }.padding(20)
            )
    }

    private var backFace: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(cardGradient)
            .frame(height: 200)
            .overlay(
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Card Number").font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Text(decryptedNumber).font(.subheadline.monospaced()).foregroundStyle(.white)
                        }
                        Spacer()
                        CopyButton(value: decryptedNumber, label: "card number")
                    }
                    HStack(spacing: 24) {
                        VStack(alignment: .leading) {
                            Text("CVV").font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Text(decryptedCVV).font(.subheadline.monospaced()).foregroundStyle(.white)
                        }
                        CopyButton(value: decryptedCVV, label: "CVV")
                        VStack(alignment: .leading) {
                            Text("PIN").font(.caption2).foregroundStyle(.white.opacity(0.6))
                            Button(action: { pinVisible.toggle() }) {
                                Text(pinVisible ? decryptedPIN : String(repeating: "•", count: decryptedPIN.count))
                                    .font(.subheadline.monospaced()).foregroundStyle(.white)
                            }
                        }
                        CopyButton(value: decryptedPIN, label: "PIN")
                    }
                    Spacer()
                    Text("Tap to hide").font(.caption2).foregroundStyle(.white.opacity(0.5))
                }.padding(20)
            )
    }
}

private struct CopyButton: View {
    let value: String
    let label: String
    @State private var copied = false
    var body: some View {
        Button(action: {
            UIPasteboard.general.string = value
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityLabel("Copy \(label)")
    }
}
