/** @jsxImportSource https://esm.sh/react@18.2.0 */

export type NotificationTypes = "success" | "info" | "warning" | "default";

const Icon = ({
   children,
   title,
   className,
}: {
   children: React.ReactNode;
   title: string;
   className?: string;
}) => (
   <svg
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-label={title}
      className={`w-5 h-5 translate-y-[0.25px] ${className}`}
   >
      <title>{title}</title>
      {children}
   </svg>
);

export const getAsset = (type: NotificationTypes): JSX.Element | null => {
   switch (type) {
      case "success":
         return SuccessIcon;

      case "info":
         return InfoIcon;

      case "warning":
         return WarningIcon;

      default:
         return null;
   }
};

const SuccessIcon = (
   <Icon title="Success">
      <circle cx="12" cy="12" r="10" />
      <path d="m9 12 2 2 4-4" />
   </Icon>
);

const WarningIcon = (
   <Icon title="Warning">
      <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3" />
      <path d="M12 9v4" />
      <path d="M12 17h.01" />
   </Icon>
);

const InfoIcon = (
   <Icon title="Info">
      <circle cx="12" cy="12" r="10" />
      <line x1="12" x2="12" y1="8" y2="12" />
      <line x1="12" x2="12.01" y1="16" y2="16" />
   </Icon>
);
