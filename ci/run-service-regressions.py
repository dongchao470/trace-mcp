"""Test the production service-control sources with in-memory VPN/storage adapters only."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--prepare-only', action='store_true')
parser.add_argument('--output', default='.service-regressions')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
out = Path(args.output).resolve()
sources = out / 'Sources/TraceServiceFixes'
tests = out / 'Tests/TraceServiceFixesTests'
sources.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
production = [
    'TraceCore/Config/CaptureConfiguration.swift',
    'TraceCore/Config/CaptureOptions.swift',
    'TraceCore/Config/CaptureRecordingState.swift',
    'TraceCore/Config/RecordingTransitionQueue.swift',
    'TraceCore/Models/CaptureSession.swift',
    'TraceFeatures/VPN/VPNMessageReply.swift',
    'Trace/Services/NetworkCaptureService.swift',
]
for name in production:
    source = root / name
    text = source.read_text()
    # Only module imports change. The production implementation is otherwise identical.
    text = re.sub(r'^import (?:TraceCore|TraceFeatures)\n', '', text, flags=re.M)
    (sources / source.name).write_text(text)
    print(hashlib.sha256(source.read_bytes()).hexdigest(), name, flush=True)
vpn_source = (root / 'TraceFeatures/VPN/VPNManager.swift').read_text()
protocol = re.search(r'@MainActor\npublic protocol VPNManaging: AnyObject \{.*?\n\}', vpn_source, re.S)
if protocol is None:
    raise SystemExit('Could not locate the exact production VPNManaging protocol')
adapters = '''import Foundation
import Combine
import OSLog

''' + protocol.group(0) + '''

// Defaults deliberately trap: tests must never reach a real VPN or App Group store.
@MainActor
public final class VPNManager: VPNManaging {
    public static let shared = VPNManager()
    public var isConnected: Bool { preconditionFailure("Inject an in-memory VPN") }
    public var isConnectedPublisher: AnyPublisher<Bool, Never> { preconditionFailure("Inject an in-memory VPN") }
    public var isDefinitelyStopped: Bool { preconditionFailure("Inject an in-memory VPN") }
    public func prepareForControl() async throws { preconditionFailure("No real VPN in regressions") }
    public func start() async throws { preconditionFailure("No real VPN in regressions") }
    public func stop() { preconditionFailure("No real VPN in regressions") }
    public func stopAndWait() async throws { preconditionFailure("No real VPN in regressions") }
    public func sendMessage(_ message: [String: Any]) async throws -> Data? { preconditionFailure("No provider messages in regressions") }
}
final class AppGroupStorage {
    static let shared = AppGroupStorage()
    func loadConfiguration() -> CaptureConfiguration { preconditionFailure("Inject in-memory configuration") }
    func saveConfiguration(_ value: CaptureConfiguration) throws { preconditionFailure("No real storage in regressions") }
}
enum FeatureLog {
    static let vpn = Logger(subsystem: "TraceServiceRegressions", category: "test")
}
'''
(sources / 'TestOnlyAdapters.swift').write_text(adapters)
shutil.copy2(root / 'ci/TraceServiceRecordingRegressionTests.swift', tests)
(out / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TraceServiceFixes", platforms: [.macOS(.v13)], targets: [
    .target(name: "TraceServiceFixes", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "TraceServiceFixesTests", dependencies: ["TraceServiceFixes"], swiftSettings: [.swiftLanguageMode(.v5)])
])
''')
print('SERVICE_REGRESSION_PACKAGE_READY', out, flush=True)
if not args.prepare_only:
    subprocess.run(['xcrun', 'swift', 'test', '-j', '4'], cwd=out, check=True)
