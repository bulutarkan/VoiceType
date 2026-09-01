import Cocoa

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear All", target: nil, action: nil)

    private var filteredItems: [HistoryItem] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType History"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 400)
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

        let title = NSTextField(labelWithString: "History")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.frame = NSRect(x: 28, y: 466, width: 220, height: 30)
        title.autoresizingMask = [.minYMargin]
        effect.addSubview(title)

        countLabel.font = .systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.frame = NSRect(x: 29, y: 446, width: 300, height: 17)
        countLabel.autoresizingMask = [.minYMargin]
        effect.addSubview(countLabel)

        searchField.placeholderString = "Search transcripts, apps, or type"
        searchField.delegate = self
        searchField.frame = NSRect(x: 420, y: 458, width: 312, height: 28)
        searchField.autoresizingMask = [.minXMargin, .minYMargin]
        effect.addSubview(searchField)

        let scroll = NSScrollView(frame: NSRect(x: 28, y: 70, width: 704, height: 360))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        textColumn.title = "Transcript"
        textColumn.width = 430
        textColumn.minWidth = 260
        tableView.addTableColumn(textColumn)

        let appColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        appColumn.title = "App"
        appColumn.width = 125
        tableView.addTableColumn(appColumn)

        let timeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeColumn.title = "Time"
        timeColumn.width = 120
        tableView.addTableColumn(timeColumn)

        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 32
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(copySelected)
        tableView.target = self
        scroll.documentView = tableView
        effect.addSubview(scroll)

        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 28, y: 24, width: 82, height: 30)
        copyButton.autoresizingMask = [.maxYMargin]
        effect.addSubview(copyButton)

        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.bezelStyle = .rounded
        deleteButton.frame = NSRect(x: 118, y: 24, width: 82, height: 30)
        deleteButton.autoresizingMask = [.maxYMargin]
        effect.addSubview(deleteButton)

        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 632, y: 24, width: 100, height: 30)
        clearButton.autoresizingMask = [.minXMargin, .maxYMargin]
        effect.addSubview(clearButton)

        updateButtons()
    }

    @objc private func historyChanged() { reload() }

    private func reload() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = TranscriptionHistory.shared.items
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter {
                $0.text.lowercased().contains(query) ||
                ($0.appName?.lowercased().contains(query) ?? false) ||
                ($0.kind?.lowercased().contains(query) ?? false)
            }
        }
        countLabel.stringValue = "\(items.count) saved transcription\(items.count == 1 ? "" : "s") • newest first"
        tableView.reloadData()
        updateButtons()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count, let tableColumn else { return nil }
        let item = filteredItems[row]
        let identifier = tableColumn.identifier
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: identifier.rawValue == "text" ? 12 : 11, weight: .regular)
        label.textColor = identifier.rawValue == "text" ? .labelColor : .secondaryLabelColor
        label.frame = NSRect(x: 7, y: 6, width: max(20, tableColumn.width - 14), height: 20)
        label.autoresizingMask = [.width]

        switch identifier.rawValue {
        case "text": label.stringValue = item.text.replacingOccurrences(of: "\n", with: " ")
        case "app": label.stringValue = [item.kind, item.appName].compactMap { $0 }.joined(separator: " • ")
        case "time": label.stringValue = item.timeString
        default: break
        }
        cell.addSubview(label)
        cell.textField = label
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    private func updateButtons() {
        let hasSelection = tableView.selectedRow >= 0 && tableView.selectedRow < filteredItems.count
        copyButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        clearButton.isEnabled = !TranscriptionHistory.shared.items.isEmpty
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
