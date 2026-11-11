/** @jsxImportSource https://esm.sh/react@18.2.0 */

import React from "https://esm.sh/react@18.2.0";
import { Card } from "./Card.tsx";
import { Link } from "./Link.tsx";

const ListItem = ({ children }: { children: React.ReactNode }) => (
   <li className="pl-1">{children}</li>
);

export const HelpText = React.memo(function HelpText() {
   return (
      <Card>
         <h3 className="mb-3 text-lg font-semibold">How it works</h3>
         <ul className="space-y-1 text-sm list(disc inside) sm:text-base">
            <ListItem>Work for any duration you choose</ListItem>
            <ListItem>Earn break time equal to work time / fraction</ListItem>
            <ListItem>Unused break time is saved for later</ListItem>
            <ListItem>Use "Interruption" for non-work interruptions</ListItem>
            <ListItem>Use "Big Break" for meals (consumes saved time)</ListItem>
            <ListItem>
               See{" "}
               <Link href="https://www.lesswrong.com/posts/RWu8eZqbwgB9zaerh/third-time-a-better-way-to-work">
                  this LessWrong article
               </Link>{" "}
               for more info!
            </ListItem>
         </ul>
      </Card>
   );
});
