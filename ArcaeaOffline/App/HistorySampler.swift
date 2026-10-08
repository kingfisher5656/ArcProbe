import Foundation

/// Displays a bounded subset while preserving each date bucket's low and high values.
/// Callers retain their full archive for inspection and export.
enum HistorySampler {
    static func nearest<T>(_ sorted: [T], reference: Double, key: (T) -> Double) -> T? {
        guard !sorted.isEmpty else { return nil }
        var low = 0, high = sorted.count
        while low < high {
            let middle = low + (high - low) / 2
            if key(sorted[middle]) < reference { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return sorted[0] }
        if low == sorted.count { return sorted[sorted.count - 1] }
        return abs(key(sorted[low - 1]) - reference) <= abs(key(sorted[low]) - reference) ? sorted[low - 1] : sorted[low]
    }
    static func sample<T>(_ sorted: [T], budget: Int = 1500, value: (T) -> Double) -> [T] {
        guard sorted.count > budget else { return sorted }
        guard budget >= 2 else { return Array(sorted.prefix(max(0, budget))) }
        guard budget >= 4 else { return [sorted[0], sorted[sorted.count - 1]] }
        let bucketCount = (budget - 2) / 2
        let chunkSize = Int(ceil(Double(sorted.count - 2) / Double(bucketCount)))
        var indices = [0]
        var start = 1
        while start < sorted.count - 1 {
            let end = min(start + chunkSize, sorted.count - 1)
            var low = start, high = start
            for index in start..<end {
                if value(sorted[index]) < value(sorted[low]) { low = index }
                if value(sorted[index]) > value(sorted[high]) { high = index }
            }
            indices.append(contentsOf: low == high ? [low] : [min(low, high), max(low, high)])
            start = end
        }
        indices.append(sorted.count - 1)
        return indices.map { sorted[$0] }
    }
}
