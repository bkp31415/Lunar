//
//  ScrollableValueController.swift
//  Lunar
//
//  Created by Alin on 25/12/2017.
//  Copyright © 2017 Alin. All rights reserved.
//

import Cocoa
import Combine
import Defaults

class ScrollableContrast: NSView {
    @IBOutlet var label: NSTextField!
    @IBOutlet var minValue: ScrollableTextField!
    @IBOutlet var maxValue: ScrollableTextField!
    @IBOutlet var currentValue: ScrollableTextField!

    @IBOutlet var minValueCaption: ScrollableTextFieldCaption!
    @IBOutlet var maxValueCaption: ScrollableTextFieldCaption!
    @IBOutlet var currentValueCaption: ScrollableTextFieldCaption!

    @IBOutlet var lockButton: LockButton!

    var minObserver: Cancellable?
    var maxObserver: Cancellable?
    var onMinValueChanged: ((Int) -> Void)?
    var onMaxValueChanged: ((Int) -> Void)?
    var onCurrentValueChanged: ((Int) -> Void)?
    var disabled = false {
        didSet {
            minValue.isEnabled = !disabled
            maxValue.isEnabled = !disabled
        }
    }

    weak var display: Display? {
        didSet {
            if let d = display {
                update(from: d)
            }
        }
    }

    var name: String! {
        didSet {
            label?.stringValue = name
        }
    }

    var displayMinValue: Int {
        get {
            display?.minContrast.intValue ?? 0
        }
        set {
            cancelTask(SCREEN_WAKE_ADAPTER_TASK_KEY)
            display?.minContrast = newValue.ns
        }
    }

    var displayMaxValue: Int {
        get {
            display?.maxContrast.intValue ?? 100
        }
        set {
            cancelTask(SCREEN_WAKE_ADAPTER_TASK_KEY)
            display?.maxContrast = newValue.ns
        }
    }

    var displayValue: Int {
        get {
            display?.contrast.intValue ?? 50
        }
        set {
            cancelTask(SCREEN_WAKE_ADAPTER_TASK_KEY)
            display?.contrast = newValue.ns
        }
    }

    var displayObservers = [String: AnyCancellable]()

    func addObserver(_ display: Display) {
        display.$contrast.receive(on: dataPublisherQueue).sink { [weak self] newContrast in
            guard let display = self?.display, display.id != GENERIC_DISPLAY_ID else { return }
            let minContrast = display.minContrast.uint8Value
            let maxContrast = display.maxContrast.uint8Value

            let newContrast = cap(newContrast.uint8Value, minVal: minContrast, maxVal: maxContrast)
            mainThread {
                self?.currentValue?.stringValue = String(newContrast)
            }
        }.store(in: &displayObservers, for: "contrast")
    }

    func update(from display: Display) {
        minValue?.intValue = Int32(displayMinValue)
        minValue?.upperLimit = (displayMaxValue - 1).d
        maxValue?.intValue = Int32(displayMaxValue)
        maxValue?.lowerLimit = (displayMinValue + 1).d
        currentValue?.intValue = Int32(displayValue)
        currentValue?.lowerLimit = displayMinValue.d
        currentValue?.upperLimit = displayMaxValue.d

        if let button = lockButton {
            button.setup(display.lockedContrast)
            if display.lockedContrast {
                button.state = .on
            } else {
                button.state = .off
            }
        }

        addObserver(display)
    }

    deinit {
        #if DEBUG
            log.verbose("START DEINIT")
            defer { log.verbose("END DEINIT") }
        #endif
        for observer in displayObservers.values {
            observer.cancel()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        lockButton?.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        lockButton?.setup()
    }

    @IBAction func toggleLock(_ sender: LockButton) {
        switch sender.state {
        case .on:
            sender.bg = lockButtonBgOn
            display?.lockedContrast = true
        case .off:
            sender.bg = lockButtonBgOff
            display?.lockedContrast = false
        default:
            return
        }
        displayController.adaptBrightness()
    }

    func setup() {
        minValue?.onValueChangedInstant = minValue?.onValueChangedInstant ?? onMinValueChanged
        minValue?.onValueChanged = minValue?.onValueChanged ?? { [weak self] (value: Int) in
            guard let self = self else { return }

            self.maxValue?.lowerLimit = (value + 1).d
            self.currentValue?.lowerLimit = value.d
            self.currentValue.integerValue = max(self.currentValue.integerValue, value)
            if self.display != nil {
                self.displayMinValue = value
            }
        }
        maxValue?.onValueChangedInstant = maxValue?.onValueChangedInstant ?? onMaxValueChanged
        maxValue?.onValueChanged = maxValue?.onValueChanged ?? { [weak self] (value: Int) in
            guard let self = self else { return }

            self.minValue?.upperLimit = (value - 1).d
            self.currentValue?.upperLimit = value.d
            self.currentValue.integerValue = min(self.currentValue.integerValue, value)
            if self.display != nil {
                self.displayMaxValue = value
            }
        }

        currentValue?.onValueChangedInstant = currentValue?.onValueChangedInstant ?? onCurrentValueChanged
        currentValue?.onValueChanged = currentValue?.onValueChanged ?? { [weak self] (value: Int) in
            if self?.display != nil {
                self?.displayValue = value
            }
        }

        minValue?.caption = minValue?.caption ?? minValueCaption
        maxValue?.caption = maxValue?.caption ?? maxValueCaption
        currentValue?.caption = currentValue?.caption ?? currentValueCaption
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        setup()
    }
}
