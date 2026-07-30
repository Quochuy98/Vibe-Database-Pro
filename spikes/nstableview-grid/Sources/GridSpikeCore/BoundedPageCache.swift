import Foundation

public struct PageCacheLimits: Equatable, Sendable {
  public let maximumItems: Int
  public let maximumBytes: Int

  public init(maximumItems: Int = 5, maximumBytes: Int = 64 * 1_024 * 1_024) throws {
    guard maximumItems > 0 else {
      throw PageCacheError.invalidLimit("maximumItems must be positive")
    }
    guard maximumBytes > 0 else {
      throw PageCacheError.invalidLimit("maximumBytes must be positive")
    }
    self.maximumItems = maximumItems
    self.maximumBytes = maximumBytes
  }
}

public struct PageCacheInventory: Equatable, Sendable {
  public let itemCount: Int
  public let byteCount: Int
  public let maximumItems: Int
  public let maximumBytes: Int
  public let hitCount: UInt64
  public let missCount: UInt64
  public let evictionCount: UInt64

  public init(
    itemCount: Int,
    byteCount: Int,
    maximumItems: Int,
    maximumBytes: Int,
    hitCount: UInt64,
    missCount: UInt64,
    evictionCount: UInt64
  ) {
    self.itemCount = itemCount
    self.byteCount = byteCount
    self.maximumItems = maximumItems
    self.maximumBytes = maximumBytes
    self.hitCount = hitCount
    self.missCount = missCount
    self.evictionCount = evictionCount
  }
}

public enum PageCacheMemoryPressure: Sendable {
  case warning
  case critical
}

public enum PageCacheError: Error, Equatable, Sendable {
  case invalidLimit(String)
  case invalidByteCost(Int)
  case valueExceedsByteLimit(valueBytes: Int, limitBytes: Int)
}

/// Process-only LRU cache used by the disposable grid spike.
///
/// Ownership belongs to one injected result-page service. Identity includes the
/// result and generation in the caller's key. The cache is bounded by both item
/// and byte ceilings, has no TTL, and is invalidated explicitly on generation
/// changes or memory pressure. Actor isolation is its thread-safety contract.
/// Pending edits must never be stored as `Value`.
public actor BoundedPageCache<Key: Hashable & Sendable, Value: Sendable> {
  private struct Entry: Sendable {
    let value: Value
    let byteCount: Int
    var lastAccess: UInt64
  }

  private let limits: PageCacheLimits
  private let byteCost: @Sendable (Value) -> Int
  private var entries: [Key: Entry] = [:]
  private var currentBytes = 0
  private var accessClock: UInt64 = 0
  private var hitCount: UInt64 = 0
  private var missCount: UInt64 = 0
  private var evictionCount: UInt64 = 0

  public init(
    limits: PageCacheLimits,
    byteCost: @escaping @Sendable (Value) -> Int
  ) {
    self.limits = limits
    self.byteCost = byteCost
  }

  public func value(for key: Key) -> Value? {
    guard var entry = entries[key] else {
      missCount &+= 1
      return nil
    }
    hitCount &+= 1
    entry.lastAccess = nextAccessTick()
    entries[key] = entry
    return entry.value
  }

  @discardableResult
  public func insert(_ value: Value, for key: Key) throws -> PageCacheInventory {
    let valueBytes = byteCost(value)
    guard valueBytes >= 0 else {
      throw PageCacheError.invalidByteCost(valueBytes)
    }
    guard valueBytes <= limits.maximumBytes else {
      throw PageCacheError.valueExceedsByteLimit(
        valueBytes: valueBytes,
        limitBytes: limits.maximumBytes
      )
    }

    if let existing = entries.removeValue(forKey: key) {
      currentBytes -= existing.byteCount
    }

    entries[key] = Entry(
      value: value,
      byteCount: valueBytes,
      lastAccess: nextAccessTick()
    )
    currentBytes += valueBytes
    evictUntilWithin(itemLimit: limits.maximumItems, byteLimit: limits.maximumBytes)
    return inventory()
  }

  @discardableResult
  public func removeValue(for key: Key) -> Value? {
    guard let entry = entries.removeValue(forKey: key) else {
      return nil
    }
    currentBytes -= entry.byteCount
    return entry.value
  }

  public func invalidate(where shouldRemove: @Sendable (Key) -> Bool) {
    let keys = entries.keys.filter(shouldRemove)
    for key in keys {
      evict(key)
    }
  }

  public func removeAll() {
    evictionCount &+= UInt64(entries.count)
    entries.removeAll(keepingCapacity: false)
    currentBytes = 0
  }

  public func handleMemoryPressure(_ pressure: PageCacheMemoryPressure) {
    switch pressure {
    case .warning:
      evictUntilWithin(
        itemLimit: max(1, limits.maximumItems / 2),
        byteLimit: max(1, limits.maximumBytes / 2)
      )
    case .critical:
      removeAll()
    }
  }

  public func inventory() -> PageCacheInventory {
    PageCacheInventory(
      itemCount: entries.count,
      byteCount: currentBytes,
      maximumItems: limits.maximumItems,
      maximumBytes: limits.maximumBytes,
      hitCount: hitCount,
      missCount: missCount,
      evictionCount: evictionCount
    )
  }

  public func contains(_ key: Key) -> Bool {
    entries[key] != nil
  }

  private func nextAccessTick() -> UInt64 {
    accessClock &+= 1
    return accessClock
  }

  private func evictUntilWithin(itemLimit: Int, byteLimit: Int) {
    while entries.count > itemLimit || currentBytes > byteLimit {
      guard
        let leastRecentKey = entries.min(by: { lhs, rhs in
          lhs.value.lastAccess < rhs.value.lastAccess
        })?.key
      else {
        return
      }
      evict(leastRecentKey)
    }
  }

  private func evict(_ key: Key) {
    guard let removed = entries.removeValue(forKey: key) else {
      return
    }
    currentBytes -= removed.byteCount
    evictionCount &+= 1
  }
}
