import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "user.duolingo"
  ipcTarget: "user.duolingo"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var userData: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accentColor: Color.accent || "#58cc02"
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property int selectedCourseIndex: 0
  property bool settingsOpen: false

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function launchDuolingo() {
    if (root.bar) {
      root.bar.run(Quickshell.env("HOME") + "/.config/omarchy/plugins/user.duolingo/bin/launch-duo.sh")
    }
    root.close()
  }

  function refresh() {
    if (root.hostWidget && root.hostWidget.refresh) root.hostWidget.refresh()
  }

  function saveSettings(newUsername) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.username = newUsername.trim()
    root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function launch(): void { root.launchDuolingo() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight + Style.space(28))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: root.launchDuolingo()
      onMoveRequested: function(dx, dy) {
        if (!root.userData || !root.userData.courses) return
        var count = root.userData.courses.length
        if (count === 0) return
        if (dy > 0) root.selectedCourseIndex = (root.selectedCourseIndex + 1) % count
        else if (dy < 0) root.selectedCourseIndex = (root.selectedCourseIndex - 1 + count) % count
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.settingsOpen = !root.settingsOpen
        else if (t === "q" || t === "Q") root.close()
      }

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(14)

        // 1. Header / Hero with official mascot
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          Image {
            source: (root.userData && root.userData.avatar) ? root.userData.avatar : Qt.resolvedUrl("assets/duo.png")
            width: Style.space(42)
            height: Style.space(42)
            fillMode: Image.PreserveAspectFit
            Layout.alignment: Qt.AlignVCenter
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              text: root.userData && root.userData.valid ? root.userData.fullname : "Duolingo Tracker"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              text: root.userData && root.userData.valid ? ("@" + root.userData.username) : "Looking for session…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Streak Pill
          Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: streakRow.implicitWidth + Style.space(16)
            implicitHeight: Style.space(32)
            radius: Style.cornerRadius || 8
            color: root.userData && root.userData.streakExtendedToday ? Qt.rgba(0.34, 0.8, 0.01, 0.2) : Qt.rgba(1.0, 0.4, 0.0, 0.2)

            RowLayout {
              id: streakRow
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "🔥"
                font.pixelSize: Style.font.body
              }
              Text {
                text: root.userData && root.userData.valid ? String(root.userData.streak) : "0"
                color: root.userData && root.userData.streakExtendedToday ? root.accentColor : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
          }
        }

        // 2. Status Banner
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: statusText.implicitHeight + Style.space(16)
          radius: Style.cornerRadius || 8
          color: {
            if (!root.userData || !root.userData.valid) return Qt.rgba(0.5, 0.5, 0.5, 0.15)
            if (root.userData.streakExtendedToday) return Qt.rgba(0.34, 0.8, 0.01, 0.15)
            return Qt.rgba(1.0, 0.2, 0.2, 0.15)
          }

          Text {
            id: statusText
            anchors.centerIn: parent
            anchors.margins: Style.space(8)
            text: {
              if (!root.userData || !root.userData.valid) return "⚠️ Connecting to Duolingo account…"
              if (root.userData.streakExtendedToday) return "🎉 Streak safe for today! Great job continuing your habit."
              return "🔥 Daily lesson pending! Practice today to keep your streak alive."
            }
            color: {
              if (!root.userData || !root.userData.valid) return root.dim
              if (root.userData.streakExtendedToday) return root.accentColor
              return root.urgent
            }
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }

        // 3. Courses Breakdown Header
        RowLayout {
          Layout.fillWidth: true
          visible: root.userData && root.userData.valid && root.userData.courses.length > 0

          Text {
            text: "ENROLLED COURSES (" + (root.userData ? root.userData.courses.length : 0) + ")"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            Layout.fillWidth: true
          }

          Text {
            text: "TOTAL: " + (root.userData ? Model.formatNumber(root.userData.totalXp) : "0") + " XP"
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        // 4. Courses List
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.userData && root.userData.valid && root.userData.courses.length > 0
          spacing: Style.space(6)

          Repeater {
            model: root.userData ? root.userData.courses : []

            Rectangle {
              required property var modelData
              required property int index
              Layout.fillWidth: true
              implicitHeight: Style.space(42)
              radius: Style.cornerRadius || 6
              color: index === root.selectedCourseIndex ? Style.hoverFillFor(root.foreground, Color.accent) : Qt.rgba(1, 1, 1, 0.04)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(8)

                Text {
                  text: modelData.flag
                  font.pixelSize: Style.font.title
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  RowLayout {
                    Layout.fillWidth: true
                    Text {
                      text: modelData.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      Layout.fillWidth: true
                    }
                    Text {
                      text: Model.formatNumber(modelData.xp) + " XP"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Progress Bar
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(4)
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.1)

                    Rectangle {
                      height: parent.height
                      width: Math.max(4, parent.width * (modelData.fraction || 0))
                      radius: 2
                      color: root.accentColor
                    }
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedCourseIndex = index
                  root.launchDuolingo()
                }
              }
            }
          }
        }

        // 5. Action Buttons
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          // Practice Button
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: Style.space(38)
            radius: Style.cornerRadius || 8
            color: practiceMouse.containsMouse ? Qt.darker(root.accentColor, 1.2) : root.accentColor

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)
              Text { text: "🚀" }
              Text {
                text: "Start Practice (Enter)"
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            MouseArea {
              id: practiceMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchDuolingo()
            }
          }

          // Refresh Button
          Rectangle {
            implicitWidth: Style.space(38)
            implicitHeight: Style.space(38)
            radius: Style.cornerRadius || 8
            color: refreshMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              text: "🔄"
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: refreshMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }

          // Settings Toggle Button
          Rectangle {
            implicitWidth: Style.space(38)
            implicitHeight: Style.space(38)
            radius: Style.cornerRadius || 8
            color: root.settingsOpen || settingsMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              text: "⚙️"
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }
        }

        // 6. Settings Expander
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.settingsOpen
          spacing: Style.space(8)

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.rgba(1, 1, 1, 0.1)
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            TextField {
              id: usernameInput
              Layout.fillWidth: true
              placeholderText: "Override username"
              text: settings.username || ""
              onAccepted: root.saveSettings(usernameInput.text)
            }

            Rectangle {
              implicitWidth: Style.space(64)
              implicitHeight: usernameInput.implicitHeight || Style.space(36)
              radius: Style.cornerRadius || 6
              color: saveMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)

              Text {
                anchors.centerIn: parent
                text: "Save"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: saveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveSettings(usernameInput.text)
              }
            }
          }
        }
      }
    }
  }
}
