import AppIntents
import SwiftUI
import WidgetKit

/// "I'm up" in Control Center, on the Lock Screen or on the Action button: the day starts now and
/// its meals move with it, without opening the app.
struct StartDayControl: ControlWidget {
    static let kind = "com.orhay.dietflow.control.startDay"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: WidgetStartDayIntent()) {
                Label {
                    Text("control.startDay.label")
                } icon: {
                    Image(systemName: "sunrise.fill")
                }
            }
        }
        .displayName("control.startDay.name")
        .description("control.startDay.description")
    }
}

/// "Eaten" in Control Center: marks the meal that is on now, or the next one today.
struct MarkMealEatenControl: ControlWidget {
    static let kind = "com.orhay.dietflow.control.markEaten"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MarkMealDoneIntent()) {
                Label {
                    Text("control.markEaten.label")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
        .displayName("control.markEaten.name")
        .description("control.markEaten.description")
    }
}
