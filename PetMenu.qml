import QtQuick
import Quickshell
import Quickshell.Wayland
import "Sprites.js" as Sprites

// Context menu (right-click on the pet, or SUPER+SHIFT+left-click).
// Mirrors the CLI: every change goes through pet.setConfig(), i.e. the same
// ~/.config/desktop-pet/config.json the `desktop-pet` command edits.
// While open it covers the pet's monitor with an invisible click catcher
// (click outside closes) and takes keyboard focus (Escape closes); closed,
// the window is unmapped.
PanelWindow {
  id: menu

  required property var pet
  property bool open: false
  readonly property var h: pet.host
  // Omarchy popup look through the host seam, with fallbacks.
  readonly property color bg: h && h.popupBg !== undefined ? h.popupBg : pet.cBg
  readonly property color fg: h && h.popupFg !== undefined ? h.popupFg : pet.cFg
  readonly property color border: h && h.popupBorder !== undefined ? h.popupBorder : pet.cAccent
  readonly property color selBg: h && h.selBg !== undefined ? h.selBg : Qt.rgba(pet.cFg.r, pet.cFg.g, pet.cFg.b, 0.1)
  readonly property color selFg: h && h.selFg !== undefined ? h.selFg : pet.cAccent
  readonly property int radius: h && h.radius !== undefined ? h.radius : 0
  readonly property string font: pet.uiFont
  readonly property color dimFg: Qt.rgba(fg.r, fg.g, fg.b, 0.6)

  function show() {
    card.petX = pet.posX + pet.sprLeft
    card.petY = pet.posY + pet.sprTop
    open = true
    card.forceActiveFocus()
  }
  function hide() { open = false; nameField.text = ""; sayField.text = "" }

  visible: open
  screen: pet.petScreen
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-pet-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: menu.hide()
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool on: false
    signal picked()
    implicitWidth: chipText.implicitWidth + 12
    implicitHeight: chipText.implicitHeight + 6
    radius: Math.min(menu.radius, 4)
    color: on ? menu.selBg : (chipMouse.containsMouse ? Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.06) : "transparent")
    border.width: 1
    border.color: on ? menu.selFg : Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.22)
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.on ? menu.selFg : menu.fg
      font.family: menu.font; font.pixelSize: 11; font.bold: chip.on
    }
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: chip.picked() }
  }

  component Label: Text {
    color: menu.dimFg
    font.family: menu.font; font.pixelSize: 10
    width: 56
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  }

  component Field: Rectangle {
    id: field
    property alias text: input.text
    property string placeholder: ""
    signal accepted(string value)
    width: 168; height: 22
    color: "transparent"
    radius: Math.min(menu.radius, 4)
    border.width: 1
    border.color: input.activeFocus ? menu.selFg : Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.22)
    TextInput {
      id: input
      anchors.fill: parent; anchors.margins: 4
      color: menu.fg
      font.family: menu.font; font.pixelSize: 11
      clip: true
      maximumLength: 200
      selectByMouse: true
      onAccepted: { if (text.trim() !== "") field.accepted(text.trim()) }
      Keys.onEscapePressed: menu.hide()
    }
    Text {
      anchors.fill: input
      visible: input.text === "" && !input.activeFocus
      text: field.placeholder
      color: Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.35)
      font: input.font
    }
  }

  Rectangle {
    id: card
    focus: true
    Keys.onEscapePressed: menu.hide()
    width: 284
    height: col.implicitHeight + 20
    // placed once when the menu opens (the pet pauses meanwhile)
    property real petX: 0
    property real petY: 0
    x: {
      var right = petX + pet.spr + 8
      var nx = right + width <= menu.width - 8 ? right : petX - width - 8
      return Math.max(8, Math.min(menu.width - width - 8, nx))
    }
    y: Math.max(8, Math.min(menu.height - height - 8, petY + pet.spr / 2 - height / 2))
    color: menu.bg
    radius: menu.radius
    border.width: 2
    border.color: menu.border

    MouseArea { anchors.fill: parent }   // swallow clicks so they don't close the menu

    Column {
      id: col
      x: 10; y: 10
      width: parent.width - 20
      spacing: 6

      // ---- stats header
      Text {
        text: (pet.egg ? "an egg" : pet.displayName + "  ·  " + pet.stageName + " " + Sprites.PETS[pet.pet].label)
              + "  ·  " + Math.floor(pet.ageDays) + (Math.floor(pet.ageDays) === 1 ? " day" : " days") + " old"
        width: parent.width
        wrapMode: Text.Wrap
        color: menu.selFg
        font.family: menu.font; font.pixelSize: 13; font.bold: true
      }
      Repeater {
        model: [["hunger", pet.hunger], ["happy", pet.happiness], ["energy", pet.energy]]
        Row {
          required property var modelData
          spacing: 6
          Label { text: modelData[0] }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Repeater {
              model: 15
              Rectangle {
                required property int index
                width: 9; height: 7
                color: index < Math.round(modelData[1] / 100 * 15) ? menu.selFg : Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.15)
              }
            }
          }
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "mood: " + pet.mood() + "  ·  ate " + pet.lettersEaten + " letters" + (pet.heist ? "  ·  has your " + pet.heist.id + "!" : "")
        color: menu.dimFg
        font.family: menu.font; font.pixelSize: 10
      }
      Rectangle { width: parent.width; height: 1; color: Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.15) }

      Row {
        spacing: 4
        Label { text: "pet" }
        Repeater {
          model: Sprites.PET_NAMES
          Chip { required property string modelData; label: modelData; on: pet.cfg.pet === modelData
                 onPicked: { pet.setConfig("pet", modelData); menu.hide() } }
        }
      }
      Row {
        spacing: 4
        Label { text: "size" }
        Repeater {
          model: [50, 100, 200]
          Chip { required property int modelData; label: modelData + "%"; on: pet.sizePct === modelData
                 onPicked: { pet.setConfig("size", modelData); menu.hide() } }
        }
      }
      Row {
        spacing: 4
        Label { text: "accessory" }
        Chip { label: "auto"; on: pet.cfg.accessory === "auto"; onPicked: pet.setConfig("accessory", "auto") }
        Chip { label: "none"; on: pet.cfg.accessory === "none"; onPicked: pet.setConfig("accessory", "none") }
        Chip {
          readonly property bool custom: pet.cfg.accessory !== "auto" && pet.cfg.accessory !== "none"
          label: "‹ " + (custom ? pet.cfg.accessory : "pick") + " ›"
          on: custom
          onPicked: {
            var list = Sprites.ACCESSORIES
            var i = list.indexOf(pet.cfg.accessory)
            pet.setConfig("accessory", list[(i + 1) % list.length])
          }
        }
      }
      Row {
        spacing: 4
        Label { text: "color" }
        Chip { label: "theme"; on: !pet.cfg.color || pet.cfg.color === "theme"; onPicked: pet.setConfig("color", "theme") }
        Chip { label: "complement"; on: pet.cfg.color === "complement"; onPicked: pet.setConfig("color", "complement") }
        Field {
          width: 62
          placeholder: Sprites.isHex(pet.cfg.color) ? pet.cfg.color : "#hex"
          onAccepted: function (v) { var x = v.charAt(0) === "#" ? v : "#" + v; if (Sprites.isHex(x)) pet.setConfig("color", x.toLowerCase()) }
        }
      }
      Row {
        spacing: 4
        Label { text: "name" }
        Field { id: nameField; placeholder: (pet.petName || "unnamed") + "  (Enter to rename)"
                onAccepted: function (v) { var n = Object.assign({}, pet.cfg.names || {}); n[pet.pet] = v.substring(0, 24); pet.setConfig("names", n); menu.hide() } }
      }
      Row {
        spacing: 4
        Label { text: "say" }
        Field { id: sayField; placeholder: "Say something…"
                onAccepted: function (v) { pet.sayToPet(v); menu.hide() } }
      }
      Rectangle { width: parent.width; height: 1; color: Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.15) }

      Row {
        spacing: 4
        Label { text: "eat text" }
        Chip { label: "on"; on: pet.cfg.eat; onPicked: pet.setConfig("eat", true) }
        Chip { label: "off"; on: !pet.cfg.eat; onPicked: pet.setConfig("eat", false) }
      }
      Row {
        spacing: 4
        Label { text: "goblin" }
        Chip { label: "steals icons"; on: pet.cfg.goblinSteal; onPicked: pet.setConfig("goblinSteal", true) }
        Chip { label: "off"; on: !pet.cfg.goblinSteal; onPicked: pet.setConfig("goblinSteal", false) }
      }
      Row {
        spacing: 4
        Label { text: "brain" }
        Chip { label: "on"; on: pet.cfg.brain; onPicked: pet.setConfig("brain", true) }
        Chip { label: "off"; on: !pet.cfg.brain; onPicked: pet.setConfig("brain", false) }
        Chip { label: "share title"; on: pet.cfg.brainContext; onPicked: pet.setConfig("brainContext", !pet.cfg.brainContext) }
      }
      Row {
        spacing: 4
        Label { text: "play" }
        Chip { label: "fetch on"; on: pet.cfg.fetch; onPicked: pet.setConfig("fetch", true) }
        Chip { label: "off"; on: !pet.cfg.fetch; onPicked: pet.setConfig("fetch", false) }
        Chip { label: "buddy"; on: pet.cfg.buddy; onPicked: pet.setConfig("buddy", !pet.cfg.buddy) }
      }
      Row {
        spacing: 4
        Label { text: "chatty" }
        Repeater {
          model: ["off", "low", "normal", "high"]
          Chip { required property string modelData; label: modelData; on: pet.cfg.chatty === modelData
                 onPicked: pet.setConfig("chatty", modelData) }
        }
      }
      Rectangle { width: parent.width; height: 1; color: Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.15) }

      Row {
        spacing: 4
        Chip { label: "feed"; onPicked: { menu.hide(); pet.giveTreat(20, true) } }
        Chip { label: "throw ball"; visible: pet.cfg.fetch; onPicked: { menu.hide(); pet.fetch() } }
        Chip { label: "heal"; onPicked: { menu.hide(); pet.healAll(); pet.bubble("All better! Text and dock restored.") } }
        Chip { label: "turn off"; onPicked: { menu.hide(); pet.turnOff() } }
      }
    }
  }
}
