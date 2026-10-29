import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveDateRange } from '../lib/date-presets.mjs';

test('computes presets accurately relative to reference date', () => {
  const ref = new Date('2026-10-27T12:00:00Z'); // Tuesday
  assert.deepEqual(resolveDateRange({ preset: 'today', now: ref }), {
    fromDate: '2026-10-27',
    toDate: '2026-10-27',
    label: 'Today (2026-10-27)',
  });
  assert.deepEqual(resolveDateRange({ preset: 'yesterday', now: ref }), {
    fromDate: '2026-10-26',
    toDate: '2026-10-26',
    label: 'Yesterday (2026-10-26)',
  });
  assert.deepEqual(resolveDateRange({ preset: 'last-7-days', now: ref }), {
    fromDate: '2026-10-21',
    toDate: '2026-10-27',
    label: 'Last 7 Days (2026-10-21 -> 2026-10-27)',
  });
  assert.deepEqual(resolveDateRange({ preset: 'this-week', now: ref }), {
    fromDate: '2026-10-26',
    toDate: '2026-10-27',
    label: 'This Week (2026-10-26 -> 2026-10-27)',
  });
  assert.deepEqual(resolveDateRange({ preset: 'last-week', now: ref }), {
    fromDate: '2026-10-19',
    toDate: '2026-10-25',
    label: 'Last Week (2026-10-19 -> 2026-10-25)',
  });
  assert.deepEqual(resolveDateRange({ preset: 'this-month', now: ref }), {
    fromDate: '2026-10-01',
    toDate: '2026-10-27',
    label: 'This Month (2026-10-01 -> 2026-10-27)',
  });
  assert.deepEqual(resolveDateRange({ preset: 'last-month', now: ref }), {
    fromDate: '2026-09-01',
    toDate: '2026-09-30',
    label: 'Last Month (2026-09-01 -> 2026-09-30)',
  });
});

test('validates custom date ranges and rejects reversed or malformed dates', () => {
  assert.throws(() => resolveDateRange({ fromDate: '2026-10-28', toDate: '2026-10-01' }), /fromDate cannot be after toDate/);
  assert.throws(() => resolveDateRange({ fromDate: 'not-a-date' }), /YYYY-MM-DD/);
});
