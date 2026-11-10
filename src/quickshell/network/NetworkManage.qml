import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

// List-style manager for saved Wi-Fi networks and paired Bluetooth devices.
// Data and actions go through scripts/netmanage.py. Opened as the "netmanage" widget.
Item {
    id: window
    visible: false
    focus: true

    function s(val) {
        return Scaler.s(val);
    }

    readonly property string backend: Caching.serpantinumDir + "/scripts/netmanage.py"
    readonly property string iconFont: "Iosevka Nerd Font"

    property string activeTab: "wifi"
    property var wifiList: []
    property var btList: []
    property string expandedId: ""
    property string confirmForgetId: ""
    property string busyId: ""
    property string statusText: ""
    property bool statusIsError: false
    property var revealedPasswords: ({})
    property bool loaded: false

    readonly property color tabColor: activeTab === "wifi" ? ThemeBackend.blue : ThemeBackend.mauve

    function gotoTab(tabName) {
        if (!tabName) return;
        let t = tabName.toLowerCase();
        if (t === "bt" || t === "bluetooth") window.activeTab = "bt";
        else if (t === "wifi" || t === "wlan") window.activeTab = "wifi";
    }

    // ---- intro / exit animation (same contract as the other popups) ----
    property var exitCallback: null
    property real introMain: 0
    property real introContent: 0

    function startExit(onFinished) {
        introAnim.stop();
        exitCallback = onFinished;
        exitAnim.restart();
    }

    function resetAndPlayIntro() {
        exitAnim.stop();
        introMain = 0;
        introContent = 0;
        introAnim.restart();
    }

    ParallelAnimation {
        id: introAnim
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 700; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            NumberAnimation { target: window; property: "introContent"; from: 0; to: 1.0; duration: 700; easing.type: Easing.OutExpo }
        }
    }

    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: window; property: "introContent"; to: 0.0; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: window; property: "introMain"; to: 0.0; duration: 180; easing.type: Easing.InQuart }
        }
        ScriptAction {
            script: {
                if (window.exitCallback) {
                    let cb = window.exitCallback;
                    window.exitCallback = null;
                    cb();
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            window.forceActiveFocus();
            window.resetAndPlayIntro();
            window.refresh();
        } else {
            introAnim.stop();
            exitAnim.stop();
            introMain = 0;
            introContent = 0;
            window.expandedId = "";
            window.confirmForgetId = "";
            window.revealedPasswords = {};
        }
    }

    Component.onCompleted: {
        if (visible) {
            resetAndPlayIntro();
            refresh();
        }
    }

    Shortcut {
        sequence: "Tab"
        enabled: window.visible
        onActivated: window.activeTab = (window.activeTab === "wifi" ? "bt" : "wifi")
    }

    // ---- backend ----
    function refresh() {
        if (!listProc.running) listProc.running = true;
    }

    Process {
        id: listProc
        command: ["python3", window.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text);
                    window.wifiList = d.wifi || [];
                    window.btList = d.bt || [];
                    window.loaded = true;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: window.visible && window.busyId === ""
        onTriggered: window.refresh()
    }

    property var actionQueue: []

    // Runs one backend action; doneMsg is shown on success, errors are shown from the tool's output.
    function runAction(id, args, doneMsg, onOutput) {
        window.actionQueue = window.actionQueue.concat([{ id: id, args: args, doneMsg: doneMsg || "", onOutput: onOutput || null }]);
        window.pumpQueue();
    }

    function pumpQueue() {
        if (actionProc.running || window.actionQueue.length === 0) return;
        let next = window.actionQueue[0];
        window.actionQueue = window.actionQueue.slice(1);
        actionProc.current = next;
        window.busyId = next.id;
        window.statusText = "";
        actionProc.command = ["python3", window.backend].concat(next.args);
        actionProc.running = true;
    }

    Process {
        id: actionProc
        property var current: null
        stdout: StdioCollector { id: actionOut }
        onExited: (code) => {
            let cur = actionProc.current;
            let out = actionOut.text ? actionOut.text.trim() : "";
            if (code === 0) {
                if (cur && cur.onOutput) cur.onOutput(out);
                window.statusIsError = false;
                window.statusText = cur ? cur.doneMsg : "";
            } else {
                window.statusIsError = true;
                window.statusText = out !== "" ? out.split("\n").pop() : "Something went wrong";
            }
            window.busyId = "";
            statusClear.restart();
            window.refresh();
            window.pumpQueue();
        }
    }

    Timer {
        id: statusClear
        interval: 5000
        onTriggered: window.statusText = ""
    }

    function wifiIcon(w) {
        if (!w.inRange) return "󰤮";
        if (w.signal >= 75) return "󰤨";
        if (w.signal >= 50) return "󰤥";
        if (w.signal >= 25) return "󰤢";
        return "󰤟";
    }

    function btIcon(d) {
        let i = d.icon || "";
        if (i.indexOf("headset") !== -1 || i.indexOf("headphones") !== -1) return "󰋋";
        if (i.indexOf("mouse") !== -1) return "󰍽";
        if (i.indexOf("keyboard") !== -1) return "󰌌";
        if (i.indexOf("phone") !== -1) return "󰏲";
        if (i.indexOf("audio") !== -1) return "󰓃";
        if (i.indexOf("gaming") !== -1 || i.indexOf("joystick") !== -1) return "󰊴";
        return "󰂯";
    }

    function forget(id, args, label) {
        if (window.confirmForgetId !== id) {
            window.confirmForgetId = id;
            confirmReset.restart();
            return;
        }
        window.confirmForgetId = "";
        window.expandedId = "";
        window.runAction(id, args, "Forgot " + label);
    }

    Timer {
        id: confirmReset
        interval: 3500
        onTriggered: window.confirmForgetId = ""
    }

    // ---- small building blocks ----
    component ActionChip: Rectangle {
        id: chip
        property string icon: ""
        property string label: ""
        property color accent: ThemeBackend.text
        property bool danger: false
        property bool on: false
        signal clicked()

        implicitHeight: Scaler.s(30)
        implicitWidth: chipRow.implicitWidth + Scaler.s(20)
        radius: ThemeBackend.borderRadius
        color: chip.on ? Qt.rgba(accent.r, accent.g, accent.b, 0.22)
             : (chipMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
        border.color: chip.danger ? ThemeBackend.red : (chip.on ? accent : ThemeBackend.surface1)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Scaler.s(6)
            Text {
                visible: chip.icon !== ""
                text: chip.icon
                font.family: "Iosevka Nerd Font"
                font.pixelSize: Scaler.s(14)
                color: chip.danger ? ThemeBackend.red : (chip.on ? chip.accent : ThemeBackend.text)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: chip.label
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11.5)
                font.bold: true
                color: chip.danger ? ThemeBackend.red : (chip.on ? chip.accent : ThemeBackend.text)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component InlineInput: Rectangle {
        id: inputBox
        property alias text: field.text
        property string placeholder: ""
        property bool secret: false
        property string actionLabel: "Save"
        property color focusColor: ThemeBackend.blue
        signal submitted(string value)

        implicitHeight: Scaler.s(32)
        radius: ThemeBackend.borderRadius
        color: ThemeBackend.mantle
        border.color: field.activeFocus ? inputBox.focusColor : ThemeBackend.surface1
        border.width: 1

        TextInput {
            id: field
            anchors.left: parent.left
            anchors.right: saveBtn.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Scaler.s(10)
            anchors.rightMargin: Scaler.s(8)
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            echoMode: inputBox.secret ? TextInput.Password : TextInput.Normal
            clip: true
            selectByMouse: true
            onAccepted: if (text !== "") inputBox.submitted(text)
            Keys.onEscapePressed: { text = ""; field.focus = false; }

            Text {
                visible: field.text === ""
                text: inputBox.placeholder
                color: ThemeBackend.overlay1
                font: field.font
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        ActionChip {
            id: saveBtn
            anchors.right: parent.right
            anchors.rightMargin: Scaler.s(2)
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: Scaler.s(28)
            label: inputBox.actionLabel
            accent: inputBox.focusColor
            on: field.text !== ""
            onClicked: if (field.text !== "") inputBox.submitted(field.text)
        }

        function focusField() { field.forceActiveFocus(); }
    }

    // ---- UI ----
    Item {
        anchors.fill: parent
        scale: 0.95 + 0.05 * window.introMain
        opacity: window.introMain
        transform: Translate { y: window.s(20) * (1 - window.introMain) }

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.base
            border.color: ThemeBackend.surface0
            border.width: 1
            clip: true

            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: parent.width * 0.35; y: -height * 0.55
                opacity: 0.06
                color: window.tabColor
                Behavior on color { ColorAnimation { duration: 600 } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(16)
                spacing: window.s(12)

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: window.s(10)

                    Text {
                        text: window.activeTab === "wifi" ? "󰤨" : "󰂯"
                        font.family: window.iconFont
                        font.pixelSize: window.s(26)
                        color: window.tabColor
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Manage connections"
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: window.s(16)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: window.activeTab === "wifi"
                                ? window.wifiList.length + " saved network" + (window.wifiList.length === 1 ? "" : "s")
                                : window.btList.length + " paired device" + (window.btList.length === 1 ? "" : "s")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: window.s(11)
                            color: ThemeBackend.subtext0
                        }
                    }
                    Item { Layout.fillWidth: true }
                    ActionChip {
                        icon: "󰑐"
                        label: ""
                        implicitWidth: window.s(32)
                        onClicked: window.refresh()
                    }
                    ActionChip {
                        icon: "󰀻"
                        label: "Bubbles"
                        onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/serpantinum", "msg", "toggle", "network", window.activeTab === "bt" ? "bt" : "wifi"])
                    }
                }

                // Tabs
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(38)
                    radius: ThemeBackend.borderRadius
                    color: ThemeBackend.mantle
                    border.color: ThemeBackend.surface0
                    border.width: 1

                    Rectangle {
                        width: (parent.width - window.s(8)) / 2
                        height: parent.height - window.s(8)
                        y: window.s(4)
                        x: window.s(4) + (window.activeTab === "wifi" ? 0 : width)
                        radius: ThemeBackend.borderRadius
                        color: Qt.rgba(window.tabColor.r, window.tabColor.g, window.tabColor.b, 0.2)
                        border.color: window.tabColor
                        border.width: 1
                        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 280 } }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: window.s(4)
                        Repeater {
                            model: [{ id: "wifi", icon: "󰤨", label: "Wi-Fi" }, { id: "bt", icon: "󰂯", label: "Bluetooth" }]
                            delegate: Item {
                                required property var modelData
                                width: parent.width / 2
                                height: parent.height
                                Row {
                                    anchors.centerIn: parent
                                    spacing: window.s(8)
                                    Text {
                                        text: modelData.icon
                                        font.family: window.iconFont
                                        font.pixelSize: window.s(15)
                                        color: window.activeTab === modelData.id ? ThemeBackend.text : ThemeBackend.subtext0
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: modelData.label
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: window.s(12.5)
                                        font.bold: true
                                        color: window.activeTab === modelData.id ? ThemeBackend.text : ThemeBackend.subtext0
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.activeTab = modelData.id;
                                        window.expandedId = "";
                                    }
                                }
                            }
                        }
                    }
                }

                // List
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: window.s(6)
                    opacity: window.introContent
                    boundsBehavior: Flickable.StopAtBounds
                    model: window.activeTab === "wifi" ? window.wifiList : window.btList

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: !window.loaded ? "Loading…" : (window.activeTab === "wifi" ? "No saved networks" : "No paired devices")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(12)
                        color: ThemeBackend.subtext0
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool isWifi: window.activeTab === "wifi"
                        readonly property string itemId: isWifi ? modelData.uuid : modelData.mac
                        readonly property bool expanded: window.expandedId === itemId
                        readonly property bool connected: isWifi ? modelData.active : modelData.connected
                        readonly property bool busy: window.busyId === itemId

                        width: list.width
                        height: header.height + (expanded ? actions.implicitHeight + window.s(10) : 0) + window.s(16)
                        radius: ThemeBackend.borderRadius
                        color: expanded ? ThemeBackend.surface0 : (rowMouse.containsMouse ? Qt.rgba(ThemeBackend.surface0.r, ThemeBackend.surface0.g, ThemeBackend.surface0.b, 0.6) : "transparent")
                        border.color: connected ? Qt.rgba(window.tabColor.r, window.tabColor.g, window.tabColor.b, 0.6) : (expanded ? ThemeBackend.surface1 : "transparent")
                        border.width: 1
                        clip: true
                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: rowMouse
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: header.height + window.s(16)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                window.expandedId = row.expanded ? "" : row.itemId;
                                window.confirmForgetId = "";
                            }
                        }

                        RowLayout {
                            id: header
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: window.s(8)
                            anchors.leftMargin: window.s(12)
                            anchors.rightMargin: window.s(12)
                            spacing: window.s(12)

                            Rectangle {
                                Layout.preferredWidth: window.s(36)
                                Layout.preferredHeight: window.s(36)
                                radius: ThemeBackend.borderRadius
                                color: row.connected ? Qt.rgba(window.tabColor.r, window.tabColor.g, window.tabColor.b, 0.2) : ThemeBackend.mantle
                                Text {
                                    anchors.centerIn: parent
                                    text: row.isWifi ? window.wifiIcon(row.modelData) : window.btIcon(row.modelData)
                                    font.family: window.iconFont
                                    font.pixelSize: window.s(18)
                                    color: row.connected ? window.tabColor : ((row.isWifi && !row.modelData.inRange) ? ThemeBackend.overlay1 : ThemeBackend.text)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: window.s(2)
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(13)
                                    font.bold: true
                                    color: ThemeBackend.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: window.s(10.5)
                                    color: row.connected ? window.tabColor : ThemeBackend.subtext0
                                    text: {
                                        let m = row.modelData;
                                        let parts = [];
                                        if (row.isWifi) {
                                            parts.push(m.active ? "Connected" : (m.inRange ? "In range" : "Not in range"));
                                            if (m.inRange) parts.push(m.signal + "%");
                                            if (m.security) parts.push(m.security);
                                            if (!m.autoconnect) parts.push("auto-connect off");
                                        } else {
                                            parts.push(m.connected ? "Connected" : "Paired");
                                            if (m.battery >= 0) parts.push("󰥉 " + m.battery + "%");
                                            if (!m.trusted) parts.push("not trusted");
                                        }
                                        return parts.join(" · ");
                                    }
                                }
                            }

                            LoaderIcon {
                                visible: row.busy
                                Layout.preferredWidth: window.s(16)
                                Layout.preferredHeight: window.s(16)
                                accentColor: window.tabColor
                                running: row.busy
                            }

                            Text {
                                text: row.expanded ? "󰅃" : "󰅀"
                                font.family: window.iconFont
                                font.pixelSize: window.s(16)
                                color: ThemeBackend.subtext0
                            }
                        }

                        // Expanded actions
                        ColumnLayout {
                            id: actions
                            visible: row.expanded
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: header.bottom
                            anchors.topMargin: window.s(14)
                            anchors.leftMargin: window.s(12)
                            anchors.rightMargin: window.s(12)
                            spacing: window.s(8)

                            Flow {
                                Layout.fillWidth: true
                                spacing: window.s(6)

                                ActionChip {
                                    visible: row.isWifi ? (row.connected || row.modelData.inRange) : true
                                    icon: row.connected ? "󰖪" : "󰖩"
                                    label: row.connected ? "Disconnect" : "Connect"
                                    accent: window.tabColor
                                    onClicked: {
                                        let m = row.modelData;
                                        if (row.isWifi)
                                            window.runAction(row.itemId, [m.active ? "wifi-down" : "wifi-up", m.uuid], (m.active ? "Disconnected from " : "Connected to ") + m.name);
                                        else
                                            window.runAction(row.itemId, [m.connected ? "bt-disconnect" : "bt-connect", m.mac], (m.connected ? "Disconnected " : "Connected ") + m.name);
                                    }
                                }

                                ActionChip {
                                    visible: row.isWifi
                                    icon: "󰁪"
                                    label: "Auto-connect"
                                    accent: ThemeBackend.green
                                    on: row.isWifi && row.modelData.autoconnect
                                    onClicked: window.runAction(row.itemId, ["wifi-autoconnect", row.modelData.uuid, row.modelData.autoconnect ? "no" : "yes"],
                                                                "Auto-connect " + (row.modelData.autoconnect ? "off" : "on") + " for " + row.modelData.name)
                                }

                                ActionChip {
                                    visible: !row.isWifi
                                    icon: "󰒘"
                                    label: "Trusted"
                                    accent: ThemeBackend.green
                                    on: !row.isWifi && row.modelData.trusted
                                    onClicked: window.runAction(row.itemId, ["bt-trust", row.modelData.mac, row.modelData.trusted ? "no" : "yes"],
                                                                (row.modelData.trusted ? "Untrusted " : "Trusted ") + row.modelData.name)
                                }

                                ActionChip {
                                    visible: row.isWifi
                                    readonly property string revealed: window.revealedPasswords[row.itemId] !== undefined ? window.revealedPasswords[row.itemId] : ""
                                    icon: revealed !== "" ? "󰆏" : "󰈈"
                                    label: revealed !== "" ? "Copy password" : "Show password"
                                    onClicked: {
                                        if (revealed !== "") {
                                            Quickshell.execDetached(["wl-copy", revealed]);
                                            window.statusIsError = false;
                                            window.statusText = "Password copied";
                                            statusClear.restart();
                                            return;
                                        }
                                        let id = row.itemId;
                                        window.runAction(id, ["wifi-password", row.modelData.uuid], "", function(out) {
                                            let r = Object.assign({}, window.revealedPasswords);
                                            r[id] = out !== "" ? out : "(no password)";
                                            window.revealedPasswords = r;
                                        });
                                    }
                                }

                                ActionChip {
                                    icon: "󰆴"
                                    danger: true
                                    label: window.confirmForgetId === row.itemId ? "Click again to forget" : "Forget"
                                    on: window.confirmForgetId === row.itemId
                                    accent: ThemeBackend.red
                                    onClicked: row.isWifi
                                        ? window.forget(row.itemId, ["wifi-forget", row.modelData.uuid], row.modelData.name)
                                        : window.forget(row.itemId, ["bt-forget", row.modelData.mac], row.modelData.name)
                                }
                            }

                            // Revealed password
                            Text {
                                Layout.fillWidth: true
                                visible: row.isWifi && window.revealedPasswords[row.itemId] !== undefined
                                text: "󰌋  " + (window.revealedPasswords[row.itemId] || "")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(12)
                                color: ThemeBackend.text
                                wrapMode: Text.WrapAnywhere
                            }

                            InlineInput {
                                Layout.fillWidth: true
                                visible: row.isWifi && row.modelData.security !== "Open"
                                placeholder: "New password"
                                focusColor: window.tabColor
                                secret: true
                                actionLabel: "Change"
                                onSubmitted: (value) => {
                                    let id = row.itemId;
                                    window.runAction(id, ["wifi-set-password", row.modelData.uuid, value], "Password changed for " + row.modelData.name, function() {
                                        let r = Object.assign({}, window.revealedPasswords);
                                        delete r[id];
                                        window.revealedPasswords = r;
                                    });
                                    text = "";
                                }
                            }

                            InlineInput {
                                Layout.fillWidth: true
                                visible: !row.isWifi
                                placeholder: "Rename device"
                                focusColor: window.tabColor
                                actionLabel: "Rename"
                                onSubmitted: (value) => {
                                    window.runAction(row.itemId, ["bt-rename", row.modelData.mac, value], "Renamed to " + value);
                                    text = "";
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.isWifi ? "UUID " + row.modelData.uuid : row.modelData.mac
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(9.5)
                                color: ThemeBackend.overlay1
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Status line
                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(16)
                    text: window.statusText
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: window.s(11)
                    color: window.statusIsError ? ThemeBackend.red : ThemeBackend.green
                }
            }
        }
    }
}
