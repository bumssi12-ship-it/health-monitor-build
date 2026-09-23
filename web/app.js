import {
  parseCSV,
  normalizeBackup,
  normalizeCSVRows,
  mergeUnique,
  validDate,
  finiteNumber,
  aggregateHealthDaily,
  dailyMetricSeries,
  sleepDailySeries,
  dashboardSummary,
  demoState,
} from "./core.mjs";

const emptyState = () => ({
  healthSamples: [],
  dailyMetrics: [],
  symptoms: [],
  medications: [],
  orthostatic: [],
  summary: null,
  reportText: "",
  importedFiles: [],
});

let state = emptyState();

const $ = (id) =>
  document.getElementById(id);

const refs = {
  fileInput: $("fileInput"),
  dropZone: $("dropZone"),
  importSummary: $("importSummary"),
  importErrors: $("importErrors"),
  demoBtn: $("demoBtn"),
  clearBtn: $("clearBtn"),
  symptomSearch: $("symptomSearch"),
};

function formatNumber(
  value,
  digits = 0
) {
  const n = finiteNumber(value);
  if (n === null) return "—";

  return new Intl.NumberFormat(
    "ko-KR",
    {
      maximumFractionDigits: digits,
      minimumFractionDigits: 0,
    }
  ).format(n);
}

function formatDateTime(value) {
  const d = validDate(value);
  if (!d) return "데이터 없음";

  return new Intl.DateTimeFormat(
    "ko-KR",
    {
      month: "numeric",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }
  ).format(d);
}

function formatDay(day) {
  if (!day) return "데이터 없음";

  const d = validDate(
    `${day}T12:00:00`
  );

  if (!d) return day;

  return new Intl.DateTimeFormat(
    "ko-KR",
    {
      month: "numeric",
      day: "numeric",
    }
  ).format(d);
}

function kindForFile(name) {
  const lower = name.toLowerCase();

  if (lower.endsWith(".json")) {
    return "json";
  }
  if (lower.endsWith(".csv")) {
    return "csv";
  }
  if (lower.endsWith(".txt")) {
    return "text";
  }

  return "unknown";
}

function mergeEvents(
  existing,
  incoming,
  prefix
) {
  const map = new Map();

  existing.forEach(
    (item, index) => {
      const key =
        item.event_id
          ? `${prefix}:${item.event_id}`
          : `${prefix}:${item.timestamp}:${item.symptom ?? item.name ?? ""}:${index}`;

      map.set(key, item);
    }
  );

  incoming.forEach(
    (item, index) => {
      const key =
        item.event_id
          ? `${prefix}:${item.event_id}`
          : `${prefix}:${item.timestamp}:${item.symptom ?? item.name ?? ""}:${index}`;

      map.set(key, item);
    }
  );

  return [...map.values()];
}

async function importFiles(files) {
  const errors = [];

  for (const file of files) {
    try {
      const text = await file.text();
      const lower =
        file.name.toLowerCase();

      let recognized = false;

      if (
        lower.endsWith(".json")
      ) {
        const payload =
          JSON.parse(text);

        if (
          payload &&
          payload.formatVersion
            !== undefined &&
          Array.isArray(
            payload.symptoms
          ) &&
          Array.isArray(
            payload.medications
          ) &&
          Array.isArray(
            payload
              .orthostaticSessions
          )
        ) {
          const backup =
            normalizeBackup(
              payload
            );

          state.symptoms =
            mergeEvents(
              state.symptoms,
              backup.symptoms,
              "s"
            );

          state.medications =
            mergeEvents(
              state.medications,
              backup.medications,
              "m"
            );

          state.orthostatic =
            mergeEvents(
              state.orthostatic,
              backup.orthostatic,
              "o"
            );

          recognized = true;
        } else if (
          payload &&
          (
            payload.generated_at ||
            payload
              .coverage_last_7_complete_days ||
            payload
              .database_user_version
              !== undefined
          )
        ) {
          state.summary =
            payload;

          recognized = true;
        }
      } else if (
        lower.endsWith(".csv")
      ) {
        const rows =
          parseCSV(text);

        if (
          lower.endsWith(
            "health_samples.csv"
          )
        ) {
          const normalized =
            normalizeCSVRows(
              "health",
              rows
            );

          state.healthSamples =
            mergeUnique(
              state.healthSamples,
              normalized,
              (x) =>
                x.sample_uuid ||
                `${x.type}:${x.start_at}:${x.value}`
            );

          recognized = true;
        } else if (
          lower.endsWith(
            "daily_metrics.csv"
          )
        ) {
          const normalized =
            normalizeCSVRows(
              "daily",
              rows
            );

          state.dailyMetrics =
            mergeUnique(
              state.dailyMetrics,
              normalized,
              (x) =>
                `${x.day_start}:${x.type}`
            );

          recognized = true;
        } else if (
          lower.endsWith(
            "symptoms.csv"
          )
        ) {
          state.symptoms =
            mergeEvents(
              state.symptoms,
              normalizeCSVRows(
                "symptoms",
                rows
              ),
              "s"
            );

          recognized = true;
        } else if (
          lower.endsWith(
            "medications.csv"
          )
        ) {
          state.medications =
            mergeEvents(
              state.medications,
              normalizeCSVRows(
                "medications",
                rows
              ),
              "m"
            );

          recognized = true;
        } else if (
          lower.endsWith(
            "orthostatic_sessions.csv"
          )
        ) {
          state.orthostatic =
            mergeEvents(
              state.orthostatic,
              normalizeCSVRows(
                "orthostatic",
                rows
              ),
              "o"
            );

          recognized = true;
        }
      } else if (
        lower.endsWith(
          "report_7days.txt"
        )
      ) {
        state.reportText = text;
        recognized = true;
      }

      if (!recognized) {
        throw new Error(
          "알 수 없는 Health Monitor 파일 형식"
        );
      }

      state.importedFiles =
        mergeUnique(
          state.importedFiles,
          [
            {
              name: file.name,
              size: file.size,
              kind:
                kindForFile(
                  file.name
                ),
            },
          ],
          (x) => x.name
        );
    } catch (error) {
      errors.push(
        `${file.name}: ${error?.message ?? String(error)}`
      );
    }
  }

  showErrors(errors);
  renderAll();
}

