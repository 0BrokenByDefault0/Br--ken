import Testing
import Foundation

@Test func appBundleHasContentFolder() {
    #expect(Bundle.main.url(forResource: "Content", withExtension: nil) != nil)
}
