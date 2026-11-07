import Foundation
import Security

public enum LocalCertificateError: Error, Equatable {
    case openSSLFailed(String)
    case importFailed(Int32)
}

/// A self-signed certificate for localhost / 127.0.0.1 / ::1, created once with the system's `openssl`
/// and reused. Browsers show a one-time warning for it (it is not issued by a trusted authority).
public enum LocalCertificate {
    private static let passphrase = "folderserve-local"
    private static let validDays = 825
    static let opensslPath = "/usr/bin/openssl"

    /// Loads the identity stored in `directory`, creating (or renewing) the certificate when needed.
    public static func identity(in directory: URL) throws -> SecIdentity {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let p12 = directory.appendingPathComponent("localhost.p12")
        if needsRenewal(p12) { try generate(into: directory, p12: p12) }
        return try load(p12)
    }

    /// The PEM certificate next to the identity (for "show me the certificate" / manual trust).
    public static func certificateURL(in directory: URL) -> URL { directory.appendingPathComponent("localhost.pem") }

    static func needsRenewal(_ p12: URL) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: p12.path))?[.modificationDate] as? Date else { return true }
        return Date().timeIntervalSince(modified) > Double(validDays - 60) * 86_400
    }

    static func load(_ p12: URL) throws -> SecIdentity {
        let data = try Data(contentsOf: p12)
        var items: CFArray?
        var options: [String: Any] = [kSecImportExportPassphrase as String: passphrase]
        if #available(macOS 15.0, *) { options[kSecImportToMemoryOnly as String] = true }   // earlier systems use the keychain
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let identity = first[kSecImportItemIdentity as String] else { throw LocalCertificateError.importFailed(status) }
        return identity as! SecIdentity   // swiftlint:disable:this force_cast
    }

    static func generate(into directory: URL, p12: URL) throws {
        let key = directory.appendingPathComponent("localhost.key")
        let pem = certificateURL(in: directory)
        let conf = directory.appendingPathComponent("openssl.cnf")
        try """
        [req]
        distinguished_name = dn
        x509_extensions = ext
        prompt = no
        [dn]
        CN = localhost
        O = FolderServe local development
        [ext]
        subjectAltName = DNS:localhost, DNS:*.localhost, IP:127.0.0.1, IP:::1
        basicConstraints = critical, CA:FALSE
        keyUsage = critical, digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        """.write(to: conf, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: conf) }
        try run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", String(validDays),
                 "-keyout", key.path, "-out", pem.path, "-config", conf.path])
        try run(["pkcs12", "-export", "-inkey", key.path, "-in", pem.path, "-out", p12.path,
                 "-passout", "pass:" + passphrase])
        try? FileManager.default.removeItem(at: key)
    }

    private static func run(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: opensslPath)
        p.arguments = args
        let err = Pipe()
        p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { throw LocalCertificateError.openSSLFailed("\(error)") }
        let message = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw LocalCertificateError.openSSLFailed(String(decoding: message, as: UTF8.self))
        }
    }
}
