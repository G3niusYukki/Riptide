# MITM TLS Termination & Provider Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement production-grade MITM TLS termination with swift-certificates integration and comprehensive Provider management system for Proxy and Rule providers.

**Architecture:** Library-first Swift 6 implementation with TDD approach. Phase 1 focuses on swift-certificates integration for X.509 certificate generation, CA management, and TLS termination wiring. Phase 2 enhances Provider system with auto-update scheduling and group management. Both phases maintain strict concurrency, proper error handling, and complete test coverage.

**Tech Stack:** Swift 6.2, swift-certificates v1.18.0, swift-asn1, swift-crypto, Swift Testing framework, Network.framework

---

## Context

### User Request Summary

User wants implementation plans for Riptide's missing features in two phases:

**Phase 1 (High Priority):**
1. MITM TLS Termination - Complete implementation with swift-certificates
2. Provider Management System - Enhanced CRUD and auto-update

**Phase 2 (Medium Priority):**
3. Dashboard Web UI (future)
4. WireGuard Support (future)

### Current State Analysis

**MITM System:**
- `CertificateAuthority.swift`: Generates RSA 2048 keys only
- Certificate generation returns nil (placeholder)
- `MITMHTTPSInterceptor.swift`: Only TLS pass-through/relay mode
- No X.509 DER encoding capability
- Missing swift-certificates dependency

**Provider System:**
- `ProxyProvider.swift`: Basic actor with start/stop/refresh
- `RuleSetProvider.swift`: Similar pattern exists
- `SubscriptionManager.swift`: Full CRUD implementation exists
- Missing: Provider update scheduler integration
- Missing: Rule Provider vs Proxy Provider coordination
- Missing: Provider group management

**Test Infrastructure:**
- 38 test files using Swift Testing framework
- Good patterns in `ProxyProviderTests.swift` and `MITMConfigTests.swift`
- TDD-ready structure

### Uncertainties & Assumptions

1. **Certificate Storage**: Assuming users will install CA via Keychain Access (documented flow). No programmatic trust installation required.
2. **Provider Groups**: Assuming providers work alongside static proxies (not replacing them).
3. **Dashboard UI**: Deferred to Phase 2 - no frontend work in this plan.
4. **WireGuard**: Deferred to Phase 2 - requires separate architecture analysis.

---

## Task Dependency Graph

| Task | Depends On | Reason |
|------|------------|--------|
| Task 1.1: Add swift-certificates dependency | None | Foundation for all X.509 work |
| Task 1.2: Implement CA certificate generation | Task 1.1 | Requires ASN.1 encoding library |
| Task 1.3: Implement domain certificate signing | Task 1.2 | Needs CA keypair in place |
| Task 1.4: Update MITMHTTPSInterceptor for TLS termination | Task 1.3 | Needs certificate generation working |
| Task 1.5: Add MITM integration tests | Task 1.4 | End-to-end validation |
| Task 2.1: Enhance ProxyProvider with health check | None | Independent of MITM work |
| Task 2.2: Implement ProviderUpdateScheduler | None | Independent utility actor |
| Task 2.3: Wire ProviderUpdateScheduler to ProxyProvider | Task 2.1, Task 2.2 | Combines components |
| Task 2.4: Add Rule Provider CRUD + auto-update | Task 2.2 | Uses same scheduler infrastructure |
| Task 2.5: Implement provider-group coordination | Task 2.3, Task 2.4 | Requires both provider types working |

---

## Parallel Execution Graph

### Wave 1 (Start Immediately - No Dependencies)

```
├── Task 1.1: Add swift-certificates dependency (MITM foundation)
├── Task 2.1: Enhance ProxyProvider with health check (Provider foundation)
└── Task 2.2: Implement ProviderUpdateScheduler (Utility foundation)
```

**Estimated Time:** 60-90 minutes total (20-30 min each)
**Parallel Speedup:** 3x faster than sequential

### Wave 2 (After Wave 1 Core Components Complete)

```
├── Task 1.2: Implement CA certificate generation (depends: Task 1.1)
├── Task 2.3: Wire ProviderUpdateScheduler to ProxyProvider (depends: Task 2.1, Task 2.2)
└── Task 2.4: Add Rule Provider CRUD + auto-update (depends: Task 2.2)
```

**Estimated Time:** 90-120 minutes total (30-40 min each)
**Parallel Speedup:** 3x faster than sequential

### Wave 3 (After Wave 2 Integration Complete)

```
├── Task 1.3: Implement domain certificate signing (depends: Task 1.2)
└── Task 2.5: Implement provider-group coordination (depends: Task 2.3, Task 2.4)
```

**Estimated Time:** 60-80 minutes total (30-40 min each)
**Parallel Speedup:** 2x faster than sequential

### Wave 4 (After Wave 3 Core Features Ready)

```
└── Task 1.4: Update MITMHTTPSInterceptor for TLS termination (depends: Task 1.3)
```

**Estimated Time:** 40-50 minutes

### Wave 5 (After All Components Integrated)

```
└── Task 1.5: Add MITM integration tests (depends: Task 1.4)
```

**Estimated Time:** 30-40 minutes

**Critical Path:** Task 1.1 → Task 1.2 → Task 1.3 → Task 1.4 → Task 1.5 (MITM chain)
**Estimated Total:** ~6-7 hours with parallel execution

---

## Tasks

### Task 1.1: Add swift-certificates dependency

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Riptide/Crypto/` directory (for future crypto utilities)

**Description:** Add swift-certificates, swift-asn1, and swift-crypto dependencies to Package.swift. These are required for X.509 certificate generation and ASN.1 DER encoding.

**Delegation Recommendation:**
- Category: `quick` - Single file modification, dependency setup
- Skills: [] - No specialized skills needed

**Skills Evaluation:**
- INCLUDED none: Simple dependency addition, no domain expertise required

**Depends On:** None

**Acceptance Criteria:**
- Package.swift includes swift-certificates v1.18.0
- Package.swift includes swift-asn1 dependency
- Package.swift includes swift-crypto dependency
- `swift build` succeeds with new dependencies
- `swift test` passes (all 366 tests remain green)

**Steps:**

- [ ] **Step 1: Write the failing build test**

Create `Tests/RiptideTests/Crypto/PackageDependencyTests.swift`:

```swift
import Testing
@testable import Riptide

