import AppKit
import Foundation

// 粘贴服务：负责将 ClipItem 写入系统粘贴板并触发 Command+V
public final class PasteService: PasteServiceProtocol {
    private var stack: [ClipItem] = []
    private var stackActive = false
    private var asc = true
    public init() {}
    public func paste(_ item: ClipItem, plainText: Bool) {
        // 单次粘贴（可选择纯文本）
        writeToPasteboard(item, plainText: plainText)
        // sendCommandV()
    }
    // 开启栈式粘贴，asc 控制顺序（正序/倒序）
    public func activateStack(directionAsc: Bool) { stackActive = true; asc = directionAsc }
    public func deactivateStack() { stackActive = false; stack.removeAll() }
    public func pushToStack(_ item: ClipItem) { if stackActive { stack.append(item) } }
    public func deliverStack() {
        // 依序将栈中的条目写入并模拟粘贴快捷键
        let seq = asc ? stack : stack.reversed()
        for i in seq {
            writeToPasteboard(i, plainText: false)
            // sendCommandV()
        }
        stack.removeAll()
    }
    private func writeToPasteboard(_ item: ClipItem, plainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if plainText {
            if item.type == .text {
                if item.metadata["rich"] == "rtf" {
                    if item.metadata["plainSource"] == "pb" {
                        pb.setString(item.text ?? "", forType: .string)
                    } else if let u = item.contentRef, let s = try? NSAttributedString(url: u, options: [:], documentAttributes: nil) {
                        pb.setString(s.string, forType: .string)
                    } else {
                        pb.setString(item.text ?? "", forType: .string)
                    }
                } else if item.metadata["rich"] == "html" {
                    if let u = item.contentRef, let d = try? Data(contentsOf: u), let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                        pb.setString(a.string, forType: .string)
                    } else {
                        pb.setString(item.text ?? "", forType: .string)
                    }
                } else if let u = item.contentRef, let s = try? String(contentsOf: u) {
                    pb.setString(s, forType: .string)
                } else {
                    pb.setString(item.text ?? "", forType: .string)
                }
            } else {
                pb.setString(item.text ?? "", forType: .string)
            }
            return
        }
        switch item.type {
        case .text:
            if let u = item.contentRef, item.metadata["rich"] == "rtf" {
                if let d = try? Data(contentsOf: u) { 
                    pb.setData(d, forType: .rtf)
                    if let a = try? NSAttributedString(url: u, options: [:], documentAttributes: nil) { pb.setString(a.string, forType: .string) } else { pb.setString(item.text ?? "", forType: .string) }
                } else if let a = try? NSAttributedString(url: u, options: [:], documentAttributes: nil) { pb.setString(a.string, forType: .string) }
                else { pb.setString(item.text ?? "", forType: .string) }
            } else if let u = item.contentRef, item.metadata["rich"] == "html" {
                if let d = try? Data(contentsOf: u) {
                    pb.setData(d, forType: .html)
                    if item.metadata["plainSource"] == "pb", let t = item.text { 
                        pb.setString(t, forType: .string)
                    } else if let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                        pb.setString(a.string, forType: .string)
                        let range = NSRange(location: 0, length: a.length)
                        if let r = a.rtf(from: range, documentAttributes: [:]) { pb.setData(r, forType: .rtf) }
                    } else { 
                        pb.setString(item.text ?? "", forType: .string)
                    }
                } else {
                    pb.setString(item.text ?? "", forType: .string)
                }
            } else if let u = item.contentRef, let s = try? String(contentsOf: u) {
                pb.setString(s, forType: .string)
            } else {
                pb.setString(item.text ?? "", forType: .string)
            }
        case .link:
            if let u = item.contentRef { pb.setString(u.absoluteString, forType: .URL) }
        case .image:
            if let u = item.contentRef, let d = try? Data(contentsOf: u) { pb.setData(d, forType: .png) }
        case .file:
            if let u = item.contentRef { pb.setString(u.absoluteString, forType: .fileURL) }
        case .color:
            break
        }
    }

    // 纯文本粘贴不做富文本到纯文本的重写，避免数据不一致
    private func sendCommandV() {
        // 通过 CGEvent 模拟 Command+V 键盘事件以触发粘贴
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        vDown?.flags = [.maskCommand]
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vUp?.flags = [.maskCommand]
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}
