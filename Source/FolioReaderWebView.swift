//
//  FolioReaderWebView.swift
//  FolioReaderKit
//
//  Created by Hans Seiffert on 21.09.16.
//  Copyright (c) 2016 Folio Reader. All rights reserved.
//

import UIKit
import WebKit

/// The custom WebView used in each page
open class FolioReaderWebView: WKWebView {
    var isColors = false
    var isShare = false
    var isOneWord = false

    fileprivate weak var readerContainer: FolioReaderContainer?

    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    init(frame: CGRect, readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        super.init(frame: frame, configuration: configuration)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.scrollView.backgroundColor = .clear
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIMenuController

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard readerConfig.useReaderMenuController else {
            return super.canPerformAction(action, withSender: sender)
        }

        if isShare {
            return false
        } else if isColors {
            return false
        } else {
            if action == #selector(highlight(_:))
                || action == #selector(highlightWithNote(_:))
                || action == #selector(updateHighlightNote(_:))
                || (action == #selector(define(_:)) && isOneWord)
                || (action == #selector(play(_:)) && (book.hasAudio || readerConfig.enableTTS))
                || (action == #selector(share(_:)) && readerConfig.allowSharing)
                || (action == #selector(copy(_:)) && readerConfig.allowSharing) {
                return true
            }
            return false
        }
    }

    // MARK: - UIMenuController - Actions

    @objc func share(_ sender: UIMenuController) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let shareImage = UIAlertAction(title: self.readerConfig.localizedShareImageQuote, style: .default, handler: { (action) -> Void in
            let script = self.isShare ? "getHighlightContent()" : "getSelectedText()"
            self.js(script) { [weak self] textToShare in
                guard let self = self, let text = textToShare else { return }
                self.folioReader.readerCenter?.presentQuoteShare(text)
                if !self.isShare {
                    self.clearTextSelection()
                }
            }
            self.setMenuVisible(false)
        })

        let shareText = UIAlertAction(title: self.readerConfig.localizedShareTextQuote, style: .default) { (action) -> Void in
            let script = self.isShare ? "getHighlightContent()" : "getSelectedText()"
            self.js(script) { [weak self] textToShare in
                guard let self = self, let text = textToShare else { return }
                self.folioReader.readerCenter?.shareHighlight(text, rect: sender.menuFrame)
            }
            self.setMenuVisible(false)
        }

        let cancel = UIAlertAction(title: self.readerConfig.localizedCancel, style: .cancel, handler: nil)

        alertController.addAction(shareImage)
        alertController.addAction(shareText)
        alertController.addAction(cancel)

        if let alert = alertController.popoverPresentationController {
            alert.sourceView = self.folioReader.readerCenter?.currentPage
            alert.sourceRect = sender.menuFrame
        }

        self.folioReader.readerCenter?.present(alertController, animated: true, completion: nil)
    }

    func colors(_ sender: UIMenuController?) {
        isColors = true
        createMenu(options: false)
        setMenuVisible(true)
    }

    func remove(_ sender: UIMenuController?) {
        js("removeThisHighlight()") { [weak self] removedId in
            guard let self = self, let id = removedId else { return }
            HighlightIOS.removeById(withConfiguration: self.readerConfig, highlightId: id)
        }
        setMenuVisible(false)
    }

    @objc func highlight(_ sender: UIMenuController?) {
        js("highlightString('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))')") { [weak self] highlightAndReturn in
            guard let self = self, let jsonString = highlightAndReturn else { return }
            guard let jsonData = jsonString.data(using: String.Encoding.utf8) else { return }

            do {
                let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as! NSArray
                let dic = json.firstObject as! [String: String]
                let rect = NSCoder.cgRect(for: dic["rect"]!)
                guard let startOffset = dic["startOffset"] else { return }
                guard let endOffset = dic["endOffset"] else { return }
                guard let identifier = dic["id"] else { return }

                self.createMenu(options: true)
                self.setMenuVisible(true, andRect: rect)

                // Persist
                self.js("getHTML()") { [weak self] html in
                    guard let self = self, let html = html else { return }
                    guard let bookId = (self.book.name as NSString?)?.deletingPathExtension else { return }

                    let pageNumber = self.folioReader.readerCenter?.currentPageNumber ?? 0
                    let match = HighlightIOS.MatchingHighlight(text: html, id: identifier, startOffset: startOffset, endOffset: endOffset, bookId: bookId, currentPage: pageNumber)
                    let highlight = HighlightIOS.matchHighlight(match)
                    highlight?.persist(withConfiguration: self.readerConfig)
                }
            } catch {
                print("Could not receive JSON")
            }
        }
    }
    
    @objc func highlightWithNote(_ sender: UIMenuController?) {
        js("highlightStringWithNote('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))')") { [weak self] highlightAndReturn in
            guard let self = self, let jsonString = highlightAndReturn else { return }
            guard let jsonData = jsonString.data(using: String.Encoding.utf8) else { return }

            do {
                let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as! NSArray
                let dic = json.firstObject as! [String: String]
                guard let startOffset = dic["startOffset"] else { return }
                guard let endOffset = dic["endOffset"] else { return }
                guard let identifier = dic["id"] else { return }

                self.clearTextSelection()

                self.js("getHTML()") { [weak self] html in
                    guard let self = self, let html = html else { return }
                    guard let bookId = (self.book.name as NSString?)?.deletingPathExtension else { return }

                    let pageNumber = self.folioReader.readerCenter?.currentPageNumber ?? 0
                    let match = HighlightIOS.MatchingHighlight(text: html, id: identifier, startOffset: startOffset, endOffset: endOffset, bookId: bookId, currentPage: pageNumber)
                    if let highlight = HighlightIOS.matchHighlight(match) {
                        self.folioReader.readerCenter?.presentAddHighlightNote(highlight, edit: false)
                    }
                }
            } catch {
                print("Could not receive JSON")
            }
        }
    }
    
    @objc func updateHighlightNote (_ sender: UIMenuController?) {
        js("getHighlightId()") { [weak self] highlightId in
            guard let self = self, let id = highlightId else { return }
            guard let highlightNote = HighlightIOS.getById(withConfiguration: self.readerConfig, highlightId: id) else { return }
            self.folioReader.readerCenter?.presentAddHighlightNote(highlightNote, edit: true)
        }
    }

    @objc func define(_ sender: UIMenuController?) {
        js("getSelectedText()") { [weak self] selectedText in
            guard let self = self, let text = selectedText else { return }

            self.setMenuVisible(false)
            self.clearTextSelection()

            let vc = UIReferenceLibraryViewController(term: text)
            vc.view.tintColor = self.readerConfig.tintColor
            guard let readerContainer = self.readerContainer else { return }
            readerContainer.show(vc, sender: nil)
        }
    }

    @objc func play(_ sender: UIMenuController?) {
        self.folioReader.readerAudioPlayer?.play()

        self.clearTextSelection()
    }

    func setYellow(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .yellow)
    }

    func setGreen(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .green)
    }

