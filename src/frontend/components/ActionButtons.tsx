/** @jsxImportSource https://esm.sh/react@18.2.0 */
import type { TimerState } from "../../shared/types.ts";
import { Button } from "./Button.tsx";

interface ActionButtonsProps {
   state: TimerState;
   onStartWork: () => void;
   onTakeBreak: () => void;
   onResumeWork: () => void;
   onInterruption: () => void;
   onBigBreak: () => void;
}

export function ActionButtons({
   state,
   onStartWork,
   onTakeBreak,
   onResumeWork,
   onInterruption,
   onBigBreak,
}: ActionButtonsProps) {
   return (
      <div className="space-y-3">
         {state.mode === "idle" && (
            <Button
               type="button"
               onClick={onStartWork}
               className="w-full"
               variant="primary"
               size="lg"
            >
               Start Working
            </Button>
         )}

         {state.mode === "working" && (
            <div className="space-y-2">
               <Button
                  type="button"
                  onClick={onTakeBreak}
                  className="w-full"
                  variant="primary"
                  size="lg"
               >
                  Take Break
               </Button>
               <div className="flex space-x-2">
                  <Button
                     type="button"
                     onClick={onInterruption}
                     className="flex-1"
                     variant="warning"
                     size="sm"
                  >
                     Interruption
                  </Button>
                  <Button
                     type="button"
                     onClick={onBigBreak}
                     className="flex-1"
                     variant="purple"
                     size="sm"
                  >
                     Big Break
                  </Button>
               </div>
            </div>
         )}

         {state.mode === "breaking" && (
            <Button
               type="button"
               onClick={onResumeWork}
               className="w-full"
               variant="primary"
               size="lg"
            >
               Resume Work
            </Button>
         )}
      </div>
   );
}
