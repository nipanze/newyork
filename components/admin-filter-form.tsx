import Link from "next/link";
import { Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getParam, hasFilters, type DashboardSearchParams } from "@/lib/dashboard-filters";

type Option = {
  label: string;
  value: string;
};

type Field =
  | {
      name: string;
      label: string;
      type?: "text" | "date";
      placeholder?: string;
    }
  | {
      name: string;
      label: string;
      type: "select";
      options: Option[];
    };

export function AdminFilterForm({
  searchParams,
  fields,
  resetHref,
}: {
  searchParams: DashboardSearchParams;
  fields: Field[];
  resetHref: string;
}) {
  const filterKeys = fields.map((field) => field.name);

  return (
    <form className="rounded-md border border-paper-300 bg-white p-4 shadow-sm">
      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
        {fields.map((field) => (
          <label key={field.name} className="space-y-1">
            <span className="text-xs font-medium uppercase tracking-wide text-ink-500">
              {field.label}
            </span>
            {field.type === "select" ? (
              <select
                name={field.name}
                defaultValue={getParam(searchParams, field.name)}
                className="flex h-9 w-full rounded-md border border-paper-300 bg-white px-3 py-1 text-sm text-ink-900 shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink-700"
              >
                {field.options.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            ) : (
              <Input
                name={field.name}
                type={field.type ?? "text"}
                defaultValue={getParam(searchParams, field.name)}
                placeholder={field.placeholder}
              />
            )}
          </label>
        ))}
      </div>
      <input type="hidden" name="page" value="1" />
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <Button type="submit" size="sm">
          <Search className="h-3.5 w-3.5" /> Apply filters
        </Button>
        {hasFilters(searchParams, filterKeys) ? (
          <Link
            href={resetHref}
            className="inline-flex h-8 items-center justify-center gap-2 rounded-md border border-paper-300 px-3 text-xs font-medium text-ink-700 hover:bg-paper-100"
          >
            <X className="h-3.5 w-3.5" /> Clear
          </Link>
        ) : null}
      </div>
    </form>
  );
}
