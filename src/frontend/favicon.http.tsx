/** @jsxImportSource https://esm.sh/react@18.2.0 */

import { renderToString } from "npm:react-dom@18.2.0/server";

export default function () {
   const svg = renderToString(
      <svg
         xmlns="http://www.w3.org/2000/svg"
         width="24"
         height="24"
         viewBox="0 0 24 24"
         fill="none"
         stroke="#000000"
         strokeWidth="2"
         strokeLinecap="round"
         strokeLinejoin="round"
         className="lucide lucide-clock-icon lucide-clock"
         aria-label="Clock"
      >
         <circle cx="12" cy="12" r="10" />
         <title>Clock</title>
         <polyline points="12 6 12 12 16 14" />
      </svg>
   );

   return new Response(svg, {
      headers: {
         "Content-Type": "image/svg+xml",
      },
   });
}
