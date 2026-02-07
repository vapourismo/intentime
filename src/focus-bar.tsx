import { Cache, Icon, MenuBarExtra } from "@raycast/api";

const FOCUS_DURATION = 25 * 60;
const cache = new Cache();

function getEndTime(): number | null {
  const raw = cache.get("endTime");
  if (!raw) return null;
  const endTime = Number(raw);
  if (isNaN(endTime)) return null;
  if (endTime <= Date.now()) {
    cache.remove("endTime");
    return null;
  }
  return endTime;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export default function FocusBar() {
  const endTime = getEndTime();
  const secondsLeft = endTime
    ? Math.max(0, Math.round((endTime - Date.now()) / 1000))
    : null;
  const isRunning = secondsLeft !== null && secondsLeft > 0;
  const title = isRunning ? formatTime(secondsLeft) : undefined;

  return (
    <MenuBarExtra icon={Icon.Clock} title={title} tooltip="Focus Bar">
      {!isRunning && (
        <MenuBarExtra.Item
          title="Start Focus Session"
          icon={Icon.Play}
          onAction={() => {
            cache.set("endTime", String(Date.now() + FOCUS_DURATION * 1000));
          }}
        />
      )}
      {isRunning && (
        <MenuBarExtra.Item
          title="Stop"
          icon={Icon.Stop}
          onAction={() => {
            cache.remove("endTime");
          }}
        />
      )}
    </MenuBarExtra>
  );
}
