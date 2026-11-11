/** @jsxImportSource https://esm.sh/react@18.2.0 */

import { useEffect, useRef, useState } from "https://esm.sh/react@18.2.0";
import { getAsset, type NotificationTypes } from "./Icons.tsx";

interface NotificationProps {
   message: string;
   type: NotificationTypes;
   onClose: () => void;
}

export function Notification({ message, type, onClose }: NotificationProps) {
   const [isClosing, setIsClosing] = useState(false);
   const notificationRef = useRef<HTMLDivElement>(null);

   const handleClose = () => {
      setIsClosing(true);
      setTimeout(() => {
         onClose();
      }, 300);
   };

   const handleKeyDown = (event: React.KeyboardEvent) => {
      if (event.key === "Enter" || event.key === " ") {
         event.preventDefault();
         handleClose();
      }
   };

   useEffect(() => {
      const timer = setTimeout(handleClose, 3000);

      return () => clearTimeout(timer);
   }, []);

   const icon = getAsset(type);

   const notificationColors = {
      success: "bg-[#ecfdf3] border border-[#bffcd9] text-[#008a2e]",
      info: "bg-[#f0f8ff] border border-[#dde7fd] text-[#0973dc]",
      warning: "bg-[#fffcf0] border border-[#fbeeb1] text-[#dc7609]",
   };

   return (
      <div
         ref={notificationRef}
         onClick={handleClose}
         onKeyDown={handleKeyDown}
         role="alert"
         aria-label={`${type} notification: ${message}. Press Enter or Space to dismiss.`}
         className={`notification fixed top-3 right-3 px-4 py-2 text-sm font-medium rounded-lg shadow-md transition-opacity cursor-pointer sm:top-5 sm:right-5 z-1000
             ${notificationColors[type]} ${isClosing ? "slide-out" : ""}`}
      >
         <div className="flex gap-2 items-center">
            <span className="">{icon}</span>
            <span>{message}</span>
         </div>
      </div>
   );
}
