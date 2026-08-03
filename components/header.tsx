import { LogoutButton } from "@/components/logout-button";
import { initials } from "@/lib/utils";

export function Header({
  title,
  description,
  adminName,
}: {
  title: string;
  description?: string;
  adminName?: string | null;
}) {
  return (
    <header className="flex h-16 shrink-0 items-center justify-between border-b border-paper-300 bg-white px-6">
      <div>
        <h1 className="text-base font-semibold text-ink-900">{title}</h1>
        {description ? <p className="text-xs text-ink-500">{description}</p> : null}
      </div>
      <div className="flex items-center gap-3">
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-ink-900 text-xs font-semibold text-paper-50">
          {initials(adminName)}
        </div>
        <LogoutButton />
      </div>
    </header>
  );
}
