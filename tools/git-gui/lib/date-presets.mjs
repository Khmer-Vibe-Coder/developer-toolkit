const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function formatLocalDate(d) {
  const year = d.getUTCFullYear();
  const month = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function shiftUtcDays(baseDate, offsetDays) {
  const copy = new Date(Date.UTC(baseDate.getUTCFullYear(), baseDate.getUTCMonth(), baseDate.getUTCDate()));
  copy.setUTCDate(copy.getUTCDate() + offsetDays);
  return copy;
}

export function isValidDateString(value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && formatLocalDate(parsed) === value;
}

export const DATE_PRESETS = [
  { id: 'today', label: 'Today' },
  { id: 'yesterday', label: 'Yesterday' },
  { id: 'last-7-days', label: 'Last 7 days' },
  { id: 'this-week', label: 'This week (Mon -> Today)' },
  { id: 'last-week', label: 'Last week (Prev Mon -> Sun)' },
  { id: 'this-month', label: 'This month (1st -> Today)' },
  { id: 'last-month', label: 'Last month' },
  { id: 'last-14-days', label: 'Last 14 days' },
  { id: 'last-30-days', label: 'Last 30 days' },
];

export function resolveDateRange({ preset = '', fromDate = '', toDate = '', now = new Date() } = {}) {
  const refUtc = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
  const todayStr = formatLocalDate(refUtc);

  if (preset && preset !== 'custom' && preset !== 'ask') {
    switch (preset) {
      case 'today':
        return {
          fromDate: todayStr,
          toDate: todayStr,
          label: `Today (${todayStr})`,
        };
      case 'yesterday': {
        const y = formatLocalDate(shiftUtcDays(refUtc, -1));
        return {
          fromDate: y,
          toDate: y,
          label: `Yesterday (${y})`,
        };
      }
      case 'last-7-days':
      case '7d': {
        const from = formatLocalDate(shiftUtcDays(refUtc, -6));
        return {
          fromDate: from,
          toDate: todayStr,
          label: `Last 7 Days (${from} -> ${todayStr})`,
        };
      }
      case 'last-14-days':
      case '14d': {
        const from = formatLocalDate(shiftUtcDays(refUtc, -13));
        return {
          fromDate: from,
          toDate: todayStr,
          label: `Last 14 Days (${from} -> ${todayStr})`,
        };
      }
      case 'last-30-days':
      case '30d': {
        const from = formatLocalDate(shiftUtcDays(refUtc, -29));
        return {
          fromDate: from,
          toDate: todayStr,
          label: `Last 30 Days (${from} -> ${todayStr})`,
        };
      }
      case 'this-week': {
        // ISO day of week: 1=Mon .. 7=Sun
        const jsDay = refUtc.getUTCDay();
        const isoDow = jsDay === 0 ? 7 : jsDay;
        const diff = 1 - isoDow;
        const from = formatLocalDate(shiftUtcDays(refUtc, diff));
        return {
          fromDate: from,
          toDate: todayStr,
          label: `This Week (${from} -> ${todayStr})`,
        };
      }
      case 'last-week': {
        const jsDay = refUtc.getUTCDay();
        const isoDow = jsDay === 0 ? 7 : jsDay;
        const prevMonOffset = 1 - isoDow - 7;
        const prevSunOffset = prevMonOffset + 6;
        const from = formatLocalDate(shiftUtcDays(refUtc, prevMonOffset));
        const to = formatLocalDate(shiftUtcDays(refUtc, prevSunOffset));
        return {
          fromDate: from,
          toDate: to,
          label: `Last Week (${from} -> ${to})`,
        };
      }
      case 'this-month': {
        const from = `${todayStr.slice(0, 7)}-01`;
        return {
          fromDate: from,
          toDate: todayStr,
          label: `This Month (${from} -> ${todayStr})`,
        };
      }
      case 'last-month': {
        const firstOfThisMonth = new Date(Date.UTC(refUtc.getUTCFullYear(), refUtc.getUTCMonth(), 1));
        const lastOfPrevMonth = shiftUtcDays(firstOfThisMonth, -1);
        const firstOfPrevMonth = new Date(
          Date.UTC(lastOfPrevMonth.getUTCFullYear(), lastOfPrevMonth.getUTCMonth(), 1)
        );
        const from = formatLocalDate(firstOfPrevMonth);
        const to = formatLocalDate(lastOfPrevMonth);
        return {
          fromDate: from,
          toDate: to,
          label: `Last Month (${from} -> ${to})`,
        };
      }
      default:
        throw new Error(`Unknown date preset: '${preset}'`);
    }
  }

  if (fromDate) {
    const resolvedTo = toDate || todayStr;
    if (!isValidDateString(fromDate) || !isValidDateString(resolvedTo)) {
      throw new Error('Dates must be in YYYY-MM-DD format');
    }
    if (fromDate > resolvedTo) {
      throw new Error(`fromDate cannot be after toDate (${fromDate} > ${resolvedTo})`);
    }
    return {
      fromDate,
      toDate: resolvedTo,
      label: `Custom (${fromDate} -> ${resolvedTo})`,
    };
  }

  // Default fallback: last-7-days
  return resolveDateRange({ preset: 'last-7-days', now });
}
