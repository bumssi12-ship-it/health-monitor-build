import test from "node:test";
import assert from "node:assert/strict";
import {
  parseCSV,
  normalizeBackup,
  mergeUnique,
  dailyMetricSeries,
  sleepDailySeries,
  dashboardSummary,
} from "./core.mjs";

test("CSV parser handles commas, quotes, and newlines", () => {
  const rows = parseCSV(
    'a,b,c\n1,"hello,world","x""y"\n2,"line1\nline2",z\n'
  );
  assert.equal(rows.length, 2);
  assert.equal(rows[0].b, "hello,world");
  assert.equal(rows[0].c, 'x"y');
  assert.equal(rows[1].b, "line1\nline2");
});

test("backup v1 normalizes user records", () => {
  const out = normalizeBackup({
    formatVersion: 1,
    symptoms: [
      {
        eventID: "s1",
        timestamp: "2026-01-01T00:00:00Z",
        symptom: "x",
        posture: "standing",
        severity: 5,
        heartRate: 88,
        note: "",
      },
    ],
    medications: [],
    orthostaticSessions: [],
  });

  assert.equal(
    out.symptoms[0].event_id,
    "s1"
  );
  assert.equal(
    out.symptoms[0].heart_rate,
    88
  );
});

test("unsupported backup version is rejected", () => {
  assert.throws(() =>
    normalizeBackup({
      formatVersion: 9,
      symptoms: [],
      medications: [],
      orthostaticSessions: [],
    })
  );
});

test("dedupe keeps newest incoming value", () => {
  const merged = mergeUnique(
    [{ sample_uuid: "a", value: 1 }],
    [{ sample_uuid: "a", value: 2 }],
    (x) => x.sample_uuid
  );

  assert.equal(merged.length, 1);
  assert.equal(merged[0].value, 2);
});

test("daily step series deduplicates by day", () => {
  const rows = [
    {
      day_start:
        "2026-09-22T00:00:00Z",
      type: "step_count",
      value: 1000,
    },
    {
      day_start:
        "2026-09-23T00:00:00Z",
      type: "step_count",
      value: 2000,
    },
  ];

  const series = dailyMetricSeries(
    rows,
    "step_count"
  );

  assert.equal(series.length, 2);
  assert.equal(
    series.at(-1).value,
    2000
  );
});

test("sleep intervals are merged to avoid double counting", () => {
  const rows = [
    {
      type: "sleep",
      start_at:
        "2026-09-22T23:00:00Z",
      end_at:
        "2026-09-23T02:00:00Z",
    },
    {
      type: "sleep",
      start_at:
        "2026-09-23T01:30:00Z",
      end_at:
        "2026-09-23T04:00:00Z",
    },
  ];

  const series =
    sleepDailySeries(rows);

  assert.equal(series.length, 1);
  assert.equal(series[0].value, 5);
});

test("dashboard computes latest orthostatic and symptom count", () => {
  const now = new Date(
    "2026-09-23T12:00:00Z"
  );

  const summary = dashboardSummary(
    {
      healthSamples: [],
      dailyMetrics: [],
      symptoms: [
        {
          timestamp:
            "2026-09-22T12:00:00Z",
        },
        {
          timestamp:
            "2026-09-01T12:00:00Z",
        },
      ],
      medications: [],
      orthostatic: [
        {
          timestamp:
            "2026-09-22T10:00:00Z",
          peak_delta: 21,
        },
      ],
    },
    now
  );

  assert.equal(summary.symptoms7, 1);
  assert.equal(
    summary.latestOrtho.peak_delta,
    21
  );
});
