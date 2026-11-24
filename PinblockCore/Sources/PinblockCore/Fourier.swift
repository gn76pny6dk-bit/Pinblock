enum Hann {
    static func apply(_ samples: [Float]) -> [Float] {
        let n = samples.count
        guard n > 1 else { return samples }
        var out = [Float](repeating: 0, count: n)
        let denom = Double(n)
        for index in 0..<n {
            let window = 0.5 * (1 - PB.cos(2 * PB.pi * Double(index) / denom))
            out[index] = samples[index] * Float(window)
        }
        return out
    }
}

enum SwiftFourier {
    static func forward(real input: [Double]) -> (re: [Double], im: [Double]) {
        var re = input
        var im = [Double](repeating: 0, count: input.count)
        transform(&re, &im, inverse: false)
        return (re, im)
    }

    static func magnitudes(of samples: [Float]) -> [Float] {
        let windowed = Hann.apply(samples)
        let n = windowed.count
        var re = windowed.map { Double($0) }
        var im = [Double](repeating: 0, count: n)
        transform(&re, &im, inverse: false)
        var mags = [Float](repeating: 0, count: n / 2 + 1)
        for bin in 0...(n / 2) {
            mags[bin] = Float((re[bin] * re[bin] + im[bin] * im[bin]).squareRoot())
        }
        return mags
    }

    private static func transform(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
        let n = re.count
        var j = 0
        if n > 1 {
            for i in 1..<n {
                var bit = n >> 1
                while j & bit != 0 {
                    j ^= bit
                    bit >>= 1
                }
                j ^= bit
                if i < j {
                    re.swapAt(i, j)
                    im.swapAt(i, j)
                }
            }
        }
        var length = 2
        while length <= n {
            let angle = (inverse ? 2.0 : -2.0) * PB.pi / Double(length)
            let wlenRe = PB.cos(angle)
            let wlenIm = PB.sin(angle)
            var start = 0
            let half = length / 2
            while start < n {
                var wRe = 1.0
                var wIm = 0.0
                for k in 0..<half {
                    let even = start + k
                    let odd = even + half
                    let vRe = re[odd] * wRe - im[odd] * wIm
                    let vIm = re[odd] * wIm + im[odd] * wRe
                    re[odd] = re[even] - vRe
                    im[odd] = im[even] - vIm
                    re[even] += vRe
                    im[even] += vIm
                    let nextRe = wRe * wlenRe - wIm * wlenIm
                    wIm = wRe * wlenIm + wIm * wlenRe
                    wRe = nextRe
                }
                start += length
            }
            length <<= 1
        }
        if inverse {
            let scale = 1 / Double(n)
            for index in 0..<n {
                re[index] *= scale
                im[index] *= scale
            }
        }
    }
}

enum Fourier {
    static func bestLength(upTo count: Int) -> Int {
        guard count >= 2 else { return 0 }
        var length = 1
        while length * 2 <= count {
            length *= 2
        }
        return length
    }

    static func magnitudes(of samples: [Float]) -> [Float] {
        #if canImport(Accelerate)
        return AccelerateFourier.magnitudes(of: samples)
        #else
        return SwiftFourier.magnitudes(of: samples)
        #endif
    }
}
