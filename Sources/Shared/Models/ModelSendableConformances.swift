import Foundation

// Intentionally left as a narrow escape hatch.
// Prefer declaration-site `Sendable` conformance first;
// add `@unchecked Sendable` here only for proven-safe types
// that the compiler cannot verify.
