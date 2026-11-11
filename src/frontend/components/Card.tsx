/** @jsxImportSource https://esm.sh/react@18.2.0 */

interface CardProps {
   children: React.ReactNode;
   className?: string;
}
export function CardHeader({ children, className = "" }: CardProps) {
   return (
      <div className={`mb-3 text-lg font-semibold ${className}`}>
         {children}
      </div>
   );
}

export function Card({ children, className = "" }: CardProps) {
   return (
      <div
         className={`px-6 pt-4 pb-6 my-4 bg-white rounded-lg border(2 gray-200) ${className}`}
      >
         {children}
      </div>
   );
}
