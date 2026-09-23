import Foundation

enum SensitiveFileProtection {
    static func protect(_ url: URL) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return
        }

        try? fm.setAttributes(
            [
                .protectionKey:
                    FileProtectionType.complete
            ],
            ofItemAtPath: url.path
        )

        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }

    static func protectRecursively(_ directory: URL) {
        let fm = FileManager.default

        protect(directory)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for case let url as URL in enumerator {
            protect(url)
        }
    }
}
