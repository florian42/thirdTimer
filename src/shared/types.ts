export interface TimerState {
	mode: "idle" | "working" | "breaking";
	workStartTime: number | null;
	breakStartTime: number | null;
	savedBreakMinutes: number;
	breakFraction: number;
	totalWorkTime: number;
	totalBreakTime: number;
}

export interface SessionStats {
	workTime: number;
	breakTime: number;
	efficiency: number; // percentage of time spent working
}

export type BreakFraction = {
	value: number;
	label: string;
	description: string;
};