function showErrors(errors) {
  if (errors.length === 0) {
    refs.importErrors.hidden =
      true;

    refs.importErrors
      .textContent = "";

    return;
  }

  refs.importErrors.hidden =
    false;

  refs.importErrors
    .textContent =
      errors.join("\n");
}

function setMetric(
  id,
  value,
  suffix = ""
) {
  $(id).textContent =
    value === "—"
      ? value
      : `${value}${suffix}`;
}

function renderDashboard() {
  const summary =
    dashboardSummary(state);

  const hr = summary.hr;
  const resting =
    summary.resting;
  const hrv = summary.hrv;

  setMetric(
    "metricHr",
    formatNumber(hr?.value),
    hr ? " bpm" : ""
  );
  $("metricHrTime")
    .textContent =
      formatDateTime(
        hr?.start_at
      );

  setMetric(
    "metricRestingHr",
    formatNumber(
      resting?.value
    ),
    resting ? " bpm" : ""
  );
  $("metricRestingHrTime")
    .textContent =
      formatDateTime(
        resting?.start_at
      );

  setMetric(
    "metricHrv",
    formatNumber(
      hrv?.value,
      1
    ),
    hrv ? " ms" : ""
  );
  $("metricHrvTime")
    .textContent =
      formatDateTime(
        hrv?.start_at
      );

  setMetric(
    "metricSteps",
    formatNumber(
      summary.todaySteps
    )
  );

  if (
    summary.latestSleep
  ) {
    setMetric(
      "metricSleep",
      formatNumber(
        summary.latestSleep
          .value,
        1
      ),
      " h"
    );

    $("metricSleepDay")
      .textContent =
        formatDay(
          summary.latestSleep
            .day
        );
  } else {
    setMetric(
      "metricSleep",
      "—"
    );

    $("metricSleepDay")
      .textContent =
        "데이터 없음";
  }

  setMetric(
    "metricSymptoms",
    formatNumber(
      summary.symptoms7
    ),
    "건"
  );

  if (
    summary.latestOrtho &&
    finiteNumber(
      summary.latestOrtho
        .peak_delta
    ) !== null
  ) {
    const delta =
      finiteNumber(
        summary.latestOrtho
          .peak_delta
      );

    setMetric(
      "metricOrtho",
      `${delta >= 0 ? "+" : ""}${formatNumber(delta)}`,
      " bpm"
    );

    $("metricOrthoTime")
      .textContent =
        formatDateTime(
          summary.latestOrtho
            .timestamp
        );
  } else {
    setMetric(
      "metricOrtho",
      "—"
    );

    $("metricOrthoTime")
      .textContent =
        "데이터 없음";
  }

  const sync =
    state.summary
      ?.last_health_sync_at;

  $("metricSync")
    .textContent =
      sync
        ? formatDateTime(sync)
        : "—";

  const coverage =
    state.summary
      ?.coverage_last_7_complete_days;

  $("metricCoverage")
    .textContent =
      coverage
        ? `7일 커버리지 · HR ${coverage.resting_hr_days ?? 0} / HRV ${coverage.hrv_days ?? 0} / 수면 ${coverage.sleep_nights ?? 0} / 걸음 ${coverage.step_days ?? 0}`
        : "summary.json이 있으면 표시";

  drawChart(
    "stepsChart",
    "stepsEmpty",
    dailyMetricSeries(
      state.dailyMetrics,
      "step_count"
    ).slice(-14),
    ""
  );

  drawChart(
    "restingChart",
    "restingEmpty",
    aggregateHealthDaily(
      state.healthSamples,
      "resting_heart_rate"
    ).slice(-14),
    ""
  );

  drawChart(
    "hrvChart",
    "hrvEmpty",
    aggregateHealthDaily(
      state.healthSamples,
      "hrv_sdnn"
    ).slice(-14),
    ""
  );

  drawChart(
    "sleepChart",
    "sleepEmpty",
    sleepDailySeries(
      state.healthSamples
    ).slice(-14),
    "h"
  );
}

