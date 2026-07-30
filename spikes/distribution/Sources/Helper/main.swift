import Foundation

@main
private struct DataForgeDistributionHelper {
    static func main() {
#if DATAFORGE_REPLACEMENT
        print("dataforge-distribution-helper-replacement")
#else
        print("dataforge-distribution-helper-ok")
#endif
    }
}
