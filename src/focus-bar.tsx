import { Icon, MenuBarExtra } from "@raycast/api";

export default function FocusBar() {
  return (
    <MenuBarExtra icon={Icon.Clock} tooltip="Focus Bar">
      <MenuBarExtra.Item
        title="Start Focus Session"
        icon={Icon.Play}
        onAction={() => console.log("start")}
      />
      <MenuBarExtra.Item
        title="Stop"
        icon={Icon.Stop}
        onAction={() => console.log("stop")}
      />
    </MenuBarExtra>
  );
}
