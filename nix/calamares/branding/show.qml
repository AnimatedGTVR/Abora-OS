import QtQuick 2.15

Rectangle {
    width: 800
    height: 600
    color: "#0B223A"

    Image {
        anchors.centerIn: parent
        source: "abora-logo.png"
        fillMode: Image.PreserveAspectFit
        width: 360
        height: 269
    }
}
