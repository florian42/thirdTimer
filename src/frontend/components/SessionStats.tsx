/** @jsxImportSource https://esm.sh/react@18.2.0 */

import type { SessionStats } from "../../shared/types.ts";
import { Card, CardHeader } from "./Card.tsx";
import { StatsGrid } from "./StatsGrid.tsx";

interface SessionStatsProps {
   stats: SessionStats;
   formatMinutes: (minutes: number) => string;
}

export function SessionStatsDisplay({
   stats,
   formatMinutes,
}: SessionStatsProps) {
   const statsData = [
      {
         value: formatMinutes(stats.workTime),
         label: "Work Time",
         color: "green" as const,
      },
      {
         value: formatMinutes(stats.breakTime),
         label: "Break Time",
         color: "blue" as const,
      },
      {
         value: `${Math.round(stats.efficiency)}%`,
         label: "Efficiency",
         color: "purple" as const,
      },
   ];

   return (
      <Card>
         <CardHeader>Session Stats</CardHeader>
         <StatsGrid stats={statsData} columns={3} />
      </Card>
   );
}
