import AppKit
import Common

/// Alternative name: AttrAddressibleStorage
protocol AxUiElementMock {
    func read<Attr: ReadableAttr>(_ attr: Attr) -> Result<Attr.T?, AXReadFailure>
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool
    func containingWindowId() -> CGWindowID?
}

extension AxUiElementMock {
    func read<Attr: ReadableAttr>(_ attr: Attr) -> Result<Attr.T?, AXReadFailure> { .success(get(attr)) }
    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool { false }
    var cast: AXUIElement { self as! AXUIElement }
}
