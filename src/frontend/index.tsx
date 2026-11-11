/** @jsxImportSource https://esm.sh/react@18.2.0 */

import { createRoot } from "https://esm.sh/react-dom@18.2.0/client";
import { useCallback, useState } from "https://esm.sh/react@18.2.0";
import type { TimerState } from "../shared/types.ts";
import { BreakFractionSettings } from "./components/BreakFractionSettings.tsx";
import { Button } from "./components/Button.tsx";
import { Footer } from "./components/Footer.tsx";
import { HelpText } from "./components/HelpText.tsx";
import { Notification } from "./components/Notification.tsx";
import { TimerContainer } from "./components/TimerContainer.tsx";
import * as TimerActions from "./utils/timer-actions.ts";

function App() {
   const [state, setState] = useState<TimerState>(() => {
      return {
         mode: "idle",
         workStartTime: null,
         breakStartTime: null,
         savedBreakMinutes: 0,
         breakFraction: 1 / 3,
         totalWorkTime: 0,
         totalBreakTime: 0,
      };
   });

   const [notification, setNotification] = useState<{
      message: string;
      type: "success" | "info" | "warning";
   } | null>(null);

   const showNotification = useCallback(
      (message: string, type: "success" | "info" | "warning" = "info") => {
         setNotification({ message, type });
      },
      []
   );

   const resetSession = useCallback(() => {
      const result = TimerActions.resetSession(state);
      setState(result.newState);
      if (result.notification) {
         showNotification(
            result.notification.message,
            result.notification.type
         );
      }
   }, [state, showNotification]);

   const handleBreakFractionChange = useCallback((fraction: number) => {
      setState((prev) => ({
         ...prev,
         breakFraction: fraction,
      }));
   }, []);

   return (
      <div className="max-w-2xl mx-auto p-6">
         {notification && (
            <Notification
               message={notification.message}
               type={notification.type}
               onClose={() => setNotification(null)}
            />
         )}
         <div className="mb-8 text-center">
            <h1 className="mb-2 text-4xl font-bold text-gray-800">
               Third Timer
            </h1>
            <p className="text-gray-600">Work flexibly, break proportionally</p>
         </div>
         <TimerContainer
            state={state}
            setState={setState}
            showNotification={showNotification}
         />
         <BreakFractionSettings
            currentBreakFraction={state.breakFraction}
            onBreakFractionChange={handleBreakFractionChange}
         />
         <div className="text-center">
            <Button
               type="button"
               onClick={resetSession}
               variant="danger"
               size="md"
            >
               Reset Session
            </Button>
         </div>
         <HelpText />
         <Footer />
      </div>
   );
}

const rootElement = document.getElementById("root");
if (!rootElement) {
   throw new Error("Root element not found");
}
const root = createRoot(rootElement);
root.render(<App />);
