import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { buildQueryString, type DashboardSearchParams } from "@/lib/dashboard-filters";

export function Pagination({
  page,
  pageSize,
  total,
  searchParams,
  basePath,
}: {
  page: number;
  pageSize: number;
  total: number;
  searchParams: DashboardSearchParams;
  basePath: string;
}) {
  const pageCount = Math.max(1, Math.ceil(total / pageSize));
  const prevHref = `${basePath}?${buildQueryString(searchParams, { page: Math.max(1, page - 1) })}`;
  const nextHref = `${basePath}?${buildQueryString(searchParams, { page: Math.min(pageCount, page + 1) })}`;

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-paper-300 bg-white px-4 py-3 text-sm">
      <p className="text-ink-500">
        Showing page <span className="font-tabular text-ink-900">{page}</span> of{" "}
        <span className="font-tabular text-ink-900">{pageCount}</span> ·{" "}
        <span className="font-tabular text-ink-900">{total}</span> records
      </p>
      <div className="flex items-center gap-2">
        {page > 1 ? (
          <Link
            href={prevHref}
            className="inline-flex h-8 items-center gap-1 rounded-md border border-paper-300 px-3 text-xs font-medium text-ink-700 hover:bg-paper-100"
          >
            <ChevronLeft className="h-3.5 w-3.5" /> Previous
          </Link>
        ) : (
          <span className="inline-flex h-8 items-center gap-1 rounded-md border border-paper-200 px-3 text-xs font-medium text-ink-300">
            <ChevronLeft className="h-3.5 w-3.5" /> Previous
          </span>
        )}
        {page < pageCount ? (
          <Link
            href={nextHref}
            className="inline-flex h-8 items-center gap-1 rounded-md border border-paper-300 px-3 text-xs font-medium text-ink-700 hover:bg-paper-100"
          >
            Next <ChevronRight className="h-3.5 w-3.5" />
          </Link>
        ) : (
          <span className="inline-flex h-8 items-center gap-1 rounded-md border border-paper-200 px-3 text-xs font-medium text-ink-300">
            Next <ChevronRight className="h-3.5 w-3.5" />
          </span>
        )}
      </div>
    </div>
  );
}