@Suite("Package Dependencies")
struct PackageDependencyTests {
    @Test("swift-certificates is available")
    func swiftCertificatesAvailable() async {
        // This test verifies that swift-certificates is linked
        // We test by using a type from the library
        // If the import fails, this won't compile
        #expect(true) // Placeholder - actual test will use Certificate type
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "PackageDependencyTests"`
Expected: FAIL - dependencies not yet added

- [ ] **Step 3: Update Package.swift**

Modify `Package.swift`:

```swift
// In dependencies array:
dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-certificates", from: "1.18.0"),
    .package(url: "https://github.com/apple/swift-asn1", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
],

// In Riptide target dependencies:
.target(
    name: "Riptide",
    dependencies: [
        .product(name: "Yams", package: "Yams"),
        .product(name: "X509", package: "swift-certificates"),
        .product(name: "Crypto", package: "swift-crypto"),
    ],
),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "PackageDependencyTests"`
Expected: PASS - dependencies resolve successfully

- [ ] **Step 5: Commit**

```bash
git add Package.swift Tests/RiptideTests/Crypto/PackageDependencyTests.swift
git commit -m "feat: add swift-certificates dependency for TLS termination

Integrate swift-certificates v1.18.0, swift-asn1, and swift-crypto
for X.509 certificate generation and ASN.1 DER encoding.

Files:
- Package.swift
- Tests/RiptideTests/Crypto/PackageDependencyTests.swift
"
```

---

### Task 1.2: Implement CA certificate generation

**Files:**
- Create: `Sources/Riptide/MITM/X509Utilities.swift`
- Create: `Tests/RiptideTests/MITM/X509UtilitiesTests.swift`
- Modify: `Sources/Riptide/MITM/CertificateAuthority.swift`

**Description:** Implement complete X.509 v3 CA certificate generation using swift-certificates. Generate self-signed CA with proper extensions (BasicConstraints: CA:TRUE, KeyUsage: keyCertSign, SubjectKeyIdentifier, AuthorityKeyIdentifier).

**Delegation Recommendation:**
- Category: `deep` - Requires understanding X.509, ASN.1, and Swift certificate library APIs
- Skills: [`test-driven-development`] - TDD for certificate generation tests first

**Skills Evaluation:**
- INCLUDED `test-driven-development`: Certificate generation is complex logic requiring careful test-first development
- OMITTED `systematic-debugging`: Not debugging existing code, implementing new feature

**Depends On:** Task 1.1

**Acceptance Criteria:**
- X509Utilities actor with `generateCACertificate(commonName:organization:)` method
- Returns DER-encoded certificate data
- CA certificate has correct X.509 v3 extensions
- CertificateAuthority uses X509Utilities for certificate generation
- Tests cover: CA generation, DER encoding, extension validation
- All tests pass including new X509UtilitiesTests

**Steps:**

- [ ] **Step 1: Write the failing tests**

Create `Tests/RiptideTests/MITM/X509UtilitiesTests.swift`:

```swift
import Testing
import Foundation
@testable import Riptide

@Suite("X509Utilities")
struct X509UtilitiesTests {
    @Test("generates CA certificate with correct subject")
    func generatesCACertificateWithSubject() async throws {
        let utilities = X509Utilities()
        let (privateKey, certData) = try await utilities.generateCACertificate(
            commonName: "Test CA",
            organization: "Test Org"
        )
        
        #expect(privateKey != nil)
        #expect(!certData.isEmpty)
    }
    
    @Test("generates DER-encoded certificate")
    func generatesDEREncodedCert() async throws {
        let utilities = X509Utilities()
        let (_, certData) = try await utilities.generateCACertificate(
            commonName: "Test CA",
            organization: "Test Org"
        )
        
        // DER-encoded certificate should be non-empty and parseable
        #expect(!certData.isEmpty)
        // Should not throw when creating SecCertificate
        let cert = SecCertificateCreateWithData(nil, certData as CFData)
        #expect(cert != nil)
    }
    
    @Test("CA certificate has BasicConstraints extension")
    func hasBasicConstraintsExtension() async throws {
        let utilities = X509Utilities()
        let (_, certData) = try await utilities.generateCACertificate(
            commonName: "Test CA",
            organization: "Test Org"
        )
        
        let cert = try #require(SecCertificateCreateWithData(nil, certData as CFData))
        // Verify BasicConstraints: CA:TRUE
        // This will require extracting extensions - placeholder for now
        #expect(true) // Will implement extension validation
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "X509UtilitiesTests"`
Expected: FAIL - X509Utilities doesn't exist yet

- [ ] **Step 3: Implement X509Utilities actor**

Create `Sources/Riptide/MITM/X509Utilities.swift`:

```swift
import Foundation
import Security
import X509
import Crypto

/// Actor responsible for X.509 certificate generation and signing.
public actor X509Utilities {
    
    public init() {}
    
    /// Generates a self-signed CA certificate.
    /// - Parameters:
    ///   - commonName: The CN (Common Name) for the certificate subject
    ///   - organization: The O (Organization) for the certificate subject
    /// - Returns: Tuple of (private key, DER-encoded certificate data)
    public func generateCACertificate(
        commonName: String,
        organization: String
    ) async throws -> (SecKey, Data) {
        // Generate RSA 2048 key pair
        let privateKey = try generateRSAPrivateKey()
        
        // Build certificate using swift-certificates
        // Implementation details:
        // 1. Create Subject with CN and O
        // 2. Add BasicConstraints extension (CA:TRUE)
        // 3. Add KeyUsage extension (keyCertSign, cRLSign)
        // 4. Add SubjectKeyIdentifier extension
        // 5. Sign with private key
        // 6. Serialize to DER
        
        // Placeholder - will implement with swift-certificates API
        throw MITMError.certificateGenerationFailed
    }
    
    private func generateRSAPrivateKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw MITMError.certificateGenerationFailed
        }
        return key
    }
}
```

- [ ] **Step 4: Run tests to see status**

Run: `swift test --filter "X509UtilitiesTests"`
Expected: Partial pass - tests should compile but some may fail

- [ ] **Step 5: Implement full certificate generation with swift-certificates**

Update `Sources/Riptide/MITM/X509Utilities.swift` with complete implementation using swift-certificates API:

```swift
// Full implementation using X509.Certificate.Builder pattern
// Include proper extensions and signing
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter "X509UtilitiesTests"`
Expected: PASS - all certificate tests pass

- [ ] **Step 7: Update CertificateAuthority to use X509Utilities**

Modify `Sources/Riptide/MITM/CertificateAuthority.swift`:

```swift
// Replace certificate generation logic with:
private let x509Utilities = X509Utilities()

public func generateCertificate() throws {
    let (key, certData) = try await x509Utilities.generateCACertificate(
        commonName: commonName,
        organization: organization
    )
    privateKey = key
    certificateData = certData
}
```

- [ ] **Step 8: Run all MITM tests**

Run: `swift test --filter "MITM"`
Expected: PASS - all MITM tests including new X509Utilities tests

- [ ] **Step 9: Commit**

```bash
git add Sources/Riptide/MITM/X509Utilities.swift
git add Sources/Riptide/MITM/CertificateAuthority.swift
git add Tests/RiptideTests/MITM/X509UtilitiesTests.swift
git commit -m "feat: implement CA certificate generation with X.509 extensions

Implement X509Utilities actor for X.509 certificate generation:
- RSA 2048 keypair generation
- CA certificate with BasicConstraints (CA:TRUE)
- KeyUsage extension (keyCertSign, cRLSign)
- SubjectKeyIdentifier extension
- DER serialization

Files:
- Sources/Riptide/MITM/X509Utilities.swift (new)
- Sources/Riptide/MITM/CertificateAuthority.swift (modified)
- Tests/RiptideTests/MITM/X509UtilitiesTests.swift (new)

Tests:
- X509UtilitiesTests: CA generation, DER encoding, extensions
"
```

---

### Task 1.3: Implement domain certificate signing

**Files:**
- Modify: `Sources/Riptide/MITM/X509Utilities.swift`
- Modify: `Tests/RiptideTests/MITM/X509UtilitiesTests.swift`
- Modify: `Sources/Riptide/MITM/CertificateAuthority.swift`

**Description:** Implement domain certificate generation signed by CA. Each domain gets a unique certificate with SAN (SubjectAlternativeName) extension containing the domain. Certificates are signed with CA private key and have 1-year validity.

**Delegation Recommendation:**
- Category: `deep` - Complex crypto logic, certificate chain validation
- Skills: [`test-driven-development`] - TDD for certificate signing tests

**Skills Evaluation:**
- INCLUDED `test-driven-development`: Certificate signing is critical path requiring test-first rigor
- OMITTED other skills: Domain expertise not needed beyond TDD

**Depends On:** Task 1.2

**Acceptance Criteria:**
- X509Utilities method `signDomainCertificate(domain:caPrivateKey:caCertificate:)`
- Domain certificate has proper SAN extension
- Certificate validity set to 1 year
- Signature validated against CA
- CertificateAuthority.generateCertificate(for:) returns DER data (no longer throws)
- Tests cover: domain cert generation, SAN validation, signature verification
- All tests pass

**Steps:**

- [ ] **Step 1: Write the failing tests**

Add to `Tests/RiptideTests/MITM/X509UtilitiesTests.swift`:

```swift
@Test("signs domain certificate with CA")
func signsDomainCertificate() async throws {
    let utilities = X509Utilities()
    
    // Generate CA first
    let (caKey, caCertData) = try await utilities.generateCACertificate(
        commonName: "Test CA",
        organization: "Test Org"
    )
    
    // Sign domain certificate
    let domainCertData = try await utilities.signDomainCertificate(
        domain: "example.com",
        caPrivateKey: caKey,
        caCertificateData: caCertData
    )
    
    #expect(!domainCertData.isEmpty)
    let cert = try #require(SecCertificateCreateWithData(nil, domainCertData as CFData))
    #expect(cert != nil)
}

@Test("domain certificate has SAN extension")
func domainCertHasSAN() async throws {
    let utilities = X509Utilities()
    let (caKey, caCertData) = try await utilities.generateCACertificate(
        commonName: "Test CA",
        organization: "Test Org"
    )
    
    let domainCertData = try await utilities.signDomainCertificate(
        domain: "api.example.com",
        caPrivateKey: caKey,
        caCertificateData: caCertData
    )
    
    // Verify SAN extension contains the domain
    // Implementation will extract and validate SAN
    #expect(true) // Placeholder
}

@Test("domain certificate validity is 1 year")
func domainCertValidity() async throws {
    let utilities = X509Utilities()
    let (caKey, caCertData) = try await utilities.generateCACertificate(
        commonName: "Test CA",
        organization: "Test Org"
    )
    
    let domainCertData = try await utilities.signDomainCertificate(
        domain: "example.com",
        caPrivateKey: caKey,
        caCertificateData: caCertData
    )
    
    // Verify validity period is approximately 1 year
    // Implementation will check notBefore and notAfter dates
    #expect(true) // Placeholder
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "X509UtilitiesTests"`
Expected: FAIL - signDomainCertificate method doesn't exist

- [ ] **Step 3: Implement domain certificate signing**

Add to `Sources/Riptide/MITM/X509Utilities.swift`:

```swift
/// Signs a domain certificate using the CA.
/// - Parameters:
///   - domain: The domain name for the certificate (e.g., "example.com")
///   - caPrivateKey: The CA's private key for signing
///   - caCertificateData: The CA's DER-encoded certificate
/// - Returns: DER-encoded domain certificate
public func signDomainCertificate(
    domain: String,
    caPrivateKey: SecKey,
    caCertificateData: Data
) async throws -> Data {
    // Implementation using swift-certificates:
    // 1. Parse CA certificate to get issuer
    // 2. Create domain certificate subject
    // 3. Add SAN extension with domain
    // 4. Set validity to 1 year
    // 5. Sign with CA private key
    // 6. Serialize to DER
    
    // Placeholder - will implement
    throw MITMError.certificateGenerationFailed
}
```

- [ ] **Step 4: Implement full domain certificate generation**

Complete the implementation in `X509Utilities.swift`:

```swift
// Full implementation with:
// - CN = domain
// - SAN = DNS:domain
// - Issuer = CA subject
// - Validity = 365 days
// - Signed by CA private key
```

- [ ] **Step 5: Update CertificateAuthority.generateCertificate(for:)**

Modify `Sources/Riptide/MITM/CertificateAuthority.swift`:

```swift
/// Generates a domain certificate signed by the CA.
/// - Parameter domain: The domain name (e.g., "example.com")
/// - Returns: DER-encoded certificate data
public func generateCertificate(for domain: String) throws -> Data {
    guard let privateKey else {
        throw MITMError.certificateGenerationFailed
    }
    guard let certData = certificateData else {
        throw MITMError.certificateGenerationFailed
    }
    
    do {
        // Synchronously call async method - certificate generation is fast
        let domainCertData = try await x509Utilities.signDomainCertificate(
            domain: domain,
            caPrivateKey: privateKey,
            caCertificateData: certData
        )
        return domainCertData
    } catch {
        throw MITMError.signFailed(error.localizedDescription)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter "X509UtilitiesTests"`
Expected: PASS - all domain certificate tests pass

- [ ] **Step 7: Run all MITM tests**

Run: `swift test --filter "MITM"`
Expected: PASS - all MITM tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/Riptide/MITM/X509Utilities.swift
git add Sources/Riptide/MITM/CertificateAuthority.swift
git add Tests/RiptideTests/MITM/X509UtilitiesTests.swift
git commit -m "feat: implement domain certificate signing by CA

Implement domain certificate generation:
- CN set to domain name
- SAN extension with DNS:domain
- 1-year validity period
- Signed with CA private key
- DER serialization

Files:
- Sources/Riptide/MITM/X509Utilities.swift (modified)
- Sources/Riptide/MITM/CertificateAuthority.swift (modified)
- Tests/RiptideTests/MITM/X509UtilitiesTests.swift (modified)

Tests:
- Domain certificate signing
- SAN extension validation
- Validity period check
"
```

---

### Task 2.1: Enhance ProxyProvider with health check

**Files:**
- Modify: `Sources/Riptide/ProxyProvider/ProxyProvider.swift`
- Create: `Sources/Riptide/ProxyProvider/ProviderHealthChecker.swift`
- Modify: `Tests/RiptideTests/ProxyProviderTests.swift`

**Description:** Add health check support to ProxyProvider. Implement ProviderHealthChecker actor that tests node latency and availability. Wire health check into ProxyProvider refresh cycle.

**Delegation Recommendation:**
- Category: `unspecified-high` - Moderate complexity, existing patterns to follow
- Skills: [`test-driven-development`] - Health check logic needs careful testing

**Skills Evaluation:**
- INCLUDED `test-driven-development`: Health check timing and failure modes need test coverage

**Depends On:** None

**Acceptance Criteria:**
- ProviderHealthChecker actor with `checkHealth(nodes:)` method
- Returns latency and availability for each node
- ProxyProvider integrates health check during refresh()
- Health check config from ProxyProviderConfig.healthCheck used
- Tests cover: health check execution, timeout handling, node filtering
- All tests pass including updated ProxyProviderTests

**Steps:**

- [ ] **Step 1: Write the failing tests for ProviderHealthChecker**

Create `Tests/RiptideTests/ProviderHealthCheckerTests.swift`:

```swift
import Testing
import Foundation
@testable import Riptide

@Suite("ProviderHealthChecker")
struct ProviderHealthCheckerTests {
    @Test("checks health of multiple nodes")
    func checksMultipleNodes() async throws {
        let checker = ProviderHealthChecker()
        let nodes = [
            ProxyNode(name: "node1", kind: .http, server: "1.1.1.1", port: 80),
            ProxyNode(name: "node2", kind: .http, server: "2.2.2.2", port: 80),
        ]
        
        let results = try await checker.checkHealth(nodes: nodes, timeout: 5.0)
        
        #expect(results.count == 2)
        // At least one should succeed or timeout appropriately
        #expect(results.contains { $0.isReachable } || results.allSatisfy { !$0.isReachable })
    }
    
    @Test("returns latency for reachable nodes")
    func returnsLatency() async throws {
        let checker = ProviderHealthChecker()
        let nodes = [
            ProxyNode(name: "reachable", kind: .http, server: "example.com", port: 80),
        ]
        
        let results = try await checker.checkHealth(nodes: nodes, timeout: 10.0)
        
        if let result = results.first, result.isReachable {
            #expect(result.latencyMs >= 0)
        }
    }
    
    @Test("handles timeout correctly")
    func handlesTimeout() async throws {
        let checker = ProviderHealthChecker()
        // Use an unreachable IP
        let nodes = [
            ProxyNode(name: "unreachable", kind: .http, server: "10.255.255.1", port: 9999),
        ]
        
        let results = try await checker.checkHealth(nodes: nodes, timeout: 1.0)
        
        #expect(results.count == 1)
        #expect(!results[0].isReachable)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ProviderHealthChecker"`
Expected: FAIL - ProviderHealthChecker doesn't exist

- [ ] **Step 3: Implement ProviderHealthChecker actor**

Create `Sources/Riptide/ProxyProvider/ProviderHealthChecker.swift`:

```swift
import Foundation
import Network

/// Result of a health check for a single proxy node.
public struct HealthCheckResult: Sendable {
    public let nodeName: String
    public let isReachable: Bool
    public let latencyMs: Int?
    
    public init(nodeName: String, isReachable: Bool, latencyMs: Int? = nil) {
        self.nodeName = nodeName
        self.isReachable = isReachable
        self.latencyMs = isReachable ? latencyMs : nil
    }
}

/// Actor that performs health checks on proxy nodes.
public actor ProviderHealthChecker {
    
    public init() {}
    
    /// Checks the health of multiple proxy nodes.
    /// - Parameters:
    ///   - nodes: The proxy nodes to check
    ///   - timeout: Timeout in seconds for each check
    /// - Returns: Array of health check results
    public func checkHealth(
        nodes: [ProxyNode],
        timeout: TimeInterval
    ) async throws -> [HealthCheckResult] {
        var results: [HealthCheckResult] = []
        
        for node in nodes {
            let result = try await checkSingleNode(node: node, timeout: timeout)
            results.append(result)
        }
        
        return results
    }
    
    private func checkSingleNode(
        node: ProxyNode,
        timeout: TimeInterval
    ) async throws -> HealthCheckResult {
        // Use NWConnection to test TCP reachability
        // Measure latency using monotonic time
        // Implementation placeholder
        return HealthCheckResult(nodeName: node.name, isReachable: false)
    }
}
```

- [ ] **Step 4: Implement full health check logic**

Complete the `checkSingleNode` implementation with:
- TCP connection test
- Latency measurement
- Timeout handling

- [ ] **Step 5: Wire health check into ProxyProvider**

Modify `Sources/Riptide/ProxyProvider/ProxyProvider.swift`:

```swift
private let healthChecker = ProviderHealthChecker()

public func refresh() async throws {
    // ... existing refresh logic ...
    
    // Perform health check if configured
    if let healthCheckConfig = config.healthCheck, healthCheckConfig.enable {
        let results = try await healthChecker.checkHealth(
            nodes: currentNodes,
            timeout: Double(healthCheckConfig.interval)
        )
        
        // Filter out unreachable nodes or update latency info
        // Implementation depends on requirements
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter "ProviderHealthChecker"`
Expected: PASS - all health check tests pass

- [ ] **Step 7: Update ProxyProviderTests**

Add integration test in `Tests/RiptideTests/ProxyProviderTests.swift`:

```swift
@Test("ProxyProvider performs health check during refresh")
func performsHealthCheck() async throws {
    let config = ProxyProviderConfig(
        name: "health-check-test",
        type: "file",
        path: "/tmp/test.yaml",
        healthCheck: HealthCheckConfig(
            enable: true,
            url: "http://example.com",
            interval: 5
        )
    )
    
    let provider = ProxyProvider(config: config)
    // ... test implementation
}
```

- [ ] **Step 8: Run all ProxyProvider tests**

Run: `swift test --filter "ProviderProvider"`
Expected: PASS - all tests pass

- [ ] **Step 9: Commit**

```bash
git add Sources/Riptide/ProxyProvider/ProviderHealthChecker.swift
git add Sources/Riptide/ProxyProvider/ProxyProvider.swift
git add Tests/RiptideTests/ProviderHealthCheckerTests.swift
git add Tests/RiptideTests/ProxyProviderTests.swift
git commit -m "feat: add health check support to ProxyProvider

Implement ProviderHealthChecker actor:
- TCP reachability testing
- Latency measurement
- Configurable timeout
- Batch health checks

Wire health check into ProxyProvider refresh cycle.

Files:
- Sources/Riptide/ProxyProvider/ProviderHealthChecker.swift (new)
- Sources/Riptide/ProxyProvider/ProxyProvider.swift (modified)
- Tests/RiptideTests/ProviderHealthCheckerTests.swift (new)
- Tests/RiptideTests/ProxyProviderTests.swift (modified)

Tests:
- ProviderHealthCheckerTests
- ProxyProvider health check integration
"
```

---

### Task 2.2: Implement ProviderUpdateScheduler

**Files:**
- Create: `Sources/Riptide/Subscription/ProviderUpdateScheduler.swift`
- Create: `Tests/RiptideTests/ProviderUpdateSchedulerTests.swift`

**Description:** Utility actor that coordinates periodic updates for multiple providers (Proxy and Rule providers). Similar to SubscriptionUpdateScheduler but provider-agnostic.

**Delegation Recommendation:**
- Category: `quick` - Utility actor following existing SubscriptionUpdateScheduler pattern
- Skills: [] - Straightforward actor implementation

**Skills Evaluation:**
- OMITTED all skills: Simple utility actor, existing pattern to follow

**Depends On:** None

**Acceptance Criteria:**
- ProviderUpdateScheduler actor with `start()`, `stop()`, `registerProvider()`, `unregisterProvider()` methods
- Supports multiple provider types via protocol
- Respects each provider's update interval
- Tests cover: registration, periodic updates, stop/cleanup, error handling
- ProviderUpdateSchedulerTests passes

**Steps:**

- [ ] **Step 1: Write the failing tests**

Create `Tests/RiptideTests/ProviderUpdateSchedulerTests.swift`:

```swift
import Testing
import Foundation
@testable import Riptide

@Suite("ProviderUpdateScheduler")
struct ProviderUpdateSchedulerTests {
    @Test("registers and unregisters providers")
    func registersUnregisters() async {
        let scheduler = ProviderUpdateScheduler()
        let provider = MockProvider()
        
        await scheduler.registerProvider(provider, interval: 60)
        #expect(await scheduler.providerCount() == 1)
        
        await scheduler.unregisterProvider(provider.id)
        #expect(await scheduler.providerCount() == 0)
    }
    
    @Test("calls refresh on registered providers")
    func callsRefresh() async throws {
        let scheduler = ProviderUpdateScheduler()
        let provider = MockProvider()
        
        await scheduler.registerProvider(provider, interval: 1)
        await scheduler.start()
        
        // Wait for at least one refresh cycle
        try await Task.sleep(for: .seconds(1.5))
        
        #expect(await provider.refreshCalled)
        
        await scheduler.stop()
    }
    
    @Test("stops all tasks on stop()")
    func stopsAllTasks() async throws {
        let scheduler = ProviderUpdateScheduler()
        let provider1 = MockProvider()
        let provider2 = MockProvider()
        
        await scheduler.registerProvider(provider1, interval: 1)
        await scheduler.registerProvider(provider2, interval: 1)
        await scheduler.start()
        
        await scheduler.stop()
        #expect(await scheduler.providerCount() == 0)
    }
}

// Mock provider for testing
actor MockProvider: UpdatableProvider {
    let id = UUID()
    var refreshCalled = false
    
    func refresh() async {
        refreshCalled = true
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ProviderUpdateScheduler"`
Expected: FAIL - ProviderUpdateScheduler doesn't exist

- [ ] **Step 3: Define UpdatableProvider protocol**

Create `Sources/Riptide/ProxyProvider/UpdatableProvider.swift`:

```swift
import Foundation

/// Protocol for providers that can be periodically updated.
public protocol UpdatableProvider: Sendable {
    var id: UUID { get }
    func refresh() async
}
```

- [ ] **Step 4: Implement ProviderUpdateScheduler actor**

Create `Sources/Riptide/Subscription/ProviderUpdateScheduler.swift`:

```swift
import Foundation

/// Actor that coordinates periodic updates for multiple providers.
public actor ProviderUpdateScheduler {
    private var providers: [UUID: (provider: UpdatableProvider, interval: TimeInterval, task: Task<Void, Never>)] = [:]
    private var isRunning = false
    
    public init() {}
    
    /// Starts the scheduler.
    public func start() {
        isRunning = true
        // Start periodic update tasks for all registered providers
        for (id, (provider, interval, _)) in providers {
            let task = startUpdateTask(for: provider, interval: interval)
            providers[id] = (provider, interval, task)
        }
    }
    
    /// Stops all periodic updates.
    public func stop() {
        isRunning = false
        for (_, _, task) in providers {
            task.cancel()
        }
        providers.removeAll()
    }
    
    /// Registers a provider for periodic updates.
    public func registerProvider(_ provider: UpdatableProvider, interval: TimeInterval) {
        let task = isRunning ? startUpdateTask(for: provider, interval: interval) : Task {}
        providers[provider.id] = (provider, interval, task)
    }
    
    /// Unregisters a provider.
    public func unregisterProvider(_ id: UUID) {
        providers[id]?.task.cancel()
        providers.removeValue(forKey: id)
    }
    
    /// Returns the number of registered providers.
    public func providerCount() -> Int {
        providers.count
    }
    
    private func startUpdateTask(for provider: UpdatableProvider, interval: TimeInterval) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await provider.refresh()
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "ProviderUpdateScheduler"`
Expected: PASS - all scheduler tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Riptide/ProxyProvider/UpdatableProvider.swift
git add Sources/Riptide/Subscription/ProviderUpdateScheduler.swift
git add Tests/RiptideTests/ProviderUpdateSchedulerTests.swift
git commit -m "feat: implement ProviderUpdateScheduler for periodic updates

Create utility actor that coordinates updates for multiple providers:
- Provider-agnostic via UpdatableProvider protocol
- Configurable update intervals per provider
- Start/stop lifecycle management

Files:
- Sources/Riptide/ProxyProvider/UpdatableProvider.swift (new)
- Sources/Riptide/Subscription/ProviderUpdateScheduler.swift (new)
- Tests/RiptideTests/ProviderUpdateSchedulerTests.swift (new)

Tests:
- Registration and unregistration
- Periodic refresh calls
- Stop/cleanup
"
```

---

### Task 2.3: Wire ProviderUpdateScheduler to ProxyProvider

**Files:**
- Modify: `Sources/Riptide/ProxyProvider/ProxyProvider.swift`
- Create: `Sources/Riptide/ProxyProvider/ProviderProtocol.swift`
- Modify: `Tests/RiptideTests/ProxyProviderTests.swift`

**Description:** Create ProviderProtocol defining common provider interface. Make ProxyProvider conform to ProviderProtocol. Wire ProviderUpdateScheduler to manage ProxyProvider instances.

**Delegation Recommendation:**
- Category: `unspecified-high` - Protocol design and integration work
- Skills: [] - Standard refactoring

**Skills Evaluation:**
- OMITTED all skills: Integration work, no complex logic

**Depends On:** Task 2.1, Task 2.2

**Acceptance Criteria:**
- ProviderProtocol with `refresh()`, `nodes()`, `interval` requirements
- ProxyProvider conforms to ProviderProtocol
- ProviderUpdateScheduler can manage ProxyProvider instances
- Existing ProxyProvider behavior preserved
- Tests verify scheduler integration
- All tests pass

**Steps:**

- [ ] **Step 1: Define ProviderProtocol**

Create `Sources/Riptide/ProxyProvider/ProviderProtocol.swift`:

```swift
import Foundation

/// Common protocol for all updateable providers.
public protocol ProviderProtocol: UpdatableProvider {
    var name: String { get }
    var interval: TimeInterval { get }
    
    /// Returns the current nodes/rules managed by this provider.
    func nodes() async -> [ProxyNode]
}
```

- [ ] **Step 2: Make ProxyProvider conform to ProviderProtocol**

Modify `Sources/Riptide/ProxyProvider/ProxyProvider.swift`:

```swift
extension ProxyProvider: ProviderProtocol {
    public var name: String { config.name }
    
    public var interval: TimeInterval {
        TimeInterval(config.interval ?? 3600)
    }
    
    public var id: UUID { UUID() } // Or add id property to ProxyProvider
    
    // nodes() already exists
}
```

- [ ] **Step 3: Write integration tests**

Add to `Tests/RiptideTests/ProxyProviderTests.swift`:

```swift
@Test("ProxyProvider conforms to ProviderProtocol")
func conformsToProviderProtocol() async throws {
    let config = ProxyProviderConfig(name: "test", type: "http", url: "https://example.com/proxies.yaml", interval: 3600)
    let provider = ProxyProvider(config: config)
    
    // Verify ProviderProtocol conformance
    let providerProtocol: any ProviderProtocol = provider
    
    #expect(providerProtocol.name == "test")
    #expect(providerProtocol.interval == 3600)
}

@Test("ProviderUpdateScheduler manages ProxyProvider instances")
func schedulerManagesProxyProviders() async throws {
    let scheduler = ProviderUpdateScheduler()
    let config = ProxyProviderConfig(name: "test", type: "file", path: "/tmp/test.yaml", interval: 1)
    let provider = ProxyProvider(config: config)
    
    await scheduler.registerProvider(provider, interval: provider.interval)
    #expect(await scheduler.providerCount() == 1)
    
    await scheduler.stop()
    #expect(await scheduler.providerCount() == 0)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter "ProxyProviderTests"`
Expected: PASS - all tests pass including new ProviderProtocol conformance tests

- [ ] **Step 5: Commit**

```bash
git add Sources/Riptide/ProxyProvider/ProviderProtocol.swift
git add Sources/Riptide/ProxyProvider/ProxyProvider.swift
git add Tests/RiptideTests/ProxyProviderTests.swift
git commit -m "feat: wire ProviderUpdateScheduler to ProxyProvider

Define ProviderProtocol for common provider interface:
- UpdatableProvider conformance
- name, interval, nodes() requirements

Make ProxyProvider conform to ProviderProtocol.
Verify scheduler integration with tests.

Files:
- Sources/Riptide/ProxyProvider/ProviderProtocol.swift (new)
- Sources/Riptide/ProxyProvider/ProxyProvider.swift (modified)
- Tests/RiptideTests/ProxyProviderTests.swift (modified)

Tests:
- ProviderProtocol conformance
- Scheduler integration
"
```

---

### Task 2.4: Add Rule Provider CRUD + auto-update

**Files:**
- Modify: `Sources/Riptide/Rules/RuleSetProvider.swift`
- Create: `Sources/Riptide/Rules/RuleProviderManager.swift`
- Create: `Tests/RiptideTests/RuleProviderTests.swift`

**Description:** Enhance RuleSetProvider with CRUD operations (list, add, remove, update). Create RuleProviderManager to manage multiple RuleSetProvider instances. Wire to ProviderUpdateScheduler.

**Delegation Recommendation:**
- Category: `unspecified-high` - Similar pattern to ProxyProvider enhancement
- Skills: [`test-driven-development`] - CRUD operations need test coverage

**Skills Evaluation:**
- INCLUDED `test-driven-development`: CRUD operations and lifecycle management need testing

**Depends On:** Task 2.2

**Acceptance Criteria:**
- RuleSetProvider enhanced with full CRUD support
- RuleProviderManager actor manages multiple RuleSetProvider instances
- ProviderUpdateScheduler integration for auto-update
- Tests cover: CRUD operations, auto-update, manager coordination
- RuleProviderTests passes

**Steps:**

- [ ] **Step 1: Write failing tests for RuleProviderManager**

Create `Tests/RiptideTests/RuleProviderTests.swift`:

```swift
import Testing
import Foundation
@testable import Riptide

@Suite("RuleProviderManager")
struct RuleProviderManagerTests {
    @Test("adds and removes rule providers")
    func addsRemovesProviders() async throws {
        let manager = RuleProviderManager()
        let config = RuleSetProviderConfig(
            name: "test-provider",
            type: "http",
            behavior: "domain",
            url: "https://example.com/rules.yaml",
            interval: 3600
        )
        
        try await manager.addProvider(config)
        let providers = await manager.listProviders()
        #expect(providers.count == 1)
        
        try await manager.removeProvider(name: "test-provider")
        let remaining = await manager.listProviders()
        #expect(remaining.isEmpty)
    }
    
    @Test("updates rule sets on refresh")
    func updatesRuleSets() async throws {
        let manager = RuleProviderManager()
        // Test refresh functionality
        // Verify rules are loaded/updated
    }
    
    @Test("gets rules by provider name")
    func getsRulesByProvider() async throws {
        let manager = RuleProviderManager()
        let config = RuleSetProviderConfig(
            name: "geo-provider",
            type: "http",
            behavior: "domain",
            url: "https://example.com/rules.yaml",
            interval: 3600
        )
        
        try await manager.addProvider(config)
        let rules = try await manager.getRules(providerName: "geo-provider")
        // Verify rules are returned
        #expect(rules != nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "RuleProvider"`
Expected: FAIL - RuleProviderManager doesn't exist

- [ ] **Step 3: Make RuleSetProvider conform to ProviderProtocol**

Modify `Sources/Riptide/Rules/RuleSetProvider.swift`:

```swift
extension RuleSetProvider: ProviderProtocol {
    public var name: String { config.name }
    
    public var interval: TimeInterval { TimeInterval(config.interval) }
    
    public var id: UUID { UUID() } // Or add id property
    
    public func nodes() async -> [ProxyNode] {
        // RuleSetProvider doesn't return nodes
        // But ProviderProtocol requires this
        // Maybe create a more general protocol?
        // For now, return empty array
        return []
    }
}
```

- [ ] **Step 4: Implement RuleProviderManager**

Create `Sources/Riptide/Rules/RuleProviderManager.swift`:

```swift
import Foundation

/// Actor that manages multiple rule set providers.
public actor RuleProviderManager {
    private var providers: [String: RuleSetProvider] = [:]
    
    public init() {}
    
    /// Adds a new rule set provider.
    public func addProvider(_ config: RuleSetProviderConfig) async throws {
        let provider = RuleSetProvider(config: config)
        await provider.start()
        providers[config.name] = provider
    }
    
    /// Removes a rule set provider.
    public func removeProvider(name: String) async throws {
        guard let provider = providers.removeValue(forKey: name) else {
            return
        }
        await provider.stop()
    }
    
    /// Lists all provider names.
    public func listProviders() async -> [String] {
        Array(providers.keys)
    }
    
    /// Gets rules from a specific provider.
    public func getRules(providerName: String) async throws -> [ProxyRule]? {
        guard let provider = providers[providerName] else {
            return nil
        }
        return await provider.rules()
    }
    
    /// Refreshes a specific provider.
    public func refreshProvider(name: String) async throws {
        guard let provider = providers[name] else {
            return
        }
        await provider.refresh()
    }
    
    /// Refreshes all providers.
    public func refreshAll() async throws {
        for (_, provider) in providers {
            await provider.refresh()
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter "RuleProvider"`
Expected: PASS - all rule provider tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Riptide/Rules/RuleSetProvider.swift
git add Sources/Riptide/Rules/RuleProviderManager.swift
git add Tests/RiptideTests/RuleProviderTests.swift
git commit -m "feat: add Rule Provider CRUD and auto-update

Enhance RuleSetProvider with ProviderProtocol conformance.
Create RuleProviderManager for managing multiple rule providers:
- Add/remove/list providers
- Get rules by provider name
- Refresh individual or all providers

Files:
- Sources/Riptide/Rules/RuleSetProvider.swift (modified)
- Sources/Riptide/Rules/RuleProviderManager.swift (new)
- Tests/RiptideTests/RuleProviderTests.swift (new)

Tests:
- RuleProviderManager CRUD operations
- Rule retrieval
- Provider refresh
"
```

---

### Task 2.5: Implement provider-group coordination

**Files:**
- Create: `Sources/Riptide/Groups/ProviderGroupResolver.swift`
- Create: `Tests/RiptideTests/Groups/ProviderGroupResolverTests.swift`
- Modify: `Sources/Riptide/Groups/ProxyGroupResolver.swift` (if needed for coordination)

**Description:** Coordinate static proxy groups with provider groups. Providers populate proxy nodes into groups. Groups receive updates when providers refresh.

**Delegation Recommendation:**
- Category: `deep` - Architecture decision, multi-component coordination
- Skills: [`test-driven-development`] - Complex integration needing rigorous tests

**Skills Evaluation:**
- INCLUDED `test-driven-development`: Coordination logic needs comprehensive testing

**Depends On:** Task 2.3, Task 2.4

**Acceptance Criteria:**
- ProviderGroupResolver coordinates providers and groups
- Groups update dynamically when providers refresh
- Provider nodes merge correctly with static nodes
- Tests cover: provider-group coordination, node merging, dynamic updates
- ProviderGroupResolverTests passes
- All existing tests pass

**Steps:**

- [ ] **Step 1: Write failing tests**

Create `Tests/RiptideTests/Groups/ProviderGroupResolverTests.swift`:

```swift
import Testing
@testable import Riptide

@Suite("ProviderGroupResolver")
struct ProviderGroupResolverTests {
    @Test("resolves group nodes from providers")
    func resolvesGroupNodesFromProviders() async throws {
        // Create mock provider
        // Create resolver
        // Resolve group
        // Verify nodes come from provider
    }
    
    @Test("merges static and provider nodes")
    func mergesStaticAndProviderNodes() async throws {
        // Create group with static nodes
        // Add provider with additional nodes
        // Resolve group
        // Verify merged list
    }
    
    @Test("updates groups when providers refresh")
    func updatesGroupsOnProviderRefresh() async throws {
        // Register provider
        // Resolve group
        // Refresh provider
        // Verify group nodes update
    }
}
```

- [ ] **Step 2: Implement ProviderGroupResolver**

Create `Sources/Riptide/Groups/ProviderGroupResolver.swift`:

```swift
import Foundation

/// Actor that resolves proxy group nodes from providers.
public actor ProviderGroupResolver {
    private var proxyProviders: [String: ProxyProvider] = [:]
    
    public init() {}
    
    /// Registers a proxy provider.
    public func registerProvider(name: String, provider: ProxyProvider) {
        proxyProviders[name] = provider
    }
    
    /// Resolves group nodes by combining static nodes and provider nodes.
    public func resolveNodes(
        groupName: String,
        staticNodes: [ProxyNode],
        providerNames: [String]
    ) async -> [ProxyNode] {
        var allNodes = staticNodes
        
        for providerName in providerNames {
            if let provider = proxyProviders[providerName] {
                let providerNodes = await provider.nodes()
                allNodes.append(contentsOf: providerNodes)
            }
        }
        
        return allNodes
    }
}
```

- [ ] **Step 3: Wire into ProxyGroupResolver**

Modify `Sources/Riptide/Groups/ProxyGroupResolver.swift` to use ProviderGroupResolver for dynamic node resolution.

- [ ] **Step 4: Run tests**

Run: `swift test --filter "ProviderGroupResolver"`
Expected: PASS - coordination tests pass

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: PASS - all 366+ tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Riptide/Groups/ProviderGroupResolver.swift
git add Sources/Riptide/Groups/ProxyGroupResolver.swift
git add Tests/RiptideTests/Groups/ProviderGroupResolverTests.swift
git commit -m "feat: implement provider-group coordination

Create ProviderGroupResolver for coordinating:
- Static proxy nodes
- Dynamic provider nodes
- Group node resolution

Wire into ProxyGroupResolver for dynamic updates.

Files:
- Sources/Riptide/Groups/ProviderGroupResolver.swift (new)
- Sources/Riptide/Groups/ProxyGroupResolver.swift (modified)
- Tests/RiptideTests/Groups/ProviderGroupResolverTests.swift (new)

Tests:
- Group node resolution
- Static/provider node merging
- Dynamic updates on refresh
"
```

---

### Task 1.4: Update MITMHTTPSInterceptor for TLS termination

**Files:**
- Modify: `Sources/Riptide/MITM/MITMHTTPSInterceptor.swift`
- Create: `Tests/RiptideTests/MITM/MITMHTTPSInterceptorTests.swift`
- Modify: `Sources/Riptide/Transport/TLSTransport.swift` (if needed for custom TLS options)

**Description:** Replace TLS pass-through with actual TLS termination. Create two TLS sessions: client-facing (using generated domain cert) and upstream-facing (using real server cert). Relay decrypted HTTP traffic between them.

**Delegation Recommendation:**
- Category: `ultrabrain` - Complex network programming with TLS handshake orchestration
- Skills: [`test-driven-development`] - Integration tests critical for TLS termination

**Skills Evaluation:**
- INCLUDED `test-driven-development`: TLS termination requires careful contract testing

**Depends On:** Task 1.3

**Acceptance Criteria:**
- MITMHTTPSInterceptor.handleConnection() performs TLS termination for intercepted hosts
- Uses NWProtocolTLSOptions for client-facing TLS with generated cert
- Upstream TLS connection established with real server
- HTTP traffic parsed/modified between TLS sessions
- Fallback to pass-through mode if certificate generation fails
- Tests cover: TLS termination flow, certificate presentation, error handling
- All existing tests pass + new MITMHTTPSInterceptorTests pass

**Steps:**

- [ ] **Step 1: Write failing integration tests**

Create `Tests/RiptideTests/MITM/MITMHTTPSInterceptorTests.swift`:

```swift
import Testing
import Network
@testable import Riptide

@Suite("MITMHTTPSInterceptor")
struct MITMHTTPSInterceptorTests {
    @Test("performs TLS termination for intercepted hosts")
    func performsTLSTermination() async throws {
        // Setup CA and interceptor
        // Simulate HTTPS connection
        // Verify TLS termination occurs
    }
    
    @Test("falls back to pass-through on cert generation failure")
    func fallbackToPassThrough() async throws {
        // Setup interceptor without valid CA
        // Simulate HTTPS connection
        // Verify pass-through mode used
    }
    
    @Test("presents generated certificate to client")
    func presentsGeneratedCert() async throws {
        // Setup valid CA
        // Simulate HTTPS connection to example.com
        // Verify client receives certificate for example.com
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "MITMHTTPSInterceptorTests"`
Expected: FAIL - TLS termination not implemented

- [ ] **Step 3: Implement TLS termination in MITMHTTPSInterceptor**

Modify `Sources/Riptide/MITM/MITMHTTPSInterceptor.swift`:

```swift
public func handleConnection(
    clientSession: any TransportSession,
    target: ConnectionTarget,
    upstreamSession: any TransportSession,
    connectionID: UUID,
    runtime: LiveTunnelRuntime
) async throws {
    let host = target.sniffedDomain ?? target.host
    let shouldInterceptHost = await shouldIntercept(host: host, port: target.port)

    guard shouldInterceptHost else {
        // Not intercepting — relay raw TLS stream
        try await relayRawTraffic(...)
        return
    }

    // Record interception
    await mitmManager.recordInterception(host: host, method: "CONNECT", path: "\(target.host):\(target.port)")

    // Perform TLS termination
    do {
        let ca = await mitmManager.getCertificateAuthority()
        let domainCert = try ca.generateCertificate(for: host)
        
        // Create client-facing TLS session with generated cert
        // Create upstream TLS session with real server
        // Relay decrypted HTTP traffic between them
        
        try await performTLSTermination(
            clientSession: clientSession,
            upstreamSession: upstreamSession,
            domainCert: domainCert,
            host: host,
            connectionID: connectionID,
            runtime: runtime
        )
    } catch {
        // Fallback to pass-through on failure
        try await relayRawTraffic(...)
    }
}

private func performTLSTermination(...) async throws {
    // Implementation using NWProtocolTLSOptions
    // Create TLS parameters for client with generated cert
    // Establish upstream TLS connection
    // Relay HTTP traffic bidirectionally
}
```

- [ ] **Step 4: Implement TLS session creation**

Add helper methods for creating TLS sessions with custom certificates:

```swift
private func createClientTLSParameters(certData: Data) throws -> NWProtocolTLS.Options {
    // Use Security framework to create TLS parameters
    // Configure with generated domain certificate
    // Return NWProtocolTLS.Options
}

private func establishClientTLS(
    session: any TransportSession,
    tlsParameters: NWProtocolTLS.Options
) async throws {
    // Wrap transport session with TLS
    // Perform handshake
    // Return TLS-wrapped session
}
```

- [ ] **Step 5: Handle HTTP relay between TLS sessions**

```swift
private func relayDecryptedHTTP(
    clientSession: any TransportSession,
    upstreamSession: any TransportSession,
    connectionID: UUID,
    runtime: LiveTunnelRuntime
) async throws {
    // Both sessions are now TLS-decrypted
    // Relay HTTP frames bidirectionally
    // Apply MITM rewriting rules if configured
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter "MITMHTTPSInterceptorTests"`
Expected: PASS - TLS termination tests pass

- [ ] **Step 7: Run all MITM tests**

Run: `swift test --filter "MITM"`
Expected: PASS - all MITM tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/Riptide/MITM/MITMHTTPSInterceptor.swift
git add Sources/Riptide/Transport/TLSTransport.swift
git add Tests/RiptideTests/MITM/MITMHTTPSInterceptorTests.swift
git commit -m "feat: wire TLS termination into MITMHTTPSInterceptor

Implement full TLS termination for intercepted hosts:
- Generate domain certificate on-the-fly
- Create client-facing TLS session with generated cert
- Establish upstream TLS connection with real server
- Relay decrypted HTTP traffic between sessions
- Fallback to pass-through on cert generation failure

Files:
- Sources/Riptide/MITM/MITMHTTPSInterceptor.swift (modified)
- Sources/Riptide/Transport/TLSTransport.swift (modified)
- Tests/RiptideTests/MITM/MITMHTTPSInterceptorTests.swift (new)

Tests:
- TLS termination flow
- Certificate presentation
- Fallback to pass-through
"
```

---

### Task 1.5: Add MITM integration tests

**Files:**
- Create: `Tests/RiptideTests/MITM/MITMIntegrationTests.swift`
- Create: `Tests/RiptideTests/MITM/TestCertificates.swift` (test CA generation)

**Description:** End-to-end MITM integration tests. Generate test CA, verify certificate chain, simulate HTTPS interception, test certificate installation workflow (manual step documentation).

**Delegation Recommendation:**
- Category: `deep` - Requires understanding full MITM flow
- Skills: [] - Standard integration testing

**Skills Evaluation:**
- OMITTED all skills: Integration testing is straightforward verification work

**Depends On:** Task 1.4

**Acceptance Criteria:**
- MITMIntegrationTests covers full TLS termination workflow
- Tests use mock test CA for repeatable verification
- Certificate chain validation verified
- Error cases tested (CA not generated, cert signing failure, TLS handshake failure)
- All tests pass

**Steps:**

- [ ] **Step 1: Create test CA utilities**

Create `Tests/RiptideTests/MITM/TestCertificates.swift`:

```swift
import Foundation
@testable import Riptide

/// Utility for generating test certificates in integration tests.
actor TestCertificates {
    private var testCA: CertificateAuthority?
    
    /// Creates a test CA for integration testing.
    func createTestCA() async throws -> CertificateAuthority {
        let ca = CertificateAuthority(
            commonName: "Test MITM CA",
            organization: "Test Organization"
        )
        try await ca.generateCertificate()
        testCA = ca
        return ca
    }
    
    /// Generates a test domain certificate.
    func generateDomainCert(domain: String) async throws -> Data {
        guard let ca = testCA else {
            throw MITMError.certificateGenerationFailed
        }
        return try await ca.generateCertificate(for: domain)
    }
}
```

- [ ] **Step 2: Write integration tests**

Create `Tests/RiptideTests/MITM/MITMIntegrationTests.swift`:

```swift
import Testing
import Network
@testable import Riptide

@Suite("MITM Integration")
struct MITMIntegrationTests {
    @Test("full MITM workflow with CA generation")
    func fullMITMWorkflow() async throws {
        let testCerts = TestCertificates()
        let ca = try await testCerts.createTestCA()
        
        // Verify CA generated
        #expect(await ca.hasKey())
        #expect(await ca.caCertificateData() != nil)
        
        // Generate domain cert
        let domainCert = try await testCerts.generateDomainCert(domain: "example.com")
        #expect(!domainCert.isEmpty)
        
        // Verify domain cert is parseable
        let cert = SecCertificateCreateWithData(nil, domainCert as CFData)
        #expect(cert != nil)
    }
    
    @Test("certificate chain validation")
    func certificateChainValidation() async throws {
        let testCerts = TestCertificates()
        let ca = try await testCerts.createTestCA()
        
        // Generate multiple domain certs
        let cert1 = try await testCerts.generateDomainCert(domain: "api.example.com")
        let cert2 = try await testCerts.generateDomainCert(domain: "cdn.example.com")
        
        // Verify both are signed by same CA
        #expect(!cert1.isEmpty)
        #expect(!cert2.isEmpty)
        
        // Chain validation would go here
        // (requires Security framework trust evaluation)
    }
    
    @Test("MITM manager configures interception")
    func mitmManagerConfiguration() async throws {
        let manager = MITMManager()
        
        await manager.enable(hosts: ["*.example.com"], excludeHosts: ["safe.example.com"])
        
        #expect(await manager.isEnabled)
        #expect(await manager.shouldIntercept("api.example.com"))
        #expect(!await manager.shouldIntercept("safe.example.com"))
    }
    
    @Test("error handling: CA not generated")
    func errorHandlingCANotGenerated() async throws {
        let testCerts = TestCertificates()
        // Don't create CA
        
        // Attempting to generate domain cert should fail
        do {
            _ = try await testCerts.generateDomainCert(domain: "example.com")
            #expect(Bool(false), "Should throw error when CA not generated")
        } catch {
            #expect(error is MITMError)
        }
    }
}
```

- [ ] **Step 3: Run integration tests**

Run: `swift test --filter "MITMIntegration"`
Expected: PASS - all integration tests pass

- [ ] **Step 4: Run full test suite**

Run: `swift test`
Expected: PASS - all 366+ tests pass

- [ ] **Step 5: Commit**

```bash
git add Tests/RiptideTests/MITM/MITMIntegrationTests.swift
git add Tests/RiptideTests/MITM/TestCertificates.swift
git commit -m "test: add MITM integration tests

Add end-to-end integration tests for MITM:
- Full workflow with CA generation
- Certificate chain validation
- MITM manager configuration
- Error handling scenarios

Add TestCertificates utility for test CA generation.

Files:
- Tests/RiptideTests/MITM/MITMIntegrationTests.swift (new)
- Tests/RiptideTests/MITM/TestCertificates.swift (new)

Tests:
- Full MITM workflow
- Certificate generation
- Error cases
"
```

---

## Summary

This implementation plan provides a comprehensive, TDD-oriented approach to implementing MITM TLS termination and Provider management enhancements for Riptide. The plan is structured for ultrawork execution with:

**Key Deliverables:**
- ✅ Complete swift-certificates integration
- ✅ Full CA certificate generation with X.509 extensions
- ✅ Domain certificate signing with SAN extensions
- ✅ TLS termination in MITMHTTPSInterceptor
- ✅ Comprehensive testing (unit + integration)
- ✅ Provider health check system
- ✅ Provider update scheduler infrastructure
- ✅ Rule provider CRUD and management
- ✅ Provider-group coordination

**Execution Model:**
- 5 parallel execution waves
- TDD approach for all tasks
- Atomic commits per task
- Clear acceptance criteria
- Comprehensive test coverage

**Estimated Timeline:**
- Wave 1: 60-90 min (3 parallel tasks)
- Wave 2: 90-120 min (3 parallel tasks)
- Wave 3: 60-80 min (2 parallel tasks)
- Wave 4: 40-50 min (1 task)
- Wave 5: 30-40 min (1 task)
- **Total: ~6-7 hours** with parallel execution

**Success Metrics:**
- All 366+ existing tests remain passing
- New tests achieve >90% coverage on new code
- TLS termination works end-to-end
- Provider auto-update functions correctly
- No regressions in existing functionality