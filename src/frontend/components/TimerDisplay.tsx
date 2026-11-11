/** @jsxImportSource https://esm.sh/react@18.2.0 */
import type { TimerState } from "../../shared/types.ts";
import { ActionButtons } from "./ActionButtons.tsx";
import { Card } from "./Card.tsx";

interface TimerDisplayProps {
  state: TimerState;
  currentSessionTime: number;
  formatTime: (seconds: number) => string;
  formatMinutes: (minutes: number) => string;
  onStartWork: () => void;
  onTakeBreak: () => void;
  onResumeWork: () => void;
  onInterruption: () => void;
  onBigBreak: () => void;
}

export function TimerDisplay({
  state,
  currentSessionTime,
  formatTime,
  formatMinutes,
  onStartWork,
  onTakeBreak,
  onResumeWork,
  onInterruption,
  onBigBreak,
}: TimerDisplayProps) {
  const stateClasses = {
    working: "bg-green-100 pulse-work",
    breaking: "bg-blue-100 pulse-break",
    idle: "bg-gray-100",
  };

  return (
    <Card className="px-8 pt-8 pb-4">
      <div className="text-center">
        <div
          className={`inline-block p-6 rounded-lg mb-4 ${stateClasses[state.mode]}`}
        >
          <div className="font-mono text-6xl font-medium tabular-nums text-gray-800">
            {formatTime(currentSessionTime)}
          </div>
        </div>
        <div className="mb-4 text-xl font-semibold">
          {state.mode === "idle" && "Ready to start"}
          {state.mode === "working" && "Working"}
          {state.mode === "breaking" && "Breaking"}
        </div>
      </div>

      {state.savedBreakMinutes > 0 && (
        <div className="p-3 mb-4 bg-blue-50 rounded-lg">
          <span className="font-medium text-blue-700">
            Saved break time: {formatMinutes(state.savedBreakMinutes)}
          </span>
        </div>
      )}

      <ActionButtons
        state={state}
        onStartWork={onStartWork}
        onTakeBreak={onTakeBreak}
        onResumeWork={onResumeWork}
        onInterruption={onInterruption}
        onBigBreak={onBigBreak}
      />
    </Card>
  );
}