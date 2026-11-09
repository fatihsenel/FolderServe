import Foundation

/// Narrows the Activity list by the HTTP status family of each request.
enum StatusFilter: CaseIterable, Equatable {
    case any, success, redirect, errors

    var label: String {
        switch self {
        case .any: "Any status"
        case .success: "Success"
        case .redirect: "Redirects"
        case .errors: "Errors"
        }
    }

    /// What the chip's tooltip says it matches.
    var detail: String {
        switch self {
        case .any: "Every request"
        case .success: "Status 200–299"
        case .redirect: "Status 300–399"
        case .errors: "Status 400 and above: not found, forbidden, server errors, failed proxy calls"
        }
    }

    func matches(status: Int) -> Bool {
        switch self {
        case .any: true
        case .success: (200..<300).contains(status)
        case .redirect: (300..<400).contains(status)
        case .errors: status >= 400
        }
    }
}
