#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Libm wrappers. Calling `log2` inside a function of the same name would recurse.
enum PB {
    static func log2(_ x: Double) -> Double {
        #if canImport(Darwin)
        Darwin.log2(x)
        #elseif canImport(Glibc)
        Glibc.log2(x)
        #elseif canImport(Musl)
        Musl.log2(x)
        #endif
    }

    static func sin(_ x: Double) -> Double {
        #if canImport(Darwin)
        Darwin.sin(x)
        #elseif canImport(Glibc)
        Glibc.sin(x)
        #elseif canImport(Musl)
        Musl.sin(x)
        #endif
    }

    static func cos(_ x: Double) -> Double {
        #if canImport(Darwin)
        Darwin.cos(x)
        #elseif canImport(Glibc)
        Glibc.cos(x)
        #elseif canImport(Musl)
        Musl.cos(x)
        #endif
    }

    static func atan2(_ y: Double, _ x: Double) -> Double {
        #if canImport(Darwin)
        Darwin.atan2(y, x)
        #elseif canImport(Glibc)
        Glibc.atan2(y, x)
        #elseif canImport(Musl)
        Musl.atan2(y, x)
        #endif
    }

    static func exp(_ x: Double) -> Double {
        #if canImport(Darwin)
        Darwin.exp(x)
        #elseif canImport(Glibc)
        Glibc.exp(x)
        #elseif canImport(Musl)
        Musl.exp(x)
        #endif
    }

    static func ln(_ x: Double) -> Double {
        #if canImport(Darwin)
        Darwin.log(x)
        #elseif canImport(Glibc)
        Glibc.log(x)
        #elseif canImport(Musl)
        Musl.log(x)
        #endif
    }

    static func pow(_ x: Double, _ y: Double) -> Double {
        #if canImport(Darwin)
        Darwin.pow(x, y)
        #elseif canImport(Glibc)
        Glibc.pow(x, y)
        #elseif canImport(Musl)
        Musl.pow(x, y)
        #endif
    }

    static let pi = Double.pi
}

enum Cents {
    /// Cents from `reference` up to `actual`. Positive means `actual` is sharp.
    static func between(_ reference: Double, _ actual: Double) -> Double? {
        guard reference > 0, actual > 0, reference.isFinite, actual.isFinite else { return nil }
        return 1200 * PB.log2(actual / reference)
    }

    static func shift(_ frequency: Double, by cents: Double) -> Double {
        guard frequency > 0, cents.isFinite else { return frequency }
        return frequency * PB.pow(2, cents / 1200)
    }
}

enum Regression {
    static func line(x: [Double], y: [Double]) -> (intercept: Double, slope: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        var sumX = 0.0
        var sumY = 0.0
        for i in 0..<x.count {
            sumX += x[i]
            sumY += y[i]
        }
        let meanX = sumX / n
        let meanY = sumY / n
        var sxx = 0.0
        var sxy = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            sxx += dx * dx
            sxy += dx * (y[i] - meanY)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        return (meanY - slope * meanX, slope)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return 0.5 * (sorted[mid - 1] + sorted[mid])
        }
        return sorted[mid]
    }
}

enum LinearSolver {
    /// Gaussian elimination with partial pivoting. `matrix` is row-major n×n.
    static func solve(matrix: [[Double]], rhs: [Double]) -> [Double]? {
        let n = rhs.count
        guard matrix.count == n, n > 0 else { return nil }
        var a = matrix
        var b = rhs
        for column in 0..<n {
            var pivot = column
            var best = abs(a[column][column])
            if column + 1 < n {
                for row in (column + 1)..<n where abs(a[row][column]) > best {
                    best = abs(a[row][column])
                    pivot = row
                }
            }
            if best < 1e-14 { return nil }
            if pivot != column {
                a.swapAt(pivot, column)
                b.swapAt(pivot, column)
            }
            let divisor = a[column][column]
            for row in (column + 1)..<n {
                let factor = a[row][column] / divisor
                if factor == 0 { continue }
                for col in column..<n {
                    a[row][col] -= factor * a[column][col]
                }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            if row + 1 < n {
                for col in (row + 1)..<n {
                    sum -= a[row][col] * x[col]
                }
            }
            x[row] = sum / a[row][row]
        }
        return x
    }
}
