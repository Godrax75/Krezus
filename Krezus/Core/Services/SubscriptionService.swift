import Foundation
import StoreKit

/// Abonnement Hercule Premium, via StoreKit 2.
///
/// La guideline 3.1.1 de l'App Store impose l'achat intégré pour débloquer du
/// contenu dans l'app : aucun paiement web, aucun lien sortant vers une page
/// de paiement. C'est aussi StoreKit qui porte la restauration d'achat, la
/// gestion familiale et les remboursements — les réimplémenter serait à la
/// fois interdit et pire.
@MainActor
@Observable
final class SubscriptionService {

    static let productID = "com.krezus.hercule.monthly"

    private(set) var product: Product?
    private(set) var isSubscribed = false
    private(set) var isPurchasing = false
    private(set) var loadError: String?

    /// Prix localisé par l'App Store ; repli sur le tarif du plan tant que le
    /// produit n'est pas chargé (App Store Connect non configuré, hors ligne).
    var displayPrice: String { product?.displayPrice ?? HerculeStore.subscriptionPrice }

    /// Vrai quand StoreKit n'a pas pu charger le produit — l'achat est alors
    /// impossible et l'écran doit le dire plutôt que d'afficher un bouton mort.
    var isUnavailable: Bool { product == nil }

    /// `nonisolated(unsafe)` parce que `deinit` ne s'exécute pas sur l'acteur
    /// principal et ne peut donc pas lire une propriété isolée. L'annulation
    /// d'une `Task` est sûre depuis n'importe quel contexte, d'où le `unsafe`
    /// assumé.
    ///
    /// `@ObservationIgnored` n'est pas cosmétique : sans lui, la macro
    /// `@Observable` transforme le stockage en propriété calculée, l'attribut
    /// d'isolation ne porte plus sur rien — le compilateur le signale — et une
    /// poignée de `Task` se retrouverait suivie comme un état d'interface.
    @ObservationIgnored
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init() {
        // Les transactions peuvent arriver hors du flux d'achat : renouvellement,
        // achat sur un autre appareil, remboursement. Sans cet écouteur,
        // l'abonnement ne se met à jour qu'au prochain lancement.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            loadError = products.isEmpty ? t("storekit.error.product_missing") : nil
        } catch {
            loadError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    enum PurchaseOutcome { case success, cancelled, pending, unavailable, failed(String) }

    @discardableResult
    func purchase() async -> PurchaseOutcome {
        guard let product else { return .unavailable }
        guard !isPurchasing else { return .pending }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                // `.verified` porte la vérification cryptographique faite par
                // StoreKit. Accepter un `.unverified` reviendrait à offrir
                // l'abonnement à qui sait forger un reçu.
                guard case .verified(let transaction) = verification else {
                    return .failed(t("storekit.error.unverified"))
                }
                await transaction.finish()
                await refreshEntitlement()
                return .success

            case .userCancelled:
                return .cancelled
            case .pending:
                // « Demander à acheter » : l'achat attend l'accord d'un parent.
                return .pending
            @unknown default:
                return .failed(t("storekit.error.unexpected"))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Restauration explicite. StoreKit synchronise seul dans la plupart des
    /// cas, mais l'App Store exige un bouton de restauration visible.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    /// Recalcule le droit d'accès à partir des transactions en cours.
    func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.productID == Self.productID else { continue }

            // `revocationDate` couvre le remboursement : l'accès doit tomber.
            if transaction.revocationDate == nil {
                isSubscribed = true
                return
            }
        }
        isSubscribed = false
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await transaction.finish()
        await refreshEntitlement()
    }
}
