import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  readonly property string home: Quickshell.env("HOME")
  readonly property string poller: home + "/.config/omarchy/plugins/yey3men2.gotify/bin/gotify-bridge"

  function poll() {
    if (!pollProcess.running) {
      pollProcess.command = [poller, "poll"]
      pollProcess.running = true
    }
  }

  Component.onCompleted: poll()

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.poll()
  }

  Process {
    id: pollProcess
    running: false
  }
}
