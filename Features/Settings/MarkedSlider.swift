import AppKit
import SwiftUI

struct MarkedSlider: NSViewRepresentable {
    @Binding var value: Int
    var marks: [Int]
    var accessibilityTitle: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.sliderType = .linear
        slider.minValue = 0
        slider.maxValue = Double(max(marks.count - 1, 0))
        slider.numberOfTickMarks = max(marks.count, 2)
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityTitle(accessibilityTitle)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.marks = marks
        context.coordinator.onChange = { value = $0 }
        slider.minValue = 0
        slider.maxValue = Double(max(marks.count - 1, 0))
        slider.numberOfTickMarks = max(marks.count, 2)
        slider.setAccessibilityTitle(accessibilityTitle)
        let index = DurationMarks.index(of: value, in: marks)
        if Int(slider.doubleValue.rounded()) != index {
            slider.doubleValue = Double(index)
        }
        slider.setAccessibilityValue(marks.indices.contains(index) ? "\(marks[index])" : "\(value)")
    }

    final class Coordinator: NSObject {
        var marks: [Int] = []
        var onChange: ((Int) -> Void)?

        @objc func changed(_ sender: NSSlider) {
            guard !marks.isEmpty else { return }
            let index = min(max(0, Int(sender.doubleValue.rounded())), marks.count - 1)
            onChange?(marks[index])
        }
    }
}
