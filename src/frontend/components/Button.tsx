/** @jsxImportSource https://esm.sh/react@18.2.0 */

interface ButtonProps {
   children: React.ReactNode;
   onClick: () => void;
   variant?:
      | "primary"
      | "secondary"
      | "info"
      | "warning"
      | "purple"
      | "danger"
      | "neutral";
   size?: "sm" | "md" | "lg";
   className?: string;
   type?: "button" | "submit" | "reset";
   title?: string;
   disabled?: boolean;
}

export function Button({
   children,
   onClick,
   variant = "primary",
   size = "md",
   className = "",
   type = "button",
   title,
   disabled = false,
}: ButtonProps) {
   const baseClasses =
      "border-2 border-black text-black font-semibold rounded-lg transition-colors";

   const variantClasses = {
      primary: "bg-green(300 hover:400)",
      secondary: "bg-gray(100 hover:200)",
      info: "bg-blue(300 hover:400)",
      warning: "bg-yellow(300 hover:400)",
      purple: "bg-purple(300 hover:400)",
      danger: "bg-red(300 hover:400)",
      neutral: "",
   };

   const sizeClasses = {
      sm: "py-2 px-4 text-sm",
      md: "py-3 px-6",
      lg: "py-3 px-6 text-lg",
   };

   return (
      <button
         type={type}
         onClick={onClick}
         className={`${baseClasses} ${variantClasses[variant]} ${sizeClasses[size]} ${className}`}
         title={title}
         disabled={disabled}
      >
         {children}
      </button>
   );
}
