import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "yey3men2.gotify"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string helper: home + "/.config/omarchy/plugins/yey3men2.gotify/bin/gotify-bridge"
  property bool configured: false
  property bool online: false
  property int unread: 0
  property string statusText: "Gotify not configured"
  property var messages: []
  property string loadError: ""
  property bool settingsOpen: false
  property bool savingSettings: false
  property string settingsNotice: ""
  property bool showConnectionIndicator: true
  property bool showUnreadIndicator: true
  property bool notificationsEnabled: true
  property bool catchUpEnabled: true
  property int maxIndividualNotifications: 5
  property int messageFetchLimit: 100
  property int selectedAppId: 0
  property var allApplications: []
  property double nowMs: Date.now()
  readonly property var applications: allApplications.length > 0 ? allApplications : buildApplications(messages)
  readonly property var appFilterOptions: buildFilterOptions(applications)
  readonly property var visibleMessages: filterMessages(messages, selectedAppId)
  readonly property var fetchLimitOptions: [
    {value: "25", label: "25 messages", description: "Small recent history"},
    {value: "50", label: "50 messages", description: "Moderate recent history"},
    {value: "100", label: "100 messages", description: "Recommended"},
    {value: "200", label: "200 messages", description: "Extended history"},
    {value: "500", label: "500 messages", description: "Largest history and catch-up window"}
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function buildApplications(source) {
    var seen = {}
    var result = []
    for (var i = 0; i < source.length; ++i) {
      var id = Number(source[i].appId || 0)
      if (id > 0 && !seen[id]) {
        seen[id] = true
        result.push({id: id, name: String(source[i].appName || ("App " + id))})
      }
    }
    result.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return result
  }

  function filterMessages(source, appId) {
    if (appId === 0) return source
    var result = []
    for (var i = 0; i < source.length; ++i)
      if (Number(source[i].appId || 0) === appId) result.push(source[i])
    return result
  }

  function buildFilterOptions(source) {
    var result = [{value: "0", label: "All applications", description: "Show every recent message"}]
    for (var i = 0; i < source.length; ++i) {
      result.push({
        value: String(source[i].id),
        label: String(source[i].name || ("App " + source[i].id)),
        description: String(source[i].description || "")
      })
    }
    return result
  }

  function cleanMarkdown(value) {
    return String(value || "")
      .replace(/!\[[^\]]*\]\([^)]+\)/g, "")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/^\s{0,3}#{1,6}\s+/gm, "")
      .replace(/\*\*([^*]+)\*\*/g, "$1")
      .replace(/__([^_]+)__/g, "$1")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/\r/g, "")
      .replace(/\n{3,}/g, "\n\n")
      .trim()
  }

  function relativeTime(value) {
    var then = new Date(String(value || "")).getTime()
    if (isNaN(then)) return "Unknown time"
    var seconds = Math.max(0, Math.floor((nowMs - then) / 1000))
    if (seconds < 45) return "Just now"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"
    var days = Math.floor(hours / 24)
    if (days < 7) return days + "d ago"
    return Qt.formatDateTime(new Date(then), "MMM d")
  }

  function priorityColor(priority) {
    var value = Number(priority || 0)
    if (value >= 8) return root.bar ? root.bar.urgent : Color.urgent
    if (value >= 4) return "#f59e0b"
    return Qt.rgba(1, 1, 1, 0.10)
  }

  function refreshStatus() {
    if (!statusProcess.running) {
      statusProcess.command = [helper, "status"]
      statusProcess.running = true
    }
  }

  function refreshMessages() {
    if (!messagesProcess.running) {
      loadError = ""
      messagesProcess.command = [helper, "messages"]
      messagesProcess.running = true
    }
  }

  function openMessage(id) {
    openProcess.command = [helper, "open-message", String(id)]
    openProcess.running = true
  }

  function openSettings() {
    settingsOpen = true
    settingsNotice = ""
    configProcess.running = true
  }

  function cancelSettings() {
    settingsOpen = false
    settingsNotice = ""
    refreshStatus()
  }

  function saveSettings() {
    var serverValue = serverField.text.trim()
    if (serverValue === "") {
      settingsNotice = "Enter a Gotify server URL."
      return
    }
    savingSettings = true
    settingsNotice = "Testing connection…"
    saveProcess.payload = JSON.stringify({
      server: serverValue,
      token: tokenField.text,
      showConnectionIndicator: showConnectionToggle.checked,
      showUnreadIndicator: showUnreadToggle.checked,
      notificationsEnabled: notificationsToggle.checked,
      catchUpEnabled: catchUpToggle.checked,
      maxIndividualNotifications: Number(maxNotificationsField.text),
      messageFetchLimit: Number(fetchLimitDropdown.value)
    })
    saveProcess.running = true
  }

  function saveIndicatorPreferences() {
    preferenceProcess.payload = JSON.stringify({
      showConnectionIndicator: showConnectionToggle.checked,
      showUnreadIndicator: showUnreadToggle.checked,
      notificationsEnabled: notificationsToggle.checked,
      catchUpEnabled: catchUpToggle.checked,
      maxIndividualNotifications: Number(maxNotificationsField.text),
      messageFetchLimit: Number(fetchLimitDropdown.value)
    })
    if (preferenceProcess.running) preferenceRetry.restart()
    else preferenceProcess.running = true
  }

  onOpenedChanged: {
    if (opened) {
      settingsOpen = false
      refreshMessages()
      markReadProcess.running = true
      unread = 0
    }
  }

  Component.onCompleted: refreshStatus()

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var state = JSON.parse(text)
          root.configured = state.configured === true
          root.online = state.online === true
          root.unread = Number(state.unread || 0)
          root.showConnectionIndicator = state.showConnectionIndicator !== false
          root.showUnreadIndicator = state.showUnreadIndicator !== false
          root.notificationsEnabled = state.notificationsEnabled !== false
          root.catchUpEnabled = state.catchUpEnabled !== false
          root.maxIndividualNotifications = Number(state.maxIndividualNotifications || 5)
          root.messageFetchLimit = Number(state.messageFetchLimit || 100)
          root.statusText = String(state.message || "Gotify")
        } catch (e) {
          root.online = false
          root.statusText = "Gotify status unavailable"
        }
      }
    }
  }
  Timer {
    id: preferenceRetry
    interval: 150
    repeat: false
    onTriggered: {
      if (preferenceProcess.running) restart()
      else preferenceProcess.running = true
    }
  }
  Process {
    id: preferenceProcess
    property string payload: ""
    stdinEnabled: true
    command: [root.helper, "save-preferences"]
    stdout: StdioCollector { id: preferenceOutput; waitForEnd: true }
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.settingsNotice = "Could not save indicator preferences."
        root.refreshStatus()
      }
    }
  }

  Process {
    id: messagesProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          root.messages = result.messages || []
          root.allApplications = result.applications || []
        } catch (e) {
          root.loadError = "Could not load Gotify messages."
        }
      }
    }
  }

  Process { id: markReadProcess; command: [root.helper, "mark-read"] }
  Process { id: openProcess }
  Process { id: pollProcess; command: [root.helper, "poll"]; onExited: root.refreshStatus() }
  Process {
    id: configProcess
    command: [root.helper, "show-config"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var config = JSON.parse(text)
          serverField.text = String(config.server || "")
          tokenField.text = ""
          showConnectionToggle.checked = config.showConnectionIndicator !== false
          showUnreadToggle.checked = config.showUnreadIndicator !== false
          notificationsToggle.checked = config.notificationsEnabled !== false
          catchUpToggle.checked = config.catchUpEnabled !== false
          maxNotificationsField.text = String(config.maxIndividualNotifications || 5)
          fetchLimitDropdown.value = String(config.messageFetchLimit || 100)
        } catch (e) {
          root.settingsNotice = "Could not load the current configuration."
        }
      }
    }
  }
  Process {
    id: saveProcess
    property string payload: ""
    stdinEnabled: true
    command: [root.helper, "configure"]
    stdout: StdioCollector { id: saveOutput; waitForEnd: true }
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
    onExited: function(exitCode) {
      root.savingSettings = false
      tokenField.text = ""
      try {
        var result = JSON.parse(String(saveOutput.text || "{}"))
        root.settingsNotice = String(result.message || (exitCode === 0 ? "Saved." : "Could not save settings."))
        if (result.ok === true) {
          serverField.text = String(result.server || serverField.text)
          root.showConnectionIndicator = showConnectionToggle.checked
          root.showUnreadIndicator = showUnreadToggle.checked
          root.notificationsEnabled = notificationsToggle.checked
          root.catchUpEnabled = catchUpToggle.checked
          root.maxIndividualNotifications = Number(maxNotificationsField.text)
          root.messageFetchLimit = Number(fetchLimitDropdown.value)
          root.refreshStatus()
          root.refreshMessages()
        }
      } catch (e) {
        root.settingsNotice = "Could not save settings."
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    active: root.opened || root.unread > 0
    tooltipText: root.statusText + (root.unread > 0 ? " · " + root.unread + " unread" : "")
    iconComponent: Component {
      Image {
        source: Qt.resolvedUrl("assets/gotify.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.configured ? 1.0 : 0.45
      }
    }
    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        pollProcess.running = true
        root.refreshMessages()
      } else root.toggle()
    }

    Text {
      visible: root.showUnreadIndicator && root.unread > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: 1
      anchors.topMargin: -1
      text: root.unread > 99 ? "99+" : String(root.unread)
      textFormat: Text.PlainText
      color: root.bar ? root.bar.urgent : Color.urgent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.bold: true
      font.pixelSize: root.unread > 9 ? 8 : 10
    }

    Rectangle {
      visible: root.showConnectionIndicator && root.configured
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: 2
      anchors.bottomMargin: 2
      width: 6
      height: 6
      radius: 3
      color: root.online ? "#4ade80" : (root.bar ? root.bar.urgent : Color.urgent)
      border.width: 1
      border.color: root.bar ? root.bar.background : Color.background
    }
  }

  KeyboardPanel {
    id: inboxPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(420))
    contentHeight: fittedContentHeight(Math.min(messageColumn.implicitHeight, Style.space(620)))

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: messageColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: messageColumn
        width: parent.width
        spacing: Style.space(10)

        Rectangle {
          width: parent.width
          height: Style.space(54)
          color: "transparent"

          Image {
            id: headerIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34)
            height: width
            source: Qt.resolvedUrl("assets/gotify-banner.png")
            fillMode: Image.PreserveAspectFit
            smooth: true
          }

          Rectangle {
            visible: root.showConnectionIndicator
            anchors.right: headerIcon.right
            anchors.bottom: headerIcon.bottom
            width: 9
            height: 9
            radius: 5
            color: !root.configured ? "#888888"
              : (root.online ? "#4ade80" : (root.bar ? root.bar.urgent : Color.urgent))
            border.width: 1
            border.color: root.bar ? root.bar.background : Color.background
          }

          Column {
            anchors.left: headerIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Gotify"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: (root.online ? "CONNECTED" : "OFFLINE") + "  ·  "
                + root.visibleMessages.length + " OF " + root.messages.length + " MESSAGES"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.65
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒓"
            iconSize: Style.font.icon
            bordered: false
            foreground: root.bar ? root.bar.foreground : Color.foreground
            tooltipText: "Gotify settings"
            onClicked: {
              if (root.settingsOpen) root.cancelSettings()
              else root.openSettings()
            }
          }
        }

        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CONNECTION"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Text {
            width: parent.width
            text: "Server URL"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            id: serverField
            width: parent.width
            placeholderText: "https://gotify.example.com"
            enabled: !root.savingSettings
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          Text {
            width: parent.width
            text: "Client token"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            id: tokenField
            width: parent.width
            password: true
            placeholderText: root.configured ? "Leave blank to keep current token" : "Enter client token"
            enabled: !root.savingSettings
            foreground: root.bar ? root.bar.foreground : Color.foreground
            Keys.onReturnPressed: root.saveSettings()
          }

          Toggle {
            id: showConnectionToggle
            width: parent.width
            label: "Connection indicator"
            description: "Show the green or red status dot on the bar icon."
            checked: true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              checked = !checked
              root.showConnectionIndicator = checked
              root.saveIndicatorPreferences()
            }
          }

          Toggle {
            id: showUnreadToggle
            width: parent.width
            label: "Unread notification badge"
            description: "Show the unread-message count on the bar icon."
            checked: true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              checked = !checked
              root.showUnreadIndicator = checked
              root.saveIndicatorPreferences()
            }
          }

          PanelSectionHeader {
            text: "NOTIFICATIONS"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Toggle {
            id: notificationsToggle
            width: parent.width
            label: "Desktop notifications"
            description: "Show Gotify messages as desktop notifications. History and unread counts continue when disabled."
            checked: true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              checked = !checked
              root.notificationsEnabled = checked
              root.saveIndicatorPreferences()
            }
          }

          Toggle {
            id: catchUpToggle
            width: parent.width
            label: "Summarize messages received while away"
            description: "After sleep or a long connection gap, show one summary instead of replaying every message."
            checked: true
            enabled: notificationsToggle.checked
            foreground: root.bar ? root.bar.foreground : Color.foreground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              checked = !checked
              root.catchUpEnabled = checked
              root.saveIndicatorPreferences()
            }
          }

          Text {
            width: parent.width
            text: "Maximum individual notifications (1–20)"
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: notificationsToggle.checked && catchUpToggle.checked ? 1.0 : 0.5
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            id: maxNotificationsField
            width: parent.width
            text: "5"
            enabled: notificationsToggle.checked && catchUpToggle.checked
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 1; top: 20 }
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onEditingFinished: {
              if (acceptableInput) {
                root.maxIndividualNotifications = Number(text)
                root.saveIndicatorPreferences()
              }
            }
          }

          SearchableDropdown {
            id: fetchLimitDropdown
            width: parent.width
            label: "Messages to fetch"
            value: "100"
            options: root.fetchLimitOptions
            placeholderText: "Select history size…"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onChanged: function(value) {
              root.messageFetchLimit = Number(value)
              root.saveIndicatorPreferences()
              root.refreshMessages()
            }
          }

          Text {
            visible: root.settingsNotice !== ""
            width: parent.width
            text: root.settingsNotice
            textFormat: Text.PlainText
            color: root.settingsNotice.indexOf("successfully") !== -1
              ? (root.bar ? root.bar.foreground : Color.foreground)
              : (root.bar ? root.bar.urgent : Color.urgent)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.savingSettings ? "Testing…" : "Test & Save"
              iconText: "󰄬"
              bordered: true
              enabled: !root.savingSettings
              foreground: root.bar ? root.bar.foreground : Color.foreground
              onClicked: root.saveSettings()
            }
            Button {
              text: "Cancel"
              bordered: true
              enabled: !root.savingSettings
              foreground: root.bar ? root.bar.foreground : Color.foreground
              onClicked: root.cancelSettings()
            }
          }

          Text {
            width: parent.width
            text: "The client token is stored locally with owner-only permissions and is never placed in the process command line."
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.55
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        SearchableDropdown {
          visible: !root.settingsOpen && root.applications.length > 1
          width: parent.width
          showLabel: false
          value: String(root.selectedAppId)
          options: root.appFilterOptions
          placeholderText: "Search applications…"
          emptyText: "No matching applications"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onChanged: function(value) { root.selectedAppId = parseInt(value, 10) || 0 }
        }

        Text {
          visible: !root.settingsOpen && root.loadError !== ""
          width: parent.width
          text: root.loadError
          textFormat: Text.PlainText
          color: root.bar ? root.bar.urgent : Color.urgent
          wrapMode: Text.WordWrap
        }

        Text {
          visible: !root.settingsOpen && root.loadError === "" && root.visibleMessages.length === 0
          width: parent.width
          text: !root.configured ? "Use the gear to configure Gotify."
            : (root.selectedAppId === 0 ? "No Gotify messages yet." : "No recent messages from this application.")
          textFormat: Text.PlainText
          color: root.bar ? root.bar.foreground : Color.foreground
          opacity: 0.7
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.settingsOpen ? [] : root.visibleMessages
          delegate: Rectangle {
            required property var modelData
            width: messageColumn.width
            implicitHeight: cardContent.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.055)
            border.width: 1
            border.color: root.priorityColor(modelData.priority)

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Number(modelData.priority || 0) >= 4 ? 3 : 0
              radius: Style.cornerRadius
              color: root.priorityColor(modelData.priority)
            }

            Row {
              id: cardContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(40)
                height: width
                radius: Style.cornerRadius
                color: Qt.rgba(1, 1, 1, 0.08)

                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  source: String(modelData.iconUrl || "") !== ""
                    ? String(modelData.iconUrl)
                    : Qt.resolvedUrl("assets/gotify.svg")
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  asynchronous: true
                }
              }

              Column {
                width: cardContent.width - Style.space(50)
                spacing: Style.space(4)

                Text {
                  width: parent.width
                  text: String(modelData.title || "Gotify")
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  visible: root.cleanMarkdown(modelData.message) !== ""
                  width: parent.width
                  text: root.cleanMarkdown(modelData.message)
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  opacity: 0.82
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: String(modelData.appName || "Gotify") + "  ·  " + root.relativeTime(modelData.date)
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  opacity: 0.5
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openMessage(modelData.id)
            }
          }
        }
      }
    }
  }
}
