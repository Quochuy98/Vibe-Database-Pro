import AppKit

@MainActor
public final class FrozenColumnCoordinator: NSObject {
  private weak var frozenScrollView: NSScrollView?
  private weak var mainScrollView: NSScrollView?
  private var isSynchronizing = false

  public private(set) var synchronizationCount = 0

  public init(frozenScrollView: NSScrollView, mainScrollView: NSScrollView) {
    self.frozenScrollView = frozenScrollView
    self.mainScrollView = mainScrollView
    super.init()

    frozenScrollView.contentView.postsBoundsChangedNotifications = true
    mainScrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(boundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: frozenScrollView.contentView
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(boundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: mainScrollView.contentView
    )
  }

  public func synchronizeFromMain() {
    guard let mainScrollView, let frozenScrollView else {
      return
    }
    synchronize(source: mainScrollView, target: frozenScrollView)
  }

  public func synchronizeFromFrozen() {
    guard let mainScrollView, let frozenScrollView else {
      return
    }
    synchronize(source: frozenScrollView, target: mainScrollView)
  }

  @objc
  private func boundsDidChange(_ notification: Notification) {
    guard let sourceClipView = notification.object as? NSClipView else {
      return
    }
    if sourceClipView === mainScrollView?.contentView {
      synchronizeFromMain()
    } else if sourceClipView === frozenScrollView?.contentView {
      synchronizeFromFrozen()
    }
  }

  private func synchronize(source: NSScrollView, target: NSScrollView) {
    guard !isSynchronizing else {
      return
    }
    let sourceY = source.contentView.bounds.origin.y
    let maximumY = max(
      0,
      (target.documentView?.bounds.height ?? 0) - target.contentSize.height
    )
    let targetY = min(max(sourceY, 0), maximumY)
    guard abs(target.contentView.bounds.origin.y - targetY) > 0.25 else {
      return
    }

    isSynchronizing = true
    var targetOrigin = target.contentView.bounds.origin
    targetOrigin.y = targetY
    target.contentView.scroll(to: targetOrigin)
    target.reflectScrolledClipView(target.contentView)
    synchronizationCount += 1
    isSynchronizing = false
  }
}
