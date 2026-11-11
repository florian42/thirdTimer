import type { TimerState } from "../../shared/types.ts";
import { formatMinutes } from "../../shared/utils.ts";

export interface TimerActionResult {
	newState: TimerState;
	notification?: {
		message: string;
		type: "success" | "info" | "warning";
	};
	currentTime?: number;
}

/**
 * Starts a new work session by transitioning the timer to working mode.
 *
 * @param currentState - The current timer state
 * @returns A TimerActionResult containing the new state with work mode activated,
 *          a success notification, and the current timestamp
 */
export function startWork(currentState: TimerState): TimerActionResult {
	const now = Date.now();

	return {
		newState: {
			...currentState,
			mode: "working",
			workStartTime: now,
			breakStartTime: null,
		},
		notification: {
			message: "Work session started! Focus time!",
			type: "success",
		},
		currentTime: now,
	};
}

/**
 * Transitions from work mode to break mode, calculating earned break time based on work duration.
 * Break time is calculated using the break fraction multiplied by the work duration.
 *
 * @param currentState - The current timer state (must be in working mode with workStartTime set)
 * @returns A TimerActionResult with break mode activated and calculated available break time,
 *          or unchanged state if not currently working
 */
export function takeBreak(currentState: TimerState): TimerActionResult {
	if (!currentState.workStartTime) {
		return { newState: currentState };
	}

	const now = Date.now();
	const workDuration = (now - currentState.workStartTime) / 1000 / 60; // minutes
	const earnedBreakTime = workDuration * currentState.breakFraction;
	const totalAvailableBreak = currentState.savedBreakMinutes + earnedBreakTime;

	return {
		newState: {
			...currentState,
			mode: "breaking",
			breakStartTime: now,
			workStartTime: null,
			savedBreakMinutes: totalAvailableBreak,
			totalWorkTime: currentState.totalWorkTime + workDuration,
		},
		notification: {
			message: `Break earned! You have ${formatMinutes(
				totalAvailableBreak,
			)} available`,
			type: "success",
		},
		currentTime: now,
	};
}

/**
 * Resumes work from a break, calculating consumed break time and preserving any unused break time.
 * If break time remains unused, it's saved for later use.
 *
 * @param currentState - The current timer state (should be in breaking mode with breakStartTime set)
 * @returns A TimerActionResult with work mode activated, updated break time tracking,
 *          and notification about remaining break time
 */
export function resumeWork(currentState: TimerState): TimerActionResult {
	if (!currentState.breakStartTime) {
		return { newState: currentState, currentTime: Date.now() };
	}

	const now = Date.now();
	const breakDuration = (now - currentState.breakStartTime) / 1000 / 60; // minutes
	const remainingBreakTime = Math.max(
		0,
		currentState.savedBreakMinutes - breakDuration,
	);

	const notifications = [];
	if (remainingBreakTime > 0) {
		notifications.push(
			`${formatMinutes(remainingBreakTime)} break time saved for later`,
		);
	}
	notifications.push("Back to work! Stay focused");

	return {
		newState: {
			...currentState,
			mode: "working",
			workStartTime: now,
			breakStartTime: null,
			savedBreakMinutes: remainingBreakTime,
			totalBreakTime:
				currentState.totalBreakTime +
				Math.min(breakDuration, currentState.savedBreakMinutes),
		},
		notification: {
			message: notifications.join(" "),
			type: "success",
		},
		currentTime: now,
	};
}

/**
 * Handles interruptions during work sessions by automatically transitioning to break mode.
 * Calculates earned break time based on work completed before interruption.
 *
 * @param currentState - The current timer state (must be in working mode to have effect)
 * @returns A TimerActionResult with break mode activated if work was interrupted,
 *          or unchanged state if not currently working
 */
export function handleInterruption(
	currentState: TimerState,
): TimerActionResult {
	if (!(currentState.mode === "working" && currentState.workStartTime)) {
		return { newState: currentState };
	}

	const now = Date.now();
	const workDuration = (now - currentState.workStartTime) / 1000 / 60;
	const earnedBreakTime = workDuration * currentState.breakFraction;

	return {
		newState: {
			...currentState,
			mode: "breaking",
			breakStartTime: now,
			workStartTime: null,
			savedBreakMinutes: currentState.savedBreakMinutes + earnedBreakTime,
			totalWorkTime: currentState.totalWorkTime + workDuration,
		},
		notification: {
			message: "Interruption break started automatically",
			type: "warning",
		},
		currentTime: now,
	};
}

/**
 * Initiates a big break (meal time) that consumes all accumulated break time.
 * If currently working, the work session is ended and time is added to total work time.
 *
 * @param currentState - The current timer state
 * @returns A TimerActionResult with break mode activated and all saved break time consumed
 */
export function takeBigBreak(currentState: TimerState): TimerActionResult {
	const now = Date.now();
	const newState = { ...currentState };

	if (currentState.mode === "working" && currentState.workStartTime) {
		const workDuration = (now - currentState.workStartTime) / 1000 / 60;
		newState.totalWorkTime = currentState.totalWorkTime + workDuration;
	}

	return {
		newState: {
			...newState,
			mode: "breaking",
			breakStartTime: now,
			workStartTime: null,
			savedBreakMinutes: 0, // Big breaks consume all saved time
		},
		notification: {
			message: "Big break started (meal time)",
			type: "info",
		},
		currentTime: now,
	};
}

/**
 * Resets the timer session to its initial idle state, clearing all time tracking.
 * Preserves the break fraction setting but resets all other timing data.
 *
 * @param currentState - The current timer state
 * @returns A TimerActionResult with the timer reset to idle state and all timing data cleared
 */
export function resetSession(currentState: TimerState): TimerActionResult {
	return {
		newState: {
			mode: "idle",
			workStartTime: null,
			breakStartTime: null,
			savedBreakMinutes: 0,
			breakFraction: currentState.breakFraction, // preserve break fraction
			totalWorkTime: 0,
			totalBreakTime: 0,
		},
		notification: {
			message: "Session reset",
			type: "info",
		},
	};
}
