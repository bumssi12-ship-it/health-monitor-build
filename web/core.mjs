export const METRIC_LABELS = {
  heart_rate: "심박수",
  resting_heart_rate: "안정시 심박",
  walking_heart_rate: "보행 심박",
  hrv_sdnn: "HRV",
  respiratory_rate: "호흡수",
  step_count: "걸음수",
  sleep: "수면",
};

export function parseCSV(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    const next = text[i + 1];

    if (quoted) {
      if (ch === '"' && next === '"') {
        cell += '"';
        i += 1;
      } else if (ch === '"') {
        quoted = false;
      } else {
        cell += ch;
      }
      continue;
    }

    if (ch === '"') {
      quoted = true;
    } else if (ch === ",") {
      row.push(cell);
      cell = "";
    } else if (ch === "\n") {
      row.push(cell.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += ch;
    }
  }

  if (cell.length > 0 || row.length > 0) {
    row.push(cell.replace(/\r$/, ""));
    rows.push(row);
  }

  const clean = rows.filter((r) => r.some((v) => v !== ""));
  if (clean.length === 0) return [];

  const headers = clean[0].map((v) => v.trim());
  return clean.slice(1).map((values) => {
    const obj = {};
    headers.forEach((header, index) => {
      obj[header] = values[index] ?? "";
    });
    return obj;
  });
}