    func setBlue(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .blue)
    }

    func setPink(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .pink)
    }

    func setUnderline(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .underline)
    }

    func changeHighlightStyle(_ sender: UIMenuController?, style: HighlightStyle) {
        self.folioReader.currentHighlightStyle = style.rawValue

        js("setHighlightStyle('\(HighlightStyle.classForStyle(style.rawValue))')") { [weak self] updateId in
            guard let self = self, let id = updateId else { return }
            HighlightIOS.updateById(withConfiguration: self.readerConfig, highlightId: id, type: style)
        }

        //FIX: https://github.com/FolioReader/FolioReaderKit/issues/316
        setMenuVisible(false)
    }

    // MARK: - Create and show menu

    func createMenu(options: Bool) {
        guard (self.readerConfig.useReaderMenuController == true) else {
            return
        }

        isShare = options

        let colors = UIImage(readerImageNamed: "colors-marker")
        let share = UIImage(readerImageNamed: "share-marker")
        let remove = UIImage(readerImageNamed: "no-marker")
        let yellow = UIImage(readerImageNamed: "yellow-marker")
        let green = UIImage(readerImageNamed: "green-marker")
        let blue = UIImage(readerImageNamed: "blue-marker")
        let pink = UIImage(readerImageNamed: "pink-marker")
        let underline = UIImage(readerImageNamed: "underline-marker")

        let menuController = UIMenuController.shared

        let highlightItem = UIMenuItem(title: self.readerConfig.localizedHighlightMenu, action: #selector(highlight(_:)))
        let highlightNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(highlightWithNote(_:)))
        let editNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(updateHighlightNote(_:)))
        let playAudioItem = UIMenuItem(title: self.readerConfig.localizedPlayMenu, action: #selector(play(_:)))
        let defineItem = UIMenuItem(title: self.readerConfig.localizedDefineMenu, action: #selector(define(_:)))
        let colorsItem = UIMenuItem(title: "C", image: colors) { [weak self] _ in
            self?.colors(menuController)
        }
        let shareItem = UIMenuItem(title: "S", image: share) { [weak self] _ in
            self?.share(menuController)
        }
        let removeItem = UIMenuItem(title: "R", image: remove) { [weak self] _ in
            self?.remove(menuController)
        }
        let yellowItem = UIMenuItem(title: "Y", image: yellow) { [weak self] _ in
            self?.setYellow(menuController)
        }
        let greenItem = UIMenuItem(title: "G", image: green) { [weak self] _ in
            self?.setGreen(menuController)
        }
        let blueItem = UIMenuItem(title: "B", image: blue) { [weak self] _ in
            self?.setBlue(menuController)
        }
        let pinkItem = UIMenuItem(title: "P", image: pink) { [weak self] _ in
            self?.setPink(menuController)
        }
        let underlineItem = UIMenuItem(title: "U", image: underline) { [weak self] _ in
            self?.setUnderline(menuController)
        }

        var menuItems: [UIMenuItem] = []

        // menu on existing highlight
        if isShare {
            menuItems = [colorsItem, editNoteItem, removeItem]
            
            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
            
            isShare = false
        } else if isColors {
            // menu for selecting highlight color
            menuItems = [yellowItem, greenItem, blueItem, pinkItem, underlineItem]
        } else {
            // default menu
            menuItems = [highlightItem, defineItem, highlightNoteItem]

            if self.book.hasAudio || self.readerConfig.enableTTS {
                menuItems.insert(playAudioItem, at: 0)
            }

            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
        }
        
        menuController.menuItems = menuItems
    }
    
    open func setMenuVisible(_ menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRect.zero) {
        if !menuVisible && isShare || !menuVisible && isColors {
            isColors = false
            isShare = false
        }
        
        if menuVisible  {
            if !rect.equalTo(CGRect.zero) {
                UIMenuController.shared.setTargetRect(rect, in: self)
            }
        }
        
        UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
    }
    
    // MARK: - Java Script Bridge

    /// Async JavaScript evaluation - preferred method
    open func js(_ script: String, completion: ((String?) -> Void)? = nil) {
        self.evaluateJavaScript(script) { [weak self] (response, error) in
            guard self != nil else {
                completion?(nil)
                return
            }

            if let error = error {
                print("JavaScript error: \(error.localizedDescription)")
                completion?(nil)
            } else if let response = response {
                var result = String(describing: response)
                if result == "null" || result == "undefined" || result.isEmpty {
                    completion?(nil)
                } else {
                    completion?(result)
                }
            } else {
                completion?(nil)
            }
        }
    }
    
    // MARK: WebView
    
    func clearTextSelection() {
        // Forces text selection clearing
        // @NOTE: this doesn't seem to always work
        
        self.isUserInteractionEnabled = false
        self.isUserInteractionEnabled = true
    }
    
    func setupScrollDirection() {
        switch self.readerConfig.scrollDirection {
        case .vertical, .defaultVertical, .horizontalWithVerticalContent:
            scrollView.isPagingEnabled = false
            scrollView.bounces = true
        case .horizontal:
            scrollView.isPagingEnabled = true
            scrollView.bounces = false
        }
    }
}
