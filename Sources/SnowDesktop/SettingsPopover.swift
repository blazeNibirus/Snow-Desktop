import AppKit
import ServiceManagement
import SnowCore

private final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?
    init(title: String, handler: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; actionHandler = handler; bezelStyle = .inline
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func invoke() { actionHandler?() }
}

final class SettingsPopover: NSViewController {
    private let tracker: WindowTracker
    private let clear: () -> Void
    private var previewView: SnowView!
    private var intensitySlider: NSSlider!
    private var speedSlider: NSSlider!
    private var intensityLabel: NSTextField!
    private var speedLabel: NSTextField!
    private var brightness: NSSlider!
    private var warmth: NSSlider!
    private var colorTarget = 0
    private var permissionRow: NSStackView!
    private var statusLabel: NSTextField!
    private var loginSwitch: NSSwitch!
    private var saverSwitch: NSSwitch!
    private var dockMode: NSSegmentedControl!
    private var controls: [String: NSSwitch] = [:]

    init(tracker: WindowTracker, clear: @escaping () -> Void) {
        self.tracker = tracker; self.clear = clear
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        return field
    }
    private func row(_ items: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: items); stack.orientation = .horizontal
        stack.alignment = .centerY; stack.spacing = spacing
        return stack
    }
    private func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.init(1), for: .horizontal); return v }
    private func toggle(_ title: String, key: String, value: Bool) -> NSStackView {
        let control = NSSwitch(); control.state = value ? .on : .off
        control.identifier = NSUserInterfaceItemIdentifier(key); control.target = self; control.action = #selector(toggleChanged(_:))
        controls[key] = control
        return row([label(title), spacer(), control])
    }
    private func slider(value: Double, min: Double = 0, max: Double = 1, action: Selector) -> NSSlider {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true; slider.controlSize = .small
        return slider
    }
    private func separator() -> NSView {
        let line = NSBox(); line.boxType = .separator; return line
    }
    override func loadView() {
        let p = Settings.shared.value
        let root = NSVisualEffectView(); root.material = .popover; root.blendingMode = .behindWindow; root.state = .active
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 17, left: 18, bottom: 14, right: 18)
        let title = label("Snow Desktop", size: 16, weight: .semibold)
        let snowIcon = NSImageView(image: NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)!)
        snowIcon.contentTintColor = .systemCyan
        let header = row([snowIcon, title, spacer(), controls["enabled"] ?? NSView()])
        let power = NSSwitch(); power.state = p.enabled ? .on : .off
        power.identifier = .init("enabled"); power.target = self; power.action = #selector(toggleChanged(_:)); controls["enabled"] = power
        header.addArrangedSubview(power)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(label("Тихая зима на вашем Mac", size: 11, secondary: true))

        let engine = SnowEngine(width: 280, height: 78)
        engine.accumulationEnabled = false; engine.particleLimit = 120
        engine.intensity = Intensity(rawValue: p.intensity) ?? .light; engine.speed = p.speed
        for i in 0..<24 {
            engine.addParticle(Particle(x: Double((i * 73) % 280), y: Double((i * 31) % 78),
                vy: 11 + Double(i % 12), radius: 0.6 + Double(i % 5) * 0.16,
                opacity: 0.35 + Double(i % 6) * 0.09, phase: Double(i)))
        }
        previewView = SnowView(frame: CGRect(x: 0, y: 0, width: 280, height: 78), engine: engine, preview: true)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.heightAnchor.constraint(equalToConstant: 78).isActive = true
        previewView.beforeFrame = { [weak self] in
            guard let preview = self?.previewView else { return }
            let count = [15, 30, 52][Settings.shared.value.intensity]
            while preview.engine.particles.count < count {
                preview.engine.addParticle(Particle(x: Double.random(in: 0...280), y: -3,
                    vy: Double.random(in: 11...23), radius: Double.random(in: 0.6...1.35),
                    opacity: Double.random(in: 0.35...0.85), phase: Double.random(in: 0...6.28)))
            }
        }
        stack.addArrangedSubview(previewView)
        stack.addArrangedSubview(label("Предпросмотр · изменения видны сразу", size: 10, secondary: true))
        intensityLabel = label("")
        stack.addArrangedSubview(row([label("Интенсивность", weight: .medium), spacer(), intensityLabel]))
        intensitySlider = slider(value: Double(p.intensity), min: 0, max: 2, action: #selector(intensityChanged))
        intensitySlider.numberOfTickMarks = 3; intensitySlider.allowsTickMarkValuesOnly = true
        intensitySlider.setAccessibilityLabel("Интенсивность снега: три уровня")
        stack.addArrangedSubview(intensitySlider)
        speedLabel = label("")
        stack.addArrangedSubview(row([label("Скорость", weight: .medium), spacer(), speedLabel]))
        speedSlider = slider(value: p.speed, min: 0.35, max: 2.5, action: #selector(speedChanged))
        speedSlider.setAccessibilityLabel("Скорость падения снега")
        stack.addArrangedSubview(speedSlider)
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(toggle("Сугробы на окнах", key: "windows", value: p.onWindows))
        stack.addArrangedSubview(toggle("Сугробы на Dock", key: "dock", value: p.onDock))
        dockMode = NSSegmentedControl(labels: ["Только Dock", "Вся ширина"], trackingMode: .selectOne, target: self, action: #selector(dockModeChanged))
        dockMode.selectedSegment = p.fullWidthDock ? 1 : 0; dockMode.controlSize = .small
        stack.addArrangedSubview(dockMode)
        let permissionText = label("Для точных границ и увеличения Dock нужен «Универсальный доступ».", size: 10, secondary: true)
        let grant = ActionButton(title: "Разрешить…") { [weak self] in self?.tracker.requestDockAccess() }
        permissionRow = row([permissionText, grant]); stack.addArrangedSubview(permissionRow)
        stack.addArrangedSubview(separator())
        let target = NSSegmentedControl(labels: ["Снежинки", "Сугробы"], trackingMode: .selectOne, target: self, action: #selector(colorTargetChanged(_:)))
        target.selectedSegment = 0; target.controlSize = .small
        stack.addArrangedSubview(row([label("Цвет", weight: .medium), spacer(), target]))
        brightness = slider(value: p.falling.brightness, action: #selector(colorChanged))
        brightness.setAccessibilityLabel("Белизна выбранного снега")
        warmth = slider(value: p.falling.warmth, min: -1, max: 1, action: #selector(colorChanged))
        warmth.setAccessibilityLabel("Оттенок: холодный или тёплый")
        stack.addArrangedSubview(row([label("Темнее", size: 10, secondary: true), brightness, label("Белее", size: 10, secondary: true)]))
        stack.addArrangedSubview(row([label("Холоднее", size: 10, secondary: true), warmth, label("Теплее", size: 10, secondary: true)]))
        stack.addArrangedSubview(separator())
        let loginRow = toggle("Запускать при входе", key: "login", value: Settings.shared.startsAtLogin)
        loginSwitch = controls["login"]; stack.addArrangedSubview(loginRow)
        let saverRow = toggle("Снег при блокировке", key: "saver", value: FileManager.default.fileExists(atPath: Settings.shared.saverURL.path))
        saverSwitch = controls["saver"]; stack.addArrangedSubview(saverRow)
        stack.addArrangedSubview(label("Через системную заставку, без накопления. Поверх поля пароля macOS снег не отображается.", size: 10, secondary: true))
        stack.addArrangedSubview(ActionButton(title: "Выбрать заставку в настройках…") { Settings.shared.openSaverSettings() })
        statusLabel = label("", size: 10, secondary: true); stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(row([
            ActionButton(title: "Убрать сугробы") { [weak self] in self?.clear() }, spacer(),
            ActionButton(title: "Выйти") { NSApp.terminate(nil) }
        ]))
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.documentView = stack
        root.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), stack.widthAnchor.constraint(equalToConstant: 316)
        ])
        for item in stack.arrangedSubviews {
            item.translatesAutoresizingMaskIntoConstraints = false
            item.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
        }
        root.frame = CGRect(x: 0, y: 0, width: 316, height: min(730, (NSScreen.main?.visibleFrame.height ?? 850) - 50))
        view = root
        updateLabels()
    }
    override func viewWillAppear() {
        super.viewWillAppear()
        permissionRow.isHidden = tracker.hasDockAccess || !Settings.shared.value.onDock
        loginSwitch.state = Settings.shared.startsAtLogin ? .on : .off
        previewView.applyPreferences(); previewView.start()
        statusLabel.stringValue = "Память: \(Diagnostics.memoryMB()) МБ · бюджет 0,5%: \(Diagnostics.budgetMB) МБ"
    }
    override func viewDidDisappear() { super.viewDidDisappear(); previewView.stop() }
    private func updateLabels() {
        let p = Settings.shared.value
        intensityLabel.stringValue = ["Лёгкий", "Умеренный", "Густой"][p.intensity]
        speedLabel.stringValue = String(format: "%.2f×", p.speed)
        previewView?.applyPreferences()
        dockMode?.isEnabled = p.onDock
    }
    @objc private func intensityChanged() {
        Settings.shared.value.intensity = Int(intensitySlider.doubleValue.rounded())
        // Re-seed the small sample so a density change is visible immediately.
        let e = previewView.engine; e.clear()
        let count = [15, 30, 52][Settings.shared.value.intensity]
        for i in 0..<count {
            e.addParticle(Particle(x: Double((i * 73) % 280), y: Double((i * 31) % 78), vy: 11 + Double(i % 12),
                radius: 0.6 + Double(i % 5) * 0.16, opacity: 0.35 + Double(i % 6) * 0.09, phase: Double(i)))
        }
        updateLabels()
    }
    @objc private func speedChanged() { Settings.shared.value.speed = speedSlider.doubleValue; updateLabels() }
    @objc private func dockModeChanged() { Settings.shared.value.fullWidthDock = dockMode.selectedSegment == 1 }
    @objc private func colorTargetChanged(_ sender: NSSegmentedControl) {
        colorTarget = sender.selectedSegment
        let appearance = colorTarget == 0 ? Settings.shared.value.falling : Settings.shared.value.settled
        brightness.doubleValue = appearance.brightness; warmth.doubleValue = appearance.warmth
    }
    @objc private func colorChanged() {
        let color = SnowAppearance(brightness: brightness.doubleValue, warmth: warmth.doubleValue)
        if colorTarget == 0 { Settings.shared.value.falling = color }
        else { Settings.shared.value.settled = color }
        previewView.applyPreferences()
    }
    @objc private func toggleChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        switch sender.identifier?.rawValue {
        case "enabled": Settings.shared.value.enabled = enabled
        case "windows": Settings.shared.value.onWindows = enabled
        case "dock":
            Settings.shared.value.onDock = enabled
            permissionRow.isHidden = tracker.hasDockAccess || !enabled
            dockMode.isEnabled = enabled
        case "login":
            do { try Settings.shared.setLogin(enabled) }
            catch {
                sender.state = Settings.shared.startsAtLogin ? .on : .off
                statusLabel.stringValue = "Автозапуск: \(error.localizedDescription)"
                SMAppService.openSystemSettingsLoginItems()
            }
        case "saver":
            do {
                try Settings.shared.installSaver(enabled)
                statusLabel.stringValue = enabled ? "Установлена. Выберите Snow Desktop в настройках заставки." : "Заставка Snow Desktop удалена."
            } catch { sender.state = enabled ? .off : .on; statusLabel.stringValue = error.localizedDescription }
        default: break
        }
    }
}
