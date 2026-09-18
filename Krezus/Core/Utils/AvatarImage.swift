import UIKit

/// Préparation d'une photo avant envoi : carré centré, 512 px, JPEG.
///
/// Une photo d'iPhone pèse plusieurs mégaoctets pour une pastille qui n'en
/// affiche jamais plus de 72 points. Réduite ainsi, elle tombe autour de
/// 60 Ko — sous la borne d'un mégaoctet que pose le bucket.
enum AvatarImage {
    static let side: CGFloat = 512
    static let quality: CGFloat = 0.82

    static func prepare(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        // Carré inscrit, centré : le visage est presque toujours au milieu.
        let edge = min(size.width, size.height)
        let scale = side / edge
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        // `draw(in:)` applique l'orientation EXIF : une photo prise en
        // portrait ne ressort pas couchée.
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

/// Copie locale de la photo, pour ne pas la retélécharger à chaque lancement.
/// Dans le dossier Caches : iOS peut le vider, la photo sera alors
/// simplement retéléchargée.
enum AvatarCache {
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatars", isDirectory: true)
    }

    private static func prefix(_ userID: UUID) -> String { "avatar-\(userID.uuidString.lowercased())-" }

    private static func url(userID: UUID, version: Date) -> URL {
        directory.appendingPathComponent("\(prefix(userID))\(Int(version.timeIntervalSince1970)).jpg")
    }

    static func load(userID: UUID, version: Date) -> UIImage? {
        UIImage(contentsOfFile: url(userID: userID, version: version).path)
    }

    /// Remplace toute version précédente.
    static func store(_ data: Data, userID: UUID, version: Date) {
        clear(userID: userID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(userID: userID, version: version), options: .atomic)
    }

    static func clear(userID: UUID) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files where name.hasPrefix(prefix(userID)) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: Mode démo — sans serveur, la photo n'existe que sur l'appareil.

    /// Application Support et non Caches : en démo, il n'y a pas d'autre copie.
    private static var demoURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatar-demo.jpg")
    }

    static func loadDemo() -> UIImage? { UIImage(contentsOfFile: demoURL.path) }

    static func storeDemo(_ data: Data) {
        try? FileManager.default.createDirectory(
            at: demoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: demoURL, options: .atomic)
    }

    static func clearDemo() { try? FileManager.default.removeItem(at: demoURL) }
}
