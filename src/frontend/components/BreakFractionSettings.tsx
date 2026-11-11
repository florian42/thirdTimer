/** @jsxImportSource https://esm.sh/react@18.2.0 */

import React from "https://esm.sh/react@18.2.0";
import type { BreakFraction } from "../../shared/types.ts";
import { Card, CardHeader } from "./Card.tsx";
import { Button } from "./Button.tsx";

const BREAK_FRACTIONS: BreakFraction[] = [
   { value: 1 / 2, label: "1/2", description: "Lazy (67% work time)" },
   { value: 1 / 3, label: "1/3", description: "Standard (75% work time)" },
   { value: 1 / 4, label: "1/4", description: "Industrious (80% work time)" },
   { value: 1 / 5, label: "1/5", description: "Hard (83% work time)" },
   { value: 1 / 6, label: "1/6", description: "Grinding (86% work time)" },
];

interface BreakFractionSettingsProps {
   currentBreakFraction: number;
   onBreakFractionChange: (fraction: number) => void;
}

export const BreakFractionSettings = React.memo(function BreakFractionSettings({
   currentBreakFraction,
   onBreakFractionChange,
}: BreakFractionSettingsProps) {
   return (
      <Card>
         <CardHeader>Break Fraction</CardHeader>
         <div className="grid grid-cols-5 gap-2">
            {BREAK_FRACTIONS.map((fraction) => (
               <Button
                  type="button"
                  key={fraction.value}
                  onClick={() => onBreakFractionChange(fraction.value)}
                  variant="neutral"
                  size="sm"
                  className={
                     currentBreakFraction === fraction.value
                        ? "bg-blue(300 hover:400)"
                        : "bg-gray(200 hover:300)"
                  }
                  title={fraction.description}
               >
                  {fraction.label}
               </Button>
            ))}
         </div>
         <p className="text(sm gray-600) mt-4">
            Current:{" "}
            {
               BREAK_FRACTIONS.find((f) => f.value === currentBreakFraction)
                  ?.description
            }
         </p>
      </Card>
   );
});
