import Foundation

public enum Drive {
    /// `amount == 0` is identity; otherwise tanh(x*(1+9a)) / tanh(1+9a), limited to [-1, 1].
    public static func process(_ x: Float, amount: Float) -> Float {
        if amount == 0 { return x }
        let k = 1 + 9 * amount
        let y = tanh(x * k) / tanh(k)
        return min(max(y, -1), 1)
    }
}
