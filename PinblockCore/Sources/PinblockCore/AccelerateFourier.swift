#if canImport(Accelerate)
import Accelerate
import Foundation

final class FFTSetupCache: @unchecked Sendable {
    static let shared = FFTSetupCache()
    private var setups: [Int: FFTSetup] = [:]
    private let lock = NSLock()

    func setup(log2n: Int) -> FFTSetup {
        lock.lock()
        defer { lock.unlock() }
        if let existing = setups[log2n] { return existing }
        guard let created = vDSP_create_fftsetup(vDSP_Length(log2n), FFT_RADIX2) else {
            fatalError("vDSP_create_fftsetup failed")
        }
        setups[log2n] = created
        return created
    }
}

enum AccelerateFourier {
    static func magnitudes(of samples: [Float]) -> [Float] {
        let windowed = Hann.apply(samples)
        let n = windowed.count
        let log2n = n.trailingZeroBitCount
        guard n > 0, 1 << log2n == n else { return [] }
        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        let setup = FFTSetupCache.shared.setup(log2n: log2n)
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFT_FORWARD)
            }
        }
        var magnitudes = [Float](repeating: 0, count: half + 1)
        magnitudes[0] = abs(real[0])
        magnitudes[half] = abs(imag[0])
        if half > 1 {
            for bin in 1..<half {
                let re = real[bin]
                let im = imag[bin]
                magnitudes[bin] = (re * re + im * im).squareRoot()
            }
        }
        return magnitudes
    }
}
#endif
