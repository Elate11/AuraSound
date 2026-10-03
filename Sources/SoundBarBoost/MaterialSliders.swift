import SwiftUI

/// Minimalistic slider used throughout the app
public struct M3ExpSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let icon: String
    let title: String
    let valueText: String
    let activeColor: Color
    let onActiveColor: Color
    let activeGradient: LinearGradient?

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        icon: String,
        title: String,
        valueText: String,
        activeColor: Color = Color.white,
        onActiveColor: Color = Color.black,
        activeGradient: LinearGradient? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.icon = icon
        self.title = title
        self.valueText = valueText
        self.activeColor = activeColor
        self.onActiveColor = onActiveColor
        self.activeGradient = activeGradient
    }

    private var binding: Binding<Double> {
        if let step = step {
            return Binding<Double>(
                get: { value },
                set: { newVal in
                    let stepped = (newVal / step).rounded() * step
                    value = min(max(range.lowerBound, stepped), range.upperBound)
                }
            )
        } else {
            return $value
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(activeColor)
                Text(title)
                    .foregroundColor(activeColor)
                Spacer()
                Text(valueText)
                    .foregroundColor(activeColor)
                    .font(.system(.caption, design: .monospaced))
            }
            Slider(value: binding, in: range)
        }
        .padding(.vertical, 4)
    }
}
