/** @jsxImportSource https://esm.sh/react@18.2.0 */

interface StatItem {
   value: string | number;
   label: string;
   color?: "green" | "blue" | "purple" | "gray";
}

interface StatsGridProps {
   stats: StatItem[];
   columns?: number;
}

export function StatsGrid({ stats, columns = 3 }: StatsGridProps) {
   const colorClasses = {
      green: "text-green-500",
      blue: "text-blue-500",
      purple: "text-purple-500",
      gray: "text-gray-500",
   };

   const gridCols = {
      1: "grid-cols-1",
      2: "grid-cols-2",
      3: "grid-cols-3",
      4: "grid-cols-4",
      5: "grid-cols-5",
   };

   return (
      <div
         className={`grid gap-4 text-center ${ gridCols[columns as keyof typeof gridCols] }`}
      >
         {stats.map((stat, index) => (
            <div key={`${stat.label}-${index}`}>
               <div
                  className={`text-2xl font-bold ${
                     colorClasses[stat.color || "gray"]
                  }`}
               >
                  {stat.value}
               </div>
               <div className="text-sm text-gray-600">{stat.label}</div>
            </div>
         ))}
      </div>
   );
}
