import Cocoa

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl()
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyView = NSView(frame: .zero)
    private let emptyIcon = NSImageView(frame: .zero)
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptySubtitle = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear All", target: nil, action: nil)
    private let previewBox = NSBox(frame: .zero)

    private var filteredItems: [HistoryItem] = []
    private var selectedKind: String? = nil // nil = all

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType History"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 660, height: 440)
        window.center()
        super.init(window: window)
        window.delegate = self
        setupView()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged), name: .historyDidUpdate, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        reload()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func setupView() {
        guard let content = window?.contentView else { return }

        let effect = NSVisualEffectView(frame: content.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        content.addSubview(effect)

        // Header background with subtle separator
        let header = NSView(frame: NSRect(x: 0, y: content.bounds.height - 92, width: content.bounds.width, height: 92))
        header.autoresizingMask = [.width, .minYMargin]
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor
        effect.addSubview(header)

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: header.bounds.width, height: 0.5))
        sep.autoresizingMask = [.width]
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        header.addSubview(sep)

        let title = NSTextField(labelWithString: "History")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.frame = NSRect(x: 28, y: 52, width: 220, height: 30)
        title.autoresizingMask = [.minYMargin]
        header.addSubview(title)

        countLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.frame = NSRect(x: 29, y: 30, width: 340, height: 17)
        countLabel.autoresizingMask = [.minYMargin]
        header.addSubview(countLabel)

        // Search field — modern rounded
        searchField.placeholderString = "Search transcripts, apps, or type"
        searchField.delegate = self
        searchField.frame = NSRect(x: header.bounds.width - 320, y: 46, width: 292, height: 28)
        searchField.autoresizingMask = [.minXMargin, .minYMargin]
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 8
        header.addSubview(searchField)

        // Filter segmented — All / Dictation / Command
        filterControl.segmentCount = 3
        filterControl.setLabel("All", forSegment: 0)
        filterControl.setLabel("Dictation", forSegment: 1)
        filterControl.setLabel("Command", forSegment: 2)
        filterControl.selectedSegment = 0
        filterControl.segmentStyle = .rounded
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        filterControl.frame = NSRect(x: header.bounds.width - 320, y: 14, width: 292, height: 24)
        filterControl.autoresizingMask = [.minXMargin, .minYMargin]
        header.addSubview(filterControl)

        // Scroll
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 72, width: 732, height: 368))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay

        let textColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card"))
        textColumn.title = ""
        textColumn.width = 732
        textColumn.minWidth = 400
        textColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(textColumn)

        // No header — we use card rows
        tableView.headerView = nil
        tableView.rowHeight = 68
        tableView.intercellSpacing = NSSize(width: 0, height: 10)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(copySelected)
        tableView.target = self
        scroll.documentView = tableView
        effect.addSubview(scroll)

        // Empty state — centered illustration (shown when filtered empty)
        emptyView.frame = scroll.frame
        emptyView.autoresizingMask = [.width, .height]
        emptyView.isHidden = true
        effect.addSubview(emptyView)

        emptyIcon.frame = NSRect(x: (emptyView.bounds.width - 56)/2, y: 210, width: 56, height: 56)
        emptyIcon.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        emptyIcon.image = NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 42, weight: .light))
        emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyView.addSubview(emptyIcon)

        emptyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        emptyTitle.textColor = .secondaryLabelColor
        emptyTitle.alignment = .center
        emptyTitle.stringValue = "No transcripts found"
        emptyTitle.frame = NSRect(x: 0, y: 178, width: emptyView.bounds.width, height: 20)
        emptyTitle.autoresizingMask = [.width]
        emptyView.addSubview(emptyTitle)

        emptySubtitle.font = .systemFont(ofSize: 12, weight: .regular)
        emptySubtitle.textColor = .tertiaryLabelColor
        emptySubtitle.alignment = .center
        emptySubtitle.stringValue = "Try a different search or press ⌥Space to start dictating."
        emptySubtitle.frame = NSRect(x: 0, y: 156, width: emptyView.bounds.width, height: 18)
        emptySubtitle.autoresizingMask = [.width]
        emptyView.addSubview(emptySubtitle)

        // Preview box at bottom? keep buttons row
        // Button bar — frosted
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: content.bounds.width, height: 56))
        bar.autoresizingMask = [.width, .maxYMargin]
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        effect.addSubview(bar)

        let barSep = NSView(frame: NSRect(x: 0, y: 55.5, width: bar.bounds.width, height: 0.5))
        barSep.autoresizingMask = [.width, .minYMargin]
        barSep.wantsLayer = true
        barSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bar.addSubview(barSep)

        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = ""
        copyButton.font = .systemFont(ofSize: 12, weight: .medium)
        copyButton.frame = NSRect(x: 24, y: 14, width: 88, height: 30)
        copyButton.autoresizingMask = [.maxYMargin]
        bar.addSubview(copyButton)

        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.bezelStyle = .rounded
        deleteButton.font = .systemFont(ofSize: 12, weight: .medium)
        deleteButton.frame = NSRect(x: 120, y: 14, width: 88, height: 30)
        deleteButton.autoresizingMask = [.maxYMargin]
        bar.addSubview(deleteButton)

        clearButton.image = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: nil)
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearButton.bezelStyle = .rounded
        clearButton.font = .systemFont(ofSize: 12, weight: .medium)
        clearButton.frame = NSRect(x: bar.bounds.width - 118, y: 14, width: 102, height: 30)
        clearButton.autoresizingMask = [.minXMargin, .maxYMargin]
        bar.addSubview(clearButton)

        updateButtons()
    }

    @objc private func historyChanged() { reload() }

    @objc private func filterChanged() {
        switch filterControl.selectedSegment {
        case 1: selectedKind = "dictation"
        case 2: selectedKind = "command"
        default: selectedKind = nil
        }
        reload()
    }

    private func reload() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = TranscriptionHistory.shared.items
        filteredItems = items.filter { item in
            if let kind = selectedKind, item.kind != kind { return false }
            if query.isEmpty { return true }
            return item.text.lowercased().contains(query) ||
                (item.appName?.lowercased().contains(query) ?? false) ||
                (item.kind?.lowercased().contains(query) ?? false)
        }
        let total = items.count
        countLabel.stringValue = "\(total) saved • \(filteredItems.count) shown • newest first"
        tableView.reloadData()
        emptyView.isHidden = !filteredItems.isEmpty
        tableView.isHidden = filteredItems.isEmpty
        updateButtons()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count else { return nil }
        let item = filteredItems[row]
        let isSelected = tableView.selectedRow == row

        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? 700, height: 68))
        cell.wantsLayer = true

        // Card container
        let card = NSBox(frame: NSRect(x: 0, y: 4, width: cell.bounds.width, height: 60))
        card.autoresizingMask = [.width]
        card.boxType = .custom
        card.borderWidth = 0.6
        card.borderColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.45) : VTDesign.Color.cardBorder
        card.fillColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        card.cornerRadius = 12
        card.wantsLayer = true
        if isSelected {
            card.shadow = VTDesign.Shadow.cardShadow()
        }
        cell.addSubview(card)

        // Kind icon pill
        let iconSize: CGFloat = 28
        let iconView = NSView(frame: NSRect(x: 14, y: (60 - iconSize)/2, width: iconSize, height: iconSize))
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = iconSize/2
        if item.kind == "command" {
            iconView.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.16).cgColor
        } else {
            iconView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.13).cgColor
        }
        card.addSubview(iconView)

        let sym = item.kind == "command" ? "sparkles" : "mic.fill"
        let icon = NSImageView(frame: NSRect(x: 6, y: 6, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        icon.contentTintColor = item.kind == "command" ? NSColor.systemPurple : NSColor.systemBlue
        iconView.addSubview(icon)

        // Text preview — two lines max
        let textLabel = NSTextField(labelWithString: "")
        textLabel.font = .systemFont(ofSize: 13, weight: .regular)
        textLabel.textColor = .labelColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        // card width minus icon and right meta
        let rightMetaW: CGFloat = 150
        textLabel.frame = NSRect(x: iconView.frame.maxX + 12, y: 30, width: max(20, card.bounds.width - iconView.frame.maxX - 12 - rightMetaW - 10), height: 18)
        textLabel.autoresizingMask = [.width]
        textLabel.stringValue = item.text.replacingOccurrences(of: "\n", with: " ")
        card.addSubview(textLabel)

        let sub = NSTextField(labelWithString: "")
        sub.font = .systemFont(ofSize: 11, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: textLabel.frame.minX, y: 12, width: textLabel.frame.width, height: 16)
        sub.autoresizingMask = [.width]
        let appPart = [item.kind?.capitalized, item.appName].compactMap { $0 }.joined(separator: " • ")
        sub.stringValue = appPart.isEmpty ? "—" : appPart
        card.addSubview(sub)

        // Time + copy quick button
        let time = NSTextField(labelWithString: VTTime.relativeString(from: item.date))
        time.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        time.textColor = .tertiaryLabelColor
        time.alignment = .right
        time.frame = NSRect(x: card.bounds.width - 120, y: 30, width: 108, height: 16)
        time.autoresizingMask = [.minXMargin]
        card.addSubview(time)

        // Hover copy button — always visible for now, subtle
        let copyBtn = NSButton(frame: NSRect(x: card.bounds.width - 62, y: 10, width: 50, height: 20))
        copyBtn.autoresizingMask = [.minXMargin]
        copyBtn.bezelStyle = .inline
        copyBtn.isBordered = false
        copyBtn.title = ""
        copyBtn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyBtn.contentTintColor = .secondaryLabelColor
        copyBtn.target = self
        copyBtn.action = #selector(copyRow(_:))
        copyBtn.tag = row
        card.addSubview(copyBtn)

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        // re-render for selection highlight
        tableView.reloadData()
    }

    private func updateButtons() {
        let hasSelection = tableView.selectedRow >= 0 && tableView.selectedRow < filteredItems.count
        copyButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        clearButton.isEnabled = !TranscriptionHistory.shared.items.isEmpty
        // subtle style: destructive tint for delete when enabled
        deleteButton.contentTintColor = hasSelection ? .systemRed : nil
    }

    @objc private func copyRow(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < filteredItems.count else { return }
        TextInjector.copyToPasteboard(filteredItems[row].text)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        // visual feedback: flash contentTint
        sender.contentTintColor = .systemBlue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { sender.contentTintColor = .secondaryLabelColor }
    }

    @objc private func copySelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return }
        TextInjector.copyToPasteboard(filteredItems[row].text)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return }
        TranscriptionHistory.shared.delete(id: filteredItems[row].id)
    }

    @objc private func clearAll() {
        guard !TranscriptionHistory.shared.items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear transcription history?"
        alert.informativeText = "This removes all saved transcript text from VoiceType on this Mac."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        TranscriptionHistory.shared.clear()
    }
}

extension HistoryWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
