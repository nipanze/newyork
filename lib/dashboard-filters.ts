export const PAGE_SIZE_OPTIONS = [25, 50, 100] as const;

export type DashboardSearchParams = Record<string, string | string[] | undefined>;

export function getParam(searchParams: DashboardSearchParams, key: string) {
  const value = searchParams[key];
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

export function getPage(searchParams: DashboardSearchParams) {
  const page = Number(getParam(searchParams, "page"));
  return Number.isFinite(page) && page > 0 ? Math.floor(page) : 1;
}

export function getPageSize(searchParams: DashboardSearchParams) {
  const pageSize = Number(getParam(searchParams, "pageSize"));
  return PAGE_SIZE_OPTIONS.includes(pageSize as (typeof PAGE_SIZE_OPTIONS)[number])
    ? pageSize
    : 25;
}

export function getRange(page: number, pageSize: number) {
  const from = (page - 1) * pageSize;
  return { from, to: from + pageSize - 1 };
}

export function buildQueryString(
  current: DashboardSearchParams,
  updates: Record<string, string | number | boolean | null | undefined>
) {
  const params = new URLSearchParams();

  for (const [key, value] of Object.entries(current)) {
    const finalValue = Array.isArray(value) ? value[0] : value;
    if (finalValue) params.set(key, finalValue);
  }

  for (const [key, value] of Object.entries(updates)) {
    if (value === undefined || value === null || value === "") {
      params.delete(key);
    } else {
      params.set(key, String(value));
    }
  }

  return params.toString();
}

export function hasFilters(searchParams: DashboardSearchParams, keys: string[]) {
  return keys.some((key) => Boolean(getParam(searchParams, key)));
}

/**
 * Returns the current param value if non-empty, otherwise the supplied default.
 * Useful for giving filters a sensible initial value without polluting the URL.
 */
export function applyDefault(
  searchParams: DashboardSearchParams,
  key: string,
  defaultValue: string
): string {
  const value = getParam(searchParams, key);
  return value !== "" ? value : defaultValue;
}
