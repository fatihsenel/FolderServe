import Foundation

public enum RangeResult: Equatable, Sendable {
    case none
    case partial(ClosedRange<Int64>)
    case unsatisfiable
}

public enum RangeHeader {
    /// Parses a single `bytes=` range. Multi-range and malformed headers are ignored (`.none`).
    public static func parse(_ header: String?, fileSize: Int64) -> RangeResult {
        guard let header, header.hasPrefix("bytes="), !header.contains(",") else { return .none }
        let spec = header.dropFirst("bytes=".count)
        let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return .none }
        let startText = bounds[0].trimmingCharacters(in: .whitespaces)
        let endText = bounds[1].trimmingCharacters(in: .whitespaces)

        if startText.isEmpty {
            guard let n = Int64(endText), n >= 0 else { return .none }
            if n == 0 || fileSize == 0 { return .unsatisfiable }
            return .partial(max(0, fileSize - n)...(fileSize - 1))
        }
        guard let start = Int64(startText), start >= 0 else { return .none }
        var end: Int64 = fileSize - 1
        if !endText.isEmpty {
            guard let e = Int64(endText), e >= 0 else { return .none }
            if e < start { return .unsatisfiable }
            end = min(e, fileSize - 1)
        }
        if start >= fileSize { return .unsatisfiable }
        return .partial(start...end)
    }
}