export function finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export function validDate(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function localDayKey(value) {
  const date = validDate(value);
  if (!date) return "";
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function normalizeBackup(payload) {
  if (!payload || payload.formatVersion !== 1) {
    throw new Error("지원하지 않는 Health Monitor 백업 형식입니다.");
  }

  return {
    symptoms: (payload.symptoms ?? []).map((x) => ({
      event_id: x.eventID ?? "",
      timestamp: x.timestamp ?? "",
      symptom: x.symptom ?? "",
      posture: x.posture ?? "",
      severity: finiteNumber(x.severity),
      heart_rate: finiteNumber(x.heartRate),
      note: x.note ?? "",
    })),
    medications: (payload.medications ?? []).map((x) => ({
      event_id: x.eventID ?? "",
      timestamp: x.timestamp ?? "",
      name: x.name ?? "",
      dose: finiteNumber(x.dose),
      unit: x.unit ?? "",
      note: x.note ?? "",
    })),
    orthostatic: (payload.orthostaticSessions ?? []).map((x) => ({
      event_id: x.eventID ?? "",
      timestamp: x.timestamp ?? "",
      baseline_hr: finiteNumber(x.baselineHeartRate),
      peak_standing_hr: finiteNumber(x.peakStandingHeartRate),
      final_standing_hr: finiteNumber(x.finalStandingHeartRate),
      peak_delta: finiteNumber(x.peakDelta),
      final_delta: finiteNumber(x.finalDelta),
      duration_seconds: finiteNumber(x.durationSeconds),
      completed: Boolean(x.completed),
      note: x.note ?? "",
    })),
  };
}

export function normalizeCSVRows(kind, rows) {
  if (kind === "health") {
    return rows.map((x) => ({
      sample_uuid: x.sample_uuid ?? "",
      type: x.type ?? "",
      start_at: x.start_at ?? "",
      end_at: x.end_at ?? "",
      value: finiteNumber(x.value),
      unit: x.unit ?? "",
      source: x.source ?? "",
    }));
  }

  if (kind === "daily") {
    return rows.map((x) => ({
      day_start: x.day_start ?? "",
      type: x.type ?? "",
      value: finiteNumber(x.value),
      unit: x.unit ?? "",
    }));
  }

  if (kind === "symptoms") {
    return rows.map((x) => ({
      event_id: x.event_id ?? "",
      timestamp: x.timestamp ?? "",
      symptom: x.symptom ?? "",
      posture: x.posture ?? "",
      severity: finiteNumber(x.severity),
      heart_rate: finiteNumber(x.heart_rate),
      note: x.note ?? "",
    }));
  }

  if (kind === "medications") {
    return rows.map((x) => ({
      event_id: x.event_id ?? "",
      timestamp: x.timestamp ?? "",
      name: x.name ?? "",
      dose: finiteNumber(x.dose),
      unit: x.unit ?? "",
      note: x.note ?? "",
    }));
  }

  if (kind === "orthostatic") {
    return rows.map((x) => ({
      event_id: x.event_id ?? "",
      timestamp: x.timestamp ?? "",
      baseline_hr: finiteNumber(x.baseline_hr),
      peak_standing_hr: finiteNumber(x.peak_standing_hr),
      final_standing_hr: finiteNumber(x.final_standing_hr),
      peak_delta: finiteNumber(x.peak_delta),
      final_delta: finiteNumber(x.final_delta),
      duration_seconds: finiteNumber(x.duration_seconds),
      completed:
        String(x.completed).toLowerCase() === "true" ||
        x.completed === "1",
      note: x.note ?? "",
    }));
  }

  return rows;
}

export function mergeUnique(existing, incoming, keyFn) {
  const map = new Map();
  existing.forEach((item) => map.set(keyFn(item), item));
  incoming.forEach((item) => map.set(keyFn(item), item));
  return [...map.values()];
}

export function latestSample(samples, type) {
  const candidates = samples
    .filter(
      (x) =>
        x.type === type &&
        finiteNumber(x.value) !== null &&
        validDate(x.start_at)
    )
    .sort(
      (a, b) =>
        validDate(b.start_at) - validDate(a.start_at)
    );
  return candidates[0] ?? null;
}

export function aggregateHealthDaily(samples, type) {
  const buckets = new Map();

  for (const sample of samples) {
    if (sample.type !== type) continue;
    const value = finiteNumber(sample.value);
    const date = validDate(sample.start_at);
    if (value === null || !date) continue;

    const key = localDayKey(date);
    const current = buckets.get(key) ?? {
      sum: 0,
      count: 0,
    };
    current.sum += value;
    current.count += 1;
    buckets.set(key, current);
  }

  return [...buckets.entries()]
    .map(([day, x]) => ({
      day,
      value: x.sum / x.count,
    }))
    .sort((a, b) => a.day.localeCompare(b.day));
}

export function dailyMetricSeries(rows, type) {
  const map = new Map();

  for (const row of rows) {
    if (row.type !== type) continue;
    const value = finiteNumber(row.value);
    const date = validDate(row.day_start);
    if (value === null || !date) continue;
    map.set(localDayKey(date), value);
  }

  return [...map.entries()]
    .map(([day, value]) => ({ day, value }))
    .sort((a, b) => a.day.localeCompare(b.day));
}

export function sleepDailySeries(samples) {
  const buckets = new Map();

  for (const sample of samples) {
    if (sample.type !== "sleep") continue;
    const start = validDate(sample.start_at);
    const end = validDate(sample.end_at);
    if (!start || !end || end <= start) continue;

    const key = localDayKey(end);
    const list = buckets.get(key) ?? [];
    list.push([start.getTime(), end.getTime()]);
    buckets.set(key, list);
  }

  const result = [];
  for (const [day, intervals] of buckets.entries()) {
    intervals.sort((a, b) => a[0] - b[0]);
    const merged = [];

    for (const interval of intervals) {
      if (
        merged.length === 0 ||
        interval[0] > merged[merged.length - 1][1]
      ) {
        merged.push([...interval]);
      } else {
        merged[merged.length - 1][1] = Math.max(
          merged[merged.length - 1][1],
          interval[1]
        );
      }
    }

    const hours =
      merged.reduce(
        (sum, [a, b]) => sum + (b - a),
        0
      ) / 3_600_000;

    result.push({ day, value: hours });
  }

  return result.sort((a, b) =>
    a.day.localeCompare(b.day)
  );
}

export function dashboardSummary(state, now = new Date()) {
  const hr = latestSample(
    state.healthSamples,
    "heart_rate"
  );
  const resting = latestSample(
    state.healthSamples,
    "resting_heart_rate"
  );
  const hrv = latestSample(
    state.healthSamples,
    "hrv_sdnn"
  );
  const respiratory = latestSample(
    state.healthSamples,
    "respiratory_rate"
  );

  const stepsSeries = dailyMetricSeries(
    state.dailyMetrics,
    "step_count"
  );
  const today = localDayKey(now);
  const todaySteps =
    stepsSeries.find((x) => x.day === today)
      ?.value ?? null;

  const sleepSeries = sleepDailySeries(
    state.healthSamples
  );
  const latestSleep =
    sleepSeries.at(-1) ?? null;

  const weekStart = new Date(
    now.getTime() -
      7 * 24 * 60 * 60 * 1000
  );
  const symptoms7 = state.symptoms.filter(
    (x) => {
      const d = validDate(x.timestamp);
      return d && d >= weekStart && d <= now;
    }
  ).length;

  const latestOrtho =
    [...state.orthostatic]
      .filter((x) => validDate(x.timestamp))
      .sort(
        (a, b) =>
          validDate(b.timestamp) -
          validDate(a.timestamp)
      )[0] ?? null;

  return {
    hr,
    resting,
    hrv,
    respiratory,
    todaySteps,
    latestSleep,
    symptoms7,
    latestOrtho,
  };
}

export function demoState(now = new Date()) {
  const iso = (offsetDays, hour = 8) => {
    const d = new Date(now);
    d.setDate(d.getDate() + offsetDays);
    d.setHours(hour, 0, 0, 0);
    return d.toISOString();
  };

  const healthSamples = [];
  const dailyMetrics = [];

  for (let i = -13; i <= 0; i += 1) {
    dailyMetrics.push({
      day_start: iso(i, 0),
      type: "step_count",
      value:
        5200 +
        (i + 13) * 170 +
        ((i % 3) + 1) * 300,
      unit: "count",
    });

    healthSamples.push({
      sample_uuid: `rest-${i}`,
      type: "resting_heart_rate",
      start_at: iso(i, 9),
      end_at: iso(i, 9),
      value:
        71 -
        (i + 13) * 0.15 +
        (i % 2),
      unit: "bpm",
      source: "Demo",
    });

    healthSamples.push({
      sample_uuid: `hrv-${i}`,
      type: "hrv_sdnn",
      start_at: iso(i, 7),
      end_at: iso(i, 7),
      value:
        37 +
        (i + 13) * 0.45 +
        (i % 3) * 1.1,
      unit: "ms",
      source: "Demo",
    });

    const sleepStart = new Date(
      iso(i - 1, 23)
    );
    const sleepEnd = new Date(
      sleepStart.getTime() +
        (
          6.2 +
          ((i + 14) % 4) * 0.35
        ) *
          3_600_000
    );

    healthSamples.push({
      sample_uuid: `sleep-${i}`,
      type: "sleep",
      start_at: sleepStart.toISOString(),
      end_at: sleepEnd.toISOString(),
      value: 1,
      unit: "sleep",
      source: "Demo",
    });
  }

  healthSamples.push({
    sample_uuid: "hr-latest",
    type: "heart_rate",
    start_at: new Date(
      now.getTime() - 8 * 60 * 1000
    ).toISOString(),
    end_at: new Date(
      now.getTime() - 8 * 60 * 1000
    ).toISOString(),
    value: 78,
    unit: "bpm",
    source: "Demo",
  });

  return {
    healthSamples,
    dailyMetrics,
    symptoms: [
      {
        event_id: "demo-s1",
        timestamp: iso(-2, 13),
        symptom: "어지러움",
        posture: "서 있음",
        severity: 4,
        heart_rate: 92,
        note: "데모 데이터",
      },
      {
        event_id: "demo-s2",
        timestamp: iso(-1, 18),
        symptom: "피로",
        posture: "앉아 있음",
        severity: 3,
        heart_rate: 80,
        note: "",
      },
    ],
    medications: [
      {
        event_id: "demo-m1",
        timestamp: iso(-6, 9),
        name: "예시 약",
        dose: 50,
        unit: "mg",
        note: "데모 데이터",
      },
    ],
    orthostatic: [
      {
        event_id: "demo-o1",
        timestamp: iso(-1, 10),
        baseline_hr: 68,
        peak_standing_hr: 91,
        final_standing_hr: 84,
        peak_delta: 23,
        final_delta: 16,
        duration_seconds: 180,
        completed: true,
        note: "",
      },
    ],
    summary: {
      generated_at: now.toISOString(),
      last_health_sync_at: new Date(
        now.getTime() - 12 * 60 * 1000
      ).toISOString(),
      coverage_last_7_complete_days: {
        resting_hr_days: 7,
        hrv_days: 7,
        sleep_nights: 7,
        step_days: 7,
      },
    },
    reportText:
      "DEMO MODE\n이 데이터는 기능 확인용 예시이며 실제 건강 데이터가 아닙니다.",
    importedFiles: [
      {
        name: "데모 데이터",
        size: 0,
        kind: "demo",
      },
    ],
  };
}
