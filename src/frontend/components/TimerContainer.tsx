/** @jsxImportSource https://esm.sh/react@18.2.0 */

import React, {
   useCallback,
   useEffect,
   useMemo,
   useState,
} from "https://esm.sh/react@18.2.0";
import { formatTime, formatMinutes } from "../../shared/utils.ts";
import type { SessionStats, TimerState } from "../../shared/types.ts";

// Component imports
import { SessionStatsDisplay } from "./SessionStats.tsx";
import { TimerDisplay } from "./TimerDisplay.tsx";

// Timer action utilities
import * as TimerActions from "../utils/timer-actions.ts";

interface TimerContainerProps {
   state: TimerState;
   setState: React.Dispatch<React.SetStateAction<TimerState>>;
   showNotification: (
      message: string,
      type?: "success" | "info" | "warning"
   ) => void;
}

export const TimerContainer = React.memo(function TimerContainer({
   state,
   setState,
   showNotification,
}: TimerContainerProps) {
   const [currentTime, setCurrentTime] = useState(Date.now());

   useEffect(() => {
      if (state.mode === "idle") {
         return;
      }

      const interval = setInterval(() => setCurrentTime(Date.now()), 1000);
      return () => clearInterval(interval);
   }, [state.mode]);

   const startWork = useCallback(() => {
      const result = TimerActions.startWork(state);
      setState(result.newState);
      if (result.currentTime) {
         setCurrentTime(result.currentTime);
      }
      if (result.notification) {
         showNotification(
            result.notification.message,
            result.notification.type
         );
      }
   }, [state, setState, showNotification]);

   const takeBreak = useCallback(() => {
      const result = TimerActions.takeBreak(state);
      setState(result.newState);
      if (result.currentTime) {
         setCurrentTime(result.currentTime);
      }
      if (result.notification) {
         showNotification(
            result.notification.message,
            result.notification.type
         );
      }
   }, [state, setState, showNotification]);

   const resumeWork = useCallback(() => {
      const result = TimerActions.resumeWork(state);
      setState(result.newState);
      if (result.currentTime) {
         setCurrentTime(result.currentTime);
      }
      if (result.notification) {
         showNotification(
            result.notification.message,
            result.notification.type
         );
      }
   }, [state, setState, showNotification]);

   const handleInterruption = useCallback(() => {
      const result = TimerActions.handleInterruption(state);
      setState(result.newState);
      if (result.notification) {
         showNotification(
            result.notification.message,
            result.notification.type
         );
      }
   }, [state, setState, showNotification]);

   const takeBigBreak = useCallback(() => {
      const result = TimerActions.takeBigBreak(state);
      setState(result.newState);
      if (result.notification) {
         showNotification(
            result.notification.message,
            result.notification.type
         );
      }
   }, [state, setState, showNotification]);

   const currentSessionTime = useMemo(() => {
      if (state.mode === "working" && state.workStartTime) {
         return Math.max(
            0,
            Math.floor((currentTime - state.workStartTime) / 1000)
         );
      }
      if (state.mode === "breaking" && state.breakStartTime) {
         return Math.max(
            0,
            Math.floor((currentTime - state.breakStartTime) / 1000)
         );
      }
      return 0;
   }, [state.mode, state.workStartTime, state.breakStartTime, currentTime]);

   // Calculate session stats - memoized to prevent unnecessary recalculations
   const stats = useMemo((): SessionStats => {
      let workTime = state.totalWorkTime;
      let breakTime = state.totalBreakTime;

      if (state.mode === "working" && state.workStartTime) {
         workTime += (currentTime - state.workStartTime) / 1000 / 60;
      }
      if (state.mode === "breaking" && state.breakStartTime) {
         const currentBreakTime =
            (currentTime - state.breakStartTime) / 1000 / 60;
         breakTime += Math.min(currentBreakTime, state.savedBreakMinutes);
      }

      const totalTime = workTime + breakTime;
      const efficiency = totalTime > 0 ? (workTime / totalTime) * 100 : 0;

      return { workTime, breakTime, efficiency };
   }, [
      state.totalWorkTime,
      state.totalBreakTime,
      state.mode,
      state.workStartTime,
      state.breakStartTime,
      state.savedBreakMinutes,
      currentTime,
   ]);

   return (
      <>
         <TimerDisplay
            state={state}
            currentSessionTime={currentSessionTime}
            formatTime={formatTime}
            formatMinutes={formatMinutes}
            onStartWork={startWork}
            onTakeBreak={takeBreak}
            onResumeWork={resumeWork}
            onInterruption={handleInterruption}
            onBigBreak={takeBigBreak}
         />

         <SessionStatsDisplay stats={stats} formatMinutes={formatMinutes} />
      </>
   );
});