function drawChart(
  canvasId,
  emptyId,
  points,
  suffix
) {
  const canvas =
    $(canvasId);

  const empty =
    $(emptyId);

  if (
    !points ||
    points.length === 0
  ) {
    canvas.hidden = true;
    empty.hidden = false;
    return;
  }

  canvas.hidden = false;
  empty.hidden = true;

  const rect =
    canvas
      .getBoundingClientRect();

  const ratio =
    window.devicePixelRatio ||
    1;

  const width =
    Math.max(
      320,
      rect.width || 600
    );

  const height = 190;

  canvas.width =
    Math.round(
      width * ratio
    );

  canvas.height =
    Math.round(
      height * ratio
    );

  const ctx =
    canvas.getContext(
      "2d"
    );

  ctx.setTransform(
    ratio,
    0,
    0,
    ratio,
    0,
    0
  );

  ctx.clearRect(
    0,
    0,
    width,
    height
  );

  const css =
    getComputedStyle(
      document.documentElement
    );

  const lineColor =
    css
      .getPropertyValue(
        "--line"
      )
      .trim() ||
    "#dbe4ef";

  const primary =
    css
      .getPropertyValue(
        "--primary"
      )
      .trim() ||
    "#0b6bcb";

  const muted =
    css
      .getPropertyValue(
        "--muted"
      )
      .trim() ||
    "#667085";

  const values =
    points
      .map((x) => x.value)
      .filter(
        Number.isFinite
      );

  let min =
    Math.min(...values);

  let max =
    Math.max(...values);

  if (min === max) {
    min -= 1;
    max += 1;
  }

  const pad =
    Math.max(
      (max - min) * 0.15,
      1
    );

  min -= pad;
  max += pad;

  const left = 34;
  const right = 12;
  const top = 16;
  const bottom = 30;

  const plotW =
    width -
    left -
    right;

  const plotH =
    height -
    top -
    bottom;

  ctx.strokeStyle =
    lineColor;

  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(left, top);
  ctx.lineTo(
    left,
    top + plotH
  );
  ctx.lineTo(
    left + plotW,
    top + plotH
  );
  ctx.stroke();

  const x = (index) =>
    left +
    (
      points.length === 1
        ? plotW / 2
        : (
            index /
            (
              points.length -
              1
            )
          ) *
          plotW
    );

  const y = (value) =>
    top +
    (
      1 -
      (
        value - min
      ) /
      (
        max - min
      )
    ) *
    plotH;

  ctx.strokeStyle =
    primary;

  ctx.lineWidth = 2.2;
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.beginPath();

  points.forEach(
    (point, index) => {
      const px = x(index);
      const py =
        y(point.value);

      if (index === 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
  );

  ctx.stroke();
  ctx.fillStyle =
    primary;

  points.forEach(
    (point, index) => {
      ctx.beginPath();
      ctx.arc(
        x(index),
        y(point.value),
        2.8,
        0,
        Math.PI * 2
      );
      ctx.fill();
    }
  );

  ctx.fillStyle = muted;
  ctx.font =
    "11px system-ui";
  ctx.textAlign = "left";

  ctx.fillText(
    `${formatNumber(max, 1)}${suffix}`,
    2,
    top + 4
  );

  ctx.fillText(
    `${formatNumber(min, 1)}${suffix}`,
    2,
    top + plotH
  );

  ctx.textAlign =
    "center";

  const first =
    points[0];

  const last =
    points.at(-1);

  ctx.fillText(
    formatDay(first.day),
    x(0),
    height - 8
  );

  if (
    points.length > 1
  ) {
    ctx.fillText(
      formatDay(last.day),
      x(
        points.length -
          1
      ),
      height - 8
    );
  }
}

function appendCell(
  row,
  value
) {
  const td =
    document.createElement(
      "td"
    );

  td.textContent =
    String(value ?? "");

  row.appendChild(td);
}

function renderSymptoms() {
  const query =
    refs.symptomSearch
      .value
      .trim()
      .toLowerCase();

  const rows =
    [...state.symptoms]
      .filter((x) => {
        if (!query) {
          return true;
        }

        return [
          x.symptom,
          x.posture,
          x.note,
        ]
          .join(" ")
          .toLowerCase()
          .includes(query);
      })
      .sort(
        (a, b) =>
          (
            validDate(
              b.timestamp
            )?.getTime()
              ?? 0
          ) -
          (
            validDate(
              a.timestamp
            )?.getTime()
              ?? 0
          )
      );

  const body =
    $("symptomRows");

  body.replaceChildren();

  rows.forEach(
    (item) => {
      const tr =
        document
          .createElement(
            "tr"
          );

      appendCell(
        tr,
        formatDateTime(
          item.timestamp
        )
      );

      appendCell(
        tr,
        item.symptom
      );

      appendCell(
        tr,
        item.posture
      );

      appendCell(
        tr,
        finiteNumber(
          item.severity
        ) ?? "—"
      );

      appendCell(
        tr,
        finiteNumber(
          item.heart_rate
        ) === null
          ? "—"
          : `${formatNumber(item.heart_rate)} bpm`
      );

      appendCell(
        tr,
        item.note
      );

      body.appendChild(tr);
    }
  );

  $("symptomCountText")
    .textContent =
      `${rows.length}건`;

  $("symptomEmpty")
    .hidden =
      rows.length > 0;
}

function renderOrthostatic() {
  const rows =
    [...state.orthostatic]
      .sort(
        (a, b) =>
          (
            validDate(
              b.timestamp
            )?.getTime()
              ?? 0
          ) -
          (
            validDate(
              a.timestamp
            )?.getTime()
              ?? 0
          )
      );

  const body =
    $("orthoRows");

  body.replaceChildren();

  rows.forEach(
    (item) => {
      const tr =
        document
          .createElement(
            "tr"
          );

      appendCell(
        tr,
        formatDateTime(
          item.timestamp
        )
      );

      appendCell(
        tr,
        finiteNumber(
          item.baseline_hr
        ) ?? "—"
      );

      appendCell(
        tr,
        finiteNumber(
          item
            .peak_standing_hr
        ) ?? "—"
      );

      appendCell(
        tr,
        finiteNumber(
          item
            .final_standing_hr
        ) ?? "—"
      );

      const peak =
        finiteNumber(
          item.peak_delta
        );

      const final =
        finiteNumber(
          item.final_delta
        );

      appendCell(
        tr,
        peak === null
          ? "—"
          : `${peak >= 0 ? "+" : ""}${formatNumber(peak)}`
      );

      appendCell(
        tr,
        final === null
          ? "—"
          : `${final >= 0 ? "+" : ""}${formatNumber(final)}`
      );

      appendCell(
        tr,
        item.completed
          ? "완료"
          : "미완료"
      );

      body.appendChild(tr);
    }
  );

  $("orthoCountText")
    .textContent =
      `${rows.length}건`;

  $("orthoEmpty")
    .hidden =
      rows.length > 0;
}

function renderMedications() {
  const rows =
    [...state.medications]
      .sort(
        (a, b) =>
          (
            validDate(
              b.timestamp
            )?.getTime()
              ?? 0
          ) -
          (
            validDate(
              a.timestamp
            )?.getTime()
              ?? 0
          )
      );

  const body =
    $("medicationRows");

  body.replaceChildren();

  rows.forEach(
    (item) => {
      const tr =
        document
          .createElement(
            "tr"
          );

      appendCell(
        tr,
        formatDateTime(
          item.timestamp
        )
      );

      appendCell(
        tr,
        item.name
      );

      appendCell(
        tr,
        finiteNumber(
          item.dose
        ) === null
          ? "—"
          : `${formatNumber(item.dose, 2)} ${item.unit ?? ""}`.trim()
      );

      appendCell(
        tr,
        item.note
      );

      body.appendChild(tr);
    }
  );

  $("medicationCountText")
    .textContent =
      `${rows.length}건`;

  $("medicationEmpty")
    .hidden =
      rows.length > 0;
}

function renderFiles() {
  const list =
    $("fileList");

  list.replaceChildren();

  if (
    state.importedFiles
      .length === 0
  ) {
    const li =
      document
        .createElement(
          "li"
        );

    li.textContent =
      "가져온 파일이 없습니다.";

    list.appendChild(li);
  } else {
    state.importedFiles
      .forEach(
        (file) => {
          const li =
            document
              .createElement(
                "li"
              );

          const name =
            document
              .createElement(
                "span"
              );

          const size =
            document
              .createElement(
                "small"
              );

          name.textContent =
            file.name;

          size.textContent =
            file.size
              ? `${Math.ceil(file.size / 1024)} KB`
              : file.kind;

          li.append(
            name,
            size
          );

          list.appendChild(
            li
          );
        }
      );
  }

  $("reportText")
    .textContent =
      state.reportText ||
      "report_7days.txt를 불러오면 여기에 표시됩니다.";
}

function renderImportSummary() {
  const total =
    state.healthSamples
      .length +
    state.dailyMetrics
      .length +
    state.symptoms
      .length +
    state.medications
      .length +
    state.orthostatic
      .length;

  if (
    state.importedFiles
      .length === 0
  ) {
    refs.importSummary
      .textContent =
        "아직 파일을 불러오지 않았습니다.";

    return;
  }

  refs.importSummary
    .textContent =
      `${state.importedFiles.length}개 파일 · ${total.toLocaleString("ko-KR")}개 레코드`;
}

function renderAll() {
  renderImportSummary();
  renderDashboard();
  renderSymptoms();
  renderOrthostatic();
  renderMedications();
  renderFiles();
}

function resetData() {
  state = emptyState();
  refs.fileInput.value = "";
  showErrors([]);
  renderAll();
}

refs.fileInput
  .addEventListener(
    "change",
    (event) => {
      importFiles([
        ...event.target.files,
      ]);
    }
  );

[
  "dragenter",
  "dragover",
].forEach(
  (eventName) => {
    refs.dropZone
      .addEventListener(
        eventName,
        (event) => {
          event.preventDefault();

          refs.dropZone
            .classList
            .add(
              "dragging"
            );
        }
      );
  }
);

[
  "dragleave",
  "drop",
].forEach(
  (eventName) => {
    refs.dropZone
      .addEventListener(
        eventName,
        (event) => {
          event.preventDefault();

          refs.dropZone
            .classList
            .remove(
              "dragging"
            );
        }
      );
  }
);

refs.dropZone
  .addEventListener(
    "drop",
    (event) => {
      importFiles([
        ...event
          .dataTransfer
          .files,
      ]);
    }
  );

refs.clearBtn
  .addEventListener(
    "click",
    resetData
  );

refs.demoBtn
  .addEventListener(
    "click",
    () => {
      state =
        demoState();

      showErrors([]);
      renderAll();
    }
  );

refs.symptomSearch
  .addEventListener(
    "input",
    renderSymptoms
  );

document
  .querySelectorAll(
    ".tab"
  )
  .forEach(
    (button) => {
      button
        .addEventListener(
          "click",
          () => {
            document
              .querySelectorAll(
                ".tab"
              )
              .forEach(
                (x) =>
                  x.classList
                    .remove(
                      "active"
                    )
              );

            document
              .querySelectorAll(
                ".tab-panel"
              )
              .forEach(
                (x) =>
                  x.classList
                    .remove(
                      "active"
                    )
              );

            button
              .classList
              .add(
                "active"
              );

            $(
              button.dataset.tab
            )
              .classList
              .add(
                "active"
              );
          }
        );
    }
  );

window.addEventListener(
  "resize",
  () => {
    window.clearTimeout(
      window
        .__hmResizeTimer
    );

    window
      .__hmResizeTimer =
        window.setTimeout(
          renderDashboard,
          120
        );
  }
);

if (
  "serviceWorker"
    in navigator &&
  location.protocol
    !== "file:"
) {
  navigator
    .serviceWorker
    .register("./sw.js")
    .catch(() => {});
}

renderAll();


let deferredInstallPrompt = null;
const installAppBtn = document.getElementById("installAppBtn");

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  if (installAppBtn) {
    installAppBtn.hidden = false;
  }
});

if (installAppBtn) {
  installAppBtn.addEventListener("click", async () => {
    if (!deferredInstallPrompt) return;

    installAppBtn.disabled = true;
    try {
      deferredInstallPrompt.prompt();
      await deferredInstallPrompt.userChoice;
    } finally {
      deferredInstallPrompt = null;
      installAppBtn.hidden = true;
      installAppBtn.disabled = false;
    }
  });
}

window.addEventListener("appinstalled", () => {
  deferredInstallPrompt = null;
  if (installAppBtn) {
    installAppBtn.hidden = true;
  }
});
