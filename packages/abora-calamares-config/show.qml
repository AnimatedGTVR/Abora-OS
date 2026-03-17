import QtQuick 2.15

Rectangle {
    width: 800
    height: 600
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0B1F38" }
        GradientStop { position: 1.0; color: "#1D4C82" }
    }

    Text {
        anchors.centerIn: parent
        text: "Abora OS"
        color: "#eaf4ff"
        font.pixelSize: 46
        font.bold: true
    }
}
