import Testing
@testable import CmuxSettings

/// vmux builds itself with `scripts/build-vmux.sh`, which rewrites the bundle
/// identifier of a stock cmux build. The identifier it picks has to stay inside a
/// namespace `variant(bundleIdentifier:environment:)` recognizes, so these pin the
/// classification the build script depends on rather than the script's string.
@Test func vmuxIsATagScopedStagingVariant() {
    let vmux = "com.cmuxterm.app.staging.vmux"
    let variant = SocketPathMarkerFiles.variant(bundleIdentifier: vmux, environment: [:])

    #expect(variant == .staging(slug: "vmux"))
    #expect(variant.markerFileName == "staging-vmux-last-socket-path")
    #expect(variant.tmpPath == "/tmp/cmux-staging-vmux-last-socket-path")
    #expect(SocketPathMarkerFiles.defaultSocketPath(
        bundleIdentifier: vmux,
        environment: [:],
        isDebugBuild: false,
        stableSocketPath: "/stable/cmux.sock"
    ) == "/tmp/cmux-staging-vmux.sock")

    // Selects the ephemeral socket client secret in
    // `makeSocketClientCapabilityAuthority`. A keychain-backed secret cannot be
    // held by vmux's ad-hoc signature, and an agent whose capability check fails
    // launches without cmux's integration.
    #expect(SocketControlSettings.isStagingBundleIdentifier(vmux))
}

/// An identifier outside every known namespace is classified as the shipping
/// build, which is what vmux 1.0.0 did: it shared an installed cmux's socket and
/// marker files while reporting itself as a separate app.
@Test func anIdentifierOutsideTheNamespaceFallsBackToStable() {
    #expect(SocketPathMarkerFiles.variant(
        bundleIdentifier: "com.vmuxterm.app",
        environment: [:]
    ) == .stable)
    #expect(SocketPathMarkerFiles.defaultSocketPath(
        bundleIdentifier: "com.vmuxterm.app",
        environment: [:],
        isDebugBuild: false,
        stableSocketPath: "/stable/cmux.sock"
    ) == "/stable/cmux.sock")
    #expect(!SocketControlSettings.isStagingBundleIdentifier("com.vmuxterm.app"))
}
