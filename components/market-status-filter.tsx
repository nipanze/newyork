"use client";

import { useRouter, useSearchParams } from "next/navigation";

export function MarketStatusFilter({
  countries,
  currentCountry,
  currentStatus,
}: {
  countries: { code: string; name: string }[] | null;
  currentCountry?: string;
  currentStatus?: string;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  function updateFilter(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (value) {
      params.set(key, value);
    } else {
      params.delete(key);
    }
    const queryStr = params.toString();
    router.push(queryStr ? `?${queryStr}` : window.location.pathname);
  }

  return (
    <div className="flex flex-wrap gap-2">
      <select
        name="country"
        value={currentCountry ?? ""}
        className="h-9 rounded-md border border-paper-300 bg-white px-3 text-sm shadow-sm"
        onChange={(e) => updateFilter("country", e.target.value)}
      >
        <option value="">All markets</option>
        {countries?.map((c) => (
          <option key={c.code} value={c.code}>
            {c.name}
          </option>
        ))}
      </select>
      <select
        name="status"
        value={currentStatus ?? ""}
        className="h-9 rounded-md border border-paper-300 bg-white px-3 text-sm shadow-sm"
        onChange={(e) => updateFilter("status", e.target.value)}
      >
        <option value="">All statuses</option>
        <option value="active">Active</option>
        <option value="contracted">Contracted</option>
        <option value="expired">Expired</option>
        <option value="cancelled">Cancelled</option>
      </select>
    </div>
  );
}
