/**
 * Formats seconds into a time string (HH:MM:SS or MM:SS)
 * @param {number} seconds - The number of seconds to format
 * @returns {string} Formatted time string
 */
export function formatTime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, "0")}:${
      secs
        .toString()
        .padStart(2, "0")
    }`;
  }
  return `${minutes.toString()}:${secs.toString().padStart(2, "0")}`;
}

/**
 * Formats minutes into a human-readable duration string
 * @param {number} minutes - The number of minutes to format
 * @returns {string} Formatted duration string (e.g., "30s", "5m", "2h 30m")
 */
export function formatMinutes(minutes: number): string {
  if (minutes < 1) return `${Math.round(minutes * 60)}s`;
  if (minutes < 60) return `${Math.round(minutes)}m`;
  const hours = Math.floor(minutes / 60);
  const mins = Math.round(minutes % 60);
  return `${hours}h ${mins}m`;
}