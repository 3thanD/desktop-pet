import QtQuick

// Omarchy shell plugin entry point (manifest "service"). The shell injects the
// properties below; the pet itself lives in PetCore.qml and only talks to the
// desktop through OmarchyHost.qml.
Item {
  property var manifest: null
  property var shell: null
  property var pluginRegistry: null
  property string omarchyPath: ""

  OmarchyHost { id: host }
  PetCore { host: host }
}
