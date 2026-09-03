import UIKit

enum WhyPhotoStore {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("why-photo.jpg")
    }

    static func load() -> UIImage? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ data: Data) throws {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82), let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: fileURL, options: .atomic)
    }

    static func remove() throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
