import QtQuick
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
  property var service: null
  readonly property var effectiveData: service && service.userData ? service.userData : userData
  readonly property string effectiveError: service ? service.lastError : ""
  readonly property bool effectiveStale: service ? service.isStale === true : false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accentColor: Color.accent || "#58cc02"
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))

  property int selectedCourseIndex: 0
  property bool settingsOpen: false
  property bool keysOpen: false

  readonly property bool reducedMotion: service ? service.reducedMotion === true : false
  readonly property int xpToday: service ? service.xpToday : 0
  readonly property int goalXp: service ? service.goalXp : 50
  readonly property bool goalMet: xpToday >= goalXp
  readonly property real goalFraction: Model.fraction(xpToday, goalXp)
  readonly property var weekData: service ? service.weekHistory : Model.weekHistory(null)
  readonly property bool hasHistory: service && service.history && service.history.days && Object.keys(service.history.days).length > 0
  readonly property bool hasConfiguredUsername: {
    var su = service ? String(service.configuredUsername || "").trim() : ""
    if (su !== "") return true
    var ss = settings.username !== undefined ? String(settings.username).trim() : ""
    return ss !== ""
  }

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
    if (root.service && typeof root.service.launchDuolingo === "function") {
      root.service.launchDuolingo()
    } else if (root.bar) {
      root.bar.run(root.pluginDir + "/bin/launch-duo.sh")
    }
    root.close()
  }

  function refresh() {
    if (root.service && typeof root.service.refresh === "function") root.service.refresh()
    else if (root.hostWidget && root.hostWidget.refresh) root.hostWidget.refresh()
  }

  function saveSettings(newUsername) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.username = newUsername.trim()
    root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.refresh()
  }

  // IPC handled by Service.qml (target "user.duolingo"). Panel toggle via
  // shell id-based handling; Service owns status/refresh/launch/streak.

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(350))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: root.launchDuolingo()
      onMoveRequested: function(dx, dy) {
        var d = root.effectiveData
        if (!d || !d.courses) return
        var count = d.courses.length
        if (count === 0) return
        if (dy > 0) root.selectedCourseIndex = (root.selectedCourseIndex + 1) % count
        else if (dy < 0) root.selectedCourseIndex = (root.selectedCourseIndex - 1 + count) % count
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.settingsOpen = !root.settingsOpen
        else if (t === "?") root.keysOpen = !root.keysOpen
        else if (t === "q" || t === "Q") root.close()
      }

      Column {
        id: mainColumn
        anchors.fill: parent
        spacing: Style.space(12)

        // 1. Native Omarchy Hero
        PanelHero {
          title: root.effectiveData && root.effectiveData.valid ? root.effectiveData.fullname : "Duolingo Tracker"
          meta: root.effectiveData && root.effectiveData.valid ? ("@" + root.effectiveData.username) : "Looking for session..."
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Image {
              source: (root.effectiveData && root.effectiveData.avatar) ? root.effectiveData.avatar : Qt.resolvedUrl("assets/duo.png")
              width: Style.space(36)
              height: Style.space(36)
              fillMode: Image.PreserveAspectFit
              smooth: true
            }
          }
          trailingControl: Component {
            Rectangle {
              implicitWidth: streakPillRow.implicitWidth + Style.space(12)
              implicitHeight: Style.space(26)
              radius: Math.min(Style.cornerRadius, 6)
              color: root.effectiveData && root.effectiveData.streakExtendedToday ? Qt.rgba(0.34, 0.8, 0.01, 0.18) : Qt.rgba(1.0, 0.4, 0.0, 0.18)

              Row {
                id: streakPillRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: root.effectiveData && root.effectiveData.valid ? String(root.effectiveData.streak) : "0"
                  color: root.effectiveData && root.effectiveData.streakExtendedToday ? root.accentColor : root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }
          }
        }

        // 2. Status Banner
        Rectangle {
          width: parent.width
          implicitHeight: statusText.implicitHeight + Style.space(12)
          radius: Math.min(Style.cornerRadius, 6)
          color: {
            if (!root.effectiveData || !root.effectiveData.valid) return Qt.rgba(0.5, 0.5, 0.5, 0.12)
            if (root.effectiveStale) return Qt.rgba(0.5, 0.5, 0.5, 0.12)
            if (root.effectiveData.streakExtendedToday) return Qt.rgba(0.34, 0.8, 0.01, 0.14)
            return Qt.rgba(1.0, 0.2, 0.2, 0.14)
          }

          Text {
            id: statusText
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            text: {
              var data = root.effectiveData
              var err = root.effectiveError
              var stale = root.effectiveStale
              if (!data || !data.valid) {
                if (err) return err
                return "Connecting to Duolingo account..."
              }
              if (stale) return "Offline — showing last saved data."
              if (data.streakExtendedToday) return "Streak completed for today."
              return "Daily lesson pending. Practice today to keep your streak."
            }
            color: {
              if (!root.effectiveData || !root.effectiveData.valid) return root.dim
              if (root.effectiveStale) return root.dim
              if (root.effectiveData.streakExtendedToday) return root.accentColor
              return root.urgent
            }
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }

        // 3. Empty username prompt
        Rectangle {
          width: parent.width
          implicitHeight: emptyCol.implicitHeight + Style.space(12)
          radius: Math.min(Style.cornerRadius, 6)
          color: Qt.rgba(0.5, 0.5, 0.5, 0.12)
          visible: !root.hasConfiguredUsername && (!root.effectiveData || !root.effectiveData.valid)
          Column {
            id: emptyCol
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            spacing: Style.space(8)
            Text {
              width: parent.width
              text: "Set your Duolingo username in Settings"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              implicitWidth: goSettingsText.implicitWidth + Style.space(16)
              implicitHeight: Style.space(28)
              radius: Math.min(Style.cornerRadius, 6)
              color: settingsMouse2.containsMouse ? Qt.darker(root.accentColor, 1.1) : root.accentColor
              Text {
                id: goSettingsText
                anchors.centerIn: parent
                text: "Open Settings"
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              MouseArea {
                id: settingsMouse2
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsOpen = true
              }
            }
          }
        }

        // 4. Today goal progress
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.hasConfiguredUsername && root.effectiveData && root.effectiveData.valid

          Item {
            width: parent.width
            implicitHeight: Math.max(todayLabel.implicitHeight, todayCaption.implicitHeight)
            Text {
              id: todayLabel
              anchors.left: parent.left
              anchors.baseline: todayCaption.baseline
              text: "TODAY"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              topPadding: Math.ceil(Style.font.caption * 0.15)
            }
            Text {
              id: todayCaption
              anchors.right: parent.right
              anchors.top: parent.top
              text: root.xpToday + " / " + root.goalXp + " XP today"
              color: root.goalMet ? root.accentColor : Qt.rgba(0.95, 0.6, 0.0, 1)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.08)
            Rectangle {
              height: parent.height
              width: parent.width * Math.max(0, Math.min(1, root.goalFraction))
              radius: parent.radius
              color: root.goalMet ? root.accentColor : Qt.rgba(0.95, 0.6, 0.0, 1)
              Behavior on width { enabled: !root.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
              Behavior on color { enabled: !root.reducedMotion; ColorAnimation { duration: 240 } }
            }
          }
        }

        // 5. This week
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(weekLabel.implicitHeight, weekCaption.implicitHeight)
            Text {
              id: weekLabel
              anchors.left: parent.left
              anchors.baseline: weekCaption.baseline
              text: "THIS WEEK"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              topPadding: Math.ceil(Style.font.caption * 0.15)
            }
            Text {
              id: weekCaption
              anchors.right: parent.right
              anchors.top: parent.top
              text: root.hasHistory ? "" : "Your first day of tracking starts now"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(4)
            visible: true
            Repeater {
              model: root.weekData
              delegate: Item {
                required property var modelData
                width: (parent.width - 6 * Style.space(4)) / 7
                height: Style.space(48)

                Column {
                  anchors.fill: parent
                  spacing: Style.space(4)

                  Rectangle {
                    width: parent.width
                    height: Style.space(28)
                    radius: Math.min(Style.cornerRadius, 4)
                    color: modelData.today ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                    border.width: modelData.today ? 1 : 0
                    border.color: modelData.today ? Qt.rgba(1,1,1,0.12) : "transparent"

                    Rectangle {
                      anchors.bottom: parent.bottom
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.margins: 2
                      height: {
                        if (!modelData.hasData || modelData.xpEarned <= 0) return 2
                        var maxXp = root.goalXp
                        for (var i = 0; i < root.weekData.length; i++) if (root.weekData[i].xpEarned > maxXp) maxXp = root.weekData[i].xpEarned
                        var f = Math.max(0, Math.min(1, modelData.xpEarned / maxXp))
                        return Math.max(2, (parent.height - 4) * f)
                      }
                      radius: 2
                      color: modelData.today ? (root.goalMet ? root.accentColor : Qt.rgba(0.95,0.6,0.0,1)) : Qt.rgba(1,1,1,0.18)
                      Behavior on height { enabled: !root.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.letter
                    color: modelData.today ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: modelData.today
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.hasData && modelData.xpEarned > 0 ? String(modelData.xpEarned) : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: 9
                  }
                }
              }
            }
          }
        }

        // 6. Courses Header
        PanelSectionHeader {
          visible: root.effectiveData && root.effectiveData.valid && root.effectiveData.courses.length > 0
          text: "COURSES · " + (root.effectiveData ? Model.formatNumber(root.effectiveData.totalXp) : "0") + " XP"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // 4. Courses List
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.effectiveData && root.effectiveData.valid && root.effectiveData.courses.length > 0

          Repeater {
            model: root.effectiveData ? root.effectiveData.courses : []

            Rectangle {
              required property var modelData
              required property int index
              width: parent.width
              implicitHeight: Style.space(34)
              radius: Math.min(Style.cornerRadius, 6)
              color: index === root.selectedCourseIndex ? Style.hoverFillFor(root.foreground, Color.accent) : Qt.rgba(1, 1, 1, 0.04)

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  text: modelData.flag
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(36)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Item {
                    width: parent.width
                    implicitHeight: Style.space(14)

                    Text {
                      text: modelData.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      text: Model.formatNumber(modelData.xp) + " XP"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Rectangle {
                    width: parent.width
                    implicitHeight: 3
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Rectangle {
                      height: parent.height
                      width: Math.max(3, parent.width * (modelData.fraction || 0))
                      radius: 1.5
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

        PanelSeparator {
          foreground: root.foreground
        }

        // 5. Action Buttons Row
        Row {
          width: parent.width
          spacing: Style.space(6)

          Rectangle {
            width: parent.width - (Style.space(34) * 2 + Style.space(12))
            implicitHeight: Style.space(34)
            radius: Math.min(Style.cornerRadius, 6)
            color: practiceMouse.containsMouse ? Qt.darker(root.accentColor, 1.2) : root.accentColor

            Text {
              anchors.centerIn: parent
              text: "Start Practice (Enter)"
              color: "#ffffff"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            MouseArea {
              id: practiceMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchDuolingo()
            }
          }

          Rectangle {
            width: Style.space(34)
            implicitHeight: Style.space(34)
            radius: Math.min(Style.cornerRadius, 6)
            color: refreshMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              text: "R"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            MouseArea {
              id: refreshMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }

          Rectangle {
            width: Style.space(34)
            implicitHeight: Style.space(34)
            radius: Math.min(Style.cornerRadius, 6)
            color: root.settingsOpen || settingsMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              text: "S"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
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

        // Footer hint and KeysCard
        Text {
          width: parent.width
          text: "Press ? for shortcuts  ·  j/k navigate  ·  Enter practice  ·  r refresh  ·  s settings"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          visible: !root.keysOpen
        }

        Item {
          id: keysHost
          width: parent.width
          implicitHeight: root.keysOpen ? keysCard.implicitHeight : 0
          height: implicitHeight
          clip: true
          visible: height > 0.5
          Behavior on implicitHeight { enabled: !root.reducedMotion; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

          Rectangle {
            id: keysCard
            width: parent.width
            implicitHeight: keysCol.implicitHeight + Style.space(12)
            radius: Math.min(Style.cornerRadius, 6)
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            Column {
              id: keysCol
              x: Style.space(8)
              y: Style.space(6)
              width: parent.width - Style.space(16)
              spacing: Style.space(4)
              Repeater {
                model: [["j / k","Navigate courses"], ["Enter","Start practice"], ["r","Refresh stats"], ["s","Toggle settings"], ["?","Toggle this help"], ["Esc / q","Close panel"]]
                delegate: Item {
                  required property var modelData
                  width: keysCol.width
                  height: Style.space(18)
                  Rectangle {
                    id: keyCap
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: capText.implicitWidth + Style.space(8)
                    height: capText.implicitHeight + Style.space(4)
                    radius: Math.min(Style.cornerRadius, 4)
                    color: Qt.rgba(1,1,1,0.08)
                    Text {
                      id: capText
                      anchors.centerIn: parent
                      text: modelData[0]
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                  Text {
                    anchors.left: keyCap.right
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: modelData[1]
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }

        // 7. Settings Drawer
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.settingsOpen

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: usernameInput
              width: parent.width - Style.space(64)
              implicitHeight: Style.space(32)
              placeholderText: "Override username"
              text: settings.username || ""
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              onAccepted: root.saveSettings(usernameInput.text)
            }

            Rectangle {
              width: Style.space(58)
              implicitHeight: Style.space(32)
              radius: Math.min(Style.cornerRadius, 4)
              color: saveMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)

              Text {
                anchors.centerIn: parent
                text: "Save"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
