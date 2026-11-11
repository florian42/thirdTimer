/** @jsxImportSource https://esm.sh/react@18.2.0?dev */

export const Link = ({
   children,
   href,
   className = "",
}: {
   children: React.ReactNode;
   href: string;
   className?: string;
}) => (
   <a
      className={`text-blue-500 hover:underline ${className}`}
      href={href}
      rel="noreferrer"
      target="_blank"
   >
      {children}
   </a>
);
