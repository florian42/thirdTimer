/** @jsxImportSource https://esm.sh/react@18.2.0?dev */

import React from "https://esm.sh/react@18.2.0";
import { Link } from "./Link.tsx";

export const SOURCE_URL = "https://val.town/x/nbbaier/thirdTimer";

export const Footer = React.memo(function Footer() {
   return (
      <footer className="flex gap-2 items-center p-4 mx-auto my-0 max-w-5xl text-xs">
         <div className="m-auto" />
         <div>
            Third Time is built on Val Town |{" "}
            <Link href={SOURCE_URL}>View Source</Link>
         </div>
      </footer>
   );
});
