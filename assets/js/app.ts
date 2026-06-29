import 'phoenix_html'
import Chart, { type ChartArea, type ScriptableContext } from 'chart.js/auto'
import { MatrixController, MatrixElement } from 'chartjs-chart-matrix'
import annotationPlugin from 'chartjs-plugin-annotation'
import 'chartjs-adapter-date-fns'
import { Socket } from 'phoenix'
import { LiveSocket, type ViewHook } from 'phoenix_live_view'

import type {
  HeatmapCell,
  HeatmapTile,
  HeatStatus,
  PingProgress,
  RangeChanged,
  SpeedtestProgress,
} from './types/events'

import { chartColors, makeChartHook } from './charts'

Chart.register(annotationPlugin, MatrixController, MatrixElement)

const TIME_RANGE_KEY = 'baudflow.time_range'
const VALID_TIME_RANGES = ['24h', '7d', '30d']
const DEFAULT_TIME_RANGE = '7d'

function readSavedTimeRange(): string {
  try {
    const v = localStorage.getItem(TIME_RANGE_KEY)
    return v && VALID_TIME_RANGES.includes(v) ? v : DEFAULT_TIME_RANGE
  } catch {
    return DEFAULT_TIME_RANGE
  }
}

const LOCAL_MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
]
function pad2(n: number): string {
  return String(n).padStart(2, '0')
}

function formatLocal(date: Date, format: string | undefined): string {
  const datePart = `${LOCAL_MONTHS[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`
  let h = date.getHours()
  const ampm = h >= 12 ? 'PM' : 'AM'
  // 0/12 o'clock both render as 12 (a real falsy→12 default, not nullish)
  const mod = h % 12
  h = mod === 0 ? 12 : mod
  const mm = pad2(date.getMinutes())
  const time =
    format === 'datetime-seconds'
      ? `${h}:${mm}:${pad2(date.getSeconds())} ${ampm}`
      : `${h}:${mm} ${ampm}`
  return `${datePart} · ${time}`
}

function renderLocalTime(el: HTMLElement): void {
  const iso = el.getAttribute('datetime')
  if (!iso) {
    return
  }
  const date = new Date(iso)
  if (isNaN(date.getTime())) {
    return
  }
  el.textContent = formatLocal(date, el.dataset.format)
  if (!el.title) {
    el.title = date.toUTCString()
  }
}

const heatmapStatusColors: Record<Exclude<HeatStatus, 'empty'>, string> = {
  healthy: '#3a9d7a',
  breach: '#c29438',
  failed: '#c75566',
  unknown: '#2c3852',
}

const heatmapStatusLabels: Record<HeatStatus, string> = {
  healthy: 'Healthy',
  breach: 'Threshold breach',
  failed: 'Failed',
  unknown: 'No verdict',
  empty: 'No data',
}

const heatmapWeekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

function cellFromContext(ctx: ScriptableContext<'matrix'>): HeatmapCell | null {
  let point: unknown = ctx.raw
  if (!point && Number.isInteger(ctx.dataIndex)) {
    point = ctx.dataset.data[ctx.dataIndex]
  }
  return (point as HeatmapCell | undefined) ?? null
}

type MatrixHook = ViewHook<HTMLCanvasElement> & { chart: Chart | null }

function paintMatrix(hook: MatrixHook, payload: HeatmapTile): void {
  if (hook.chart) {
    hook.chart.destroy()
    hook.chart = null
  }

  const rows = Math.max(
    parseInt(hook.el.dataset.weeks ?? '6', 10),
    payload.weeks,
  )
  const cells = payload.cells
  const yLabels = Array.from({ length: rows }, (_, i) => String(i))
  const palette: Record<string, string | undefined> = {
    ...heatmapStatusColors,
    ...(JSON.parse(hook.el.dataset.colors ?? '{}') as Record<string, string>),
  }
  const labels: Record<HeatStatus, string | undefined> = {
    ...heatmapStatusLabels,
    ...(JSON.parse(hook.el.dataset.labels ?? '{}') as Record<string, string>),
  }

  const ctx = hook.el.getContext('2d')
  if (!ctx) {
    return
  }
  hook.chart = new Chart(ctx, {
    type: 'matrix',
    data: {
      datasets: [
        {
          data: cells,
          backgroundColor(ctx: ScriptableContext<'matrix'>) {
            const raw = cellFromContext(ctx)
            return raw ? (palette[raw.v] ?? 'transparent') : 'transparent'
          },
          borderColor(ctx: ScriptableContext<'matrix'>) {
            const raw = cellFromContext(ctx)
            return raw?.v === 'empty'
              ? 'hsla(224, 30%, 45%, 0.35)'
              : 'transparent'
          },
          borderWidth: 1,
          borderRadius: 2,
          width: (ctx: ScriptableContext<'matrix'>) => {
            const area = ctx.chart.chartArea as ChartArea | undefined
            return area ? area.width / 7 - 3 : 0
          },
          height: (ctx: ScriptableContext<'matrix'>) => {
            const area = ctx.chart.chartArea as ChartArea | undefined
            return area ? area.height / rows - 3 : 0
          },
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 7 / rows,
      animation: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          displayColors: false,
          callbacks: {
            title: () => '',
            label(context) {
              const raw = (context.raw as HeatmapCell | undefined) ?? null
              return raw
                ? `${raw.d} - ${labels[raw.v] ?? 'No data'}`
                : 'No data'
            },
          },
        },
      },
      scales: {
        x: {
          type: 'category',
          labels: heatmapWeekdayLabels,
          offset: true,
          display: false,
          grid: { display: false },
        },
        y: {
          type: 'category',
          labels: yLabels,
          offset: true,
          reverse: true,
          display: false,
          grid: { display: false },
        },
      },
    },
  })
}

type Phase = 'download' | 'ping' | 'upload'

interface PhaseColor {
  b: number
  g: number
  r: number
}

interface SpeedSample {
  mbps: number
  raw?: null | number
  time: number
}

interface PingSample {
  latency: null | number
}

type VizHook = ViewHook & { cleanup?: () => void }

const chartHooks = {
  PersistRange: {
    mounted(this: ViewHook) {
      this.handleEvent('range_changed', ({ range }: RangeChanged) => {
        if (VALID_TIME_RANGES.includes(range)) {
          try {
            localStorage.setItem(TIME_RANGE_KEY, range)
          } catch {
            // localStorage unavailable (private mode); preference simply isn't persisted
          }
        }
      })
    },
  },

  LocalTime: {
    mounted(this: ViewHook) {
      renderLocalTime(this.el)
    },
    updated(this: ViewHook) {
      renderLocalTime(this.el)
    },
  },

  SpeedChart: makeChartHook({
    yTitle: 'Mbps',
    averages: true,
    drawFailures: true,
    series: [
      {
        label: 'Download (Mbps)',
        color: 'download',
        field: 'download_mbps',
        fill: true,
        tension: 0.25,
        borderWidth: 2,
        pointHoverRadius: 4,
      },
      {
        label: 'Upload (Mbps)',
        color: 'upload',
        field: 'upload_mbps',
        fill: true,
        tension: 0.25,
        borderWidth: 2,
        pointHoverRadius: 4,
      },
    ],
    thresholds: [
      {
        key: 'download',
        color: chartColors().download.border,
        label: 'DL min',
      },
      { key: 'upload', color: chartColors().upload.border, label: 'UL min' },
    ],
  }),

  PingChart: makeChartHook({
    yTitle: 'ms',
    series: [
      {
        label: 'Latency (ms)',
        color: 'latency',
        field: 'ping_latency',
        fill: true,
      },
      { label: 'Jitter (ms)', color: 'error', field: 'ping_jitter' },
    ],
    thresholds: [
      { key: 'ping', color: chartColors().latency.border, label: 'Max ping' },
    ],
  }),

  JitterChart: makeChartHook({
    yTitle: 'ms',
    series: [
      {
        label: 'Download Jitter (ms)',
        color: 'download',
        field: 'download_jitter',
      },
      { label: 'Upload Jitter (ms)', color: 'upload', field: 'upload_jitter' },
      { label: 'Ping Jitter (ms)', color: 'error', field: 'ping_jitter' },
    ],
  }),

  PingDetailChart: makeChartHook({
    yTitle: 'ms',
    series: [
      {
        label: 'Latency (ms)',
        color: 'latency',
        field: 'ping_latency',
        fill: true,
      },
      { label: 'Low (ms)', color: 'cyan', field: 'ping_low' },
      { label: 'High (ms)', color: 'orange', field: 'ping_high' },
    ],
    thresholds: [
      { key: 'ping', color: chartColors().latency.border, label: 'Max ping' },
    ],
  }),

  PacketLossChart: makeChartHook({
    yTitle: '%',
    yExtra: { min: 0 },
    series: [
      {
        label: 'Packet Loss (%)',
        color: 'error',
        field: 'packet_loss',
        fill: true,
      },
    ],
  }),

  DurationChart: makeChartHook({
    yTitle: 'ms',
    series: [
      {
        label: 'Download Duration (ms)',
        color: 'download',
        field: 'download_elapsed',
      },
      {
        label: 'Upload Duration (ms)',
        color: 'upload',
        field: 'upload_elapsed',
      },
    ],
  }),

  HeatmapMatrix: {
    mounted(this: MatrixHook) {
      this.chart = null
      this.handleEvent(`heatmap_tile:${this.el.id}`, (payload: HeatmapTile) => {
        paintMatrix(this, payload)
      })
    },

    destroyed(this: MatrixHook) {
      this.chart?.destroy()
    },
  },

  // ── SpeedtestViz: CRT oscilloscope diagnostics ────────────────────────

  SpeedtestViz: {
    mounted(this: VizHook) {
      let phase: null | Phase = null
      let samples: SpeedSample[] = [] // ring buffer of {time, mbps}
      const maxSamples = 120 // keep last ~120 data points
      let startTime = Date.now()
      let animId: null | number = null

      // DOM refs
      const canvas = document.getElementById(
        'crt-canvas',
      ) as HTMLCanvasElement | null
      const ctx = canvas?.getContext('2d') ?? null
      const speedEl = document.getElementById('crt-speed-value')
      const unitEl = document.getElementById('crt-speed-unit')
      const latencyEl = document.getElementById('crt-stat-latency')
      const jitterEl = document.getElementById('crt-stat-jitter')
      const elapsedEl = document.getElementById('crt-stat-elapsed')
      const serverEl = document.getElementById('crt-stat-server')
      const phasePing = document.getElementById('crt-phase-ping')
      const phaseDownload = document.getElementById('crt-phase-download')
      const phaseUpload = document.getElementById('crt-phase-upload')

      let w = 0
      let h = 0
      let onResize: (() => void) | null = null

      const phaseColors: Record<Phase, PhaseColor> = {
        ping: { r: 255, g: 170, b: 0 }, // electric amber
        download: { r: 0, g: 229, b: 255 }, // neon cyan
        upload: { r: 0, g: 255, b: 136 }, // neon green
      }

      function resize() {
        if (!canvas || !ctx) {
          return
        }
        const rect = canvas.parentElement?.getBoundingClientRect()
        if (!rect) {
          return
        }
        const dpr = window.devicePixelRatio
        canvas.width = rect.width * dpr
        canvas.height = rect.height * dpr
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
        w = rect.width
        h = rect.height
      }

      function stop() {
        if (animId != null) {
          cancelAnimationFrame(animId)
          animId = null
        }
        if (onResize) {
          window.removeEventListener('resize', onResize)
          onResize = null
        }
      }

      function onProgress(e: SpeedtestProgress) {
        const now = Date.now()

        if (e.type === 'testStart') {
          startTime = now
          const serverName =
            e.data.server?.name ?? e.data.server?.location ?? '──'
          if (serverEl) {
            serverEl.textContent = serverName
          }
          return
        }

        if (e.type === 'ping') {
          setPhase('ping')
          const latency = e.data.ping?.latency
          const jitter = e.data.ping?.jitter
          if (latency != null && latencyEl) {
            latencyEl.textContent = latency.toFixed(1)
          }
          if (jitter != null && jitterEl) {
            jitterEl.textContent = jitter.toFixed(1)
          }

          // Show latency as the "speed" during ping phase
          if (latency != null && speedEl) {
            speedEl.textContent = latency.toFixed(1)
            speedEl.className = 'crt-speed-num ping-val'
          }
          if (unitEl) {
            unitEl.textContent = 'ms'
          }

          // Add to waveform - use latency so lower = higher bar
          const mbps = latency ?? 0
          samples.push({ time: now, mbps, raw: latency })
          if (samples.length > maxSamples) {
            samples.shift()
          }

          if ((e.data.ping?.progress ?? 0) >= 1) {
            markPhaseDone('ping')
          }
          return
        }

        if (e.type === 'download') {
          setPhase('download')
          const bandwidth = e.data.download?.bandwidth ?? 0 // bytes/sec
          const mbps = (bandwidth * 8) / 1_000_000

          samples.push({ time: now, mbps })
          if (samples.length > maxSamples) {
            samples.shift()
          }

          if (speedEl) {
            speedEl.textContent = mbps.toFixed(1)
            speedEl.className = 'crt-speed-num'
          }
          if (unitEl) {
            unitEl.textContent = 'Mbps'
          }

          if ((e.data.download?.progress ?? 0) >= 1) {
            markPhaseDone('download')
          }
          return
        }

        setPhase('upload')
        const bandwidth = e.data.upload?.bandwidth ?? 0
        const mbps = (bandwidth * 8) / 1_000_000

        samples.push({ time: now, mbps })
        if (samples.length > maxSamples) {
          samples.shift()
        }

        if (speedEl) {
          speedEl.textContent = mbps.toFixed(1)
          speedEl.className = 'crt-speed-num mbps-upload'
        }
        if (unitEl) {
          unitEl.textContent = 'Mbps'
        }

        if ((e.data.upload?.progress ?? 0) >= 1) {
          markPhaseDone('upload')
        }
      }

      function setPhase(p: Phase) {
        if (phase === p) {
          return
        }
        if (phase === 'ping' && p !== 'ping') {
          markPhaseDone('ping')
        }
        if (phase === 'download' && p === 'upload') {
          markPhaseDone('download')
        }

        phase = p
        samples = []

        const phases: Record<string, HTMLElement | null> = {
          ping: phasePing,
          download: phaseDownload,
          upload: phaseUpload,
        }
        for (const [name, el] of Object.entries(phases)) {
          if (!el) {
            continue
          }
          el.classList.remove('active', 'done')
          if (name === p) {
            el.classList.add('active')
          }
        }
      }

      function markPhaseDone(name: Phase) {
        const map: Record<string, HTMLElement | null> = {
          ping: phasePing,
          download: phaseDownload,
          upload: phaseUpload,
        }
        const el = map[name]
        if (el) {
          el.classList.remove('active')
          el.classList.add('done')
        }
      }

      function animate() {
        draw()
        updateElapsed()
        animId = requestAnimationFrame(() => {
          animate()
        })
      }

      function updateElapsed() {
        if (!elapsedEl) {
          return
        }
        const sec = ((Date.now() - startTime) / 1000).toFixed(1)
        elapsedEl.textContent = sec
      }

      function draw() {
        if (!ctx) {
          return
        }
        const cw = w
        const ch = h
        if (!cw || !ch) {
          return
        }

        // ── Background ──
        ctx.fillStyle = '#020408'
        ctx.fillRect(0, 0, cw, ch)

        // ── Grid ──
        const gridColor = 'hsla(186, 100%, 50%, 0.04)'
        ctx.strokeStyle = gridColor
        ctx.lineWidth = 1

        // Horizontal grid lines (8 divisions)
        const hDivs = 8
        for (let i = 1; i < hDivs; i++) {
          const y = (ch / hDivs) * i
          ctx.beginPath()
          ctx.moveTo(0, y)
          ctx.lineTo(cw, y)
          ctx.stroke()
        }

        // Vertical grid lines (12 divisions)
        const vDivs = 12
        for (let i = 1; i < vDivs; i++) {
          const x = (cw / vDivs) * i
          ctx.beginPath()
          ctx.moveTo(x, 0)
          ctx.lineTo(x, ch)
          ctx.stroke()
        }

        // ── Center crosshair ──
        ctx.strokeStyle = 'hsla(186, 100%, 50%, 0.08)'
        ctx.beginPath()
        ctx.moveTo(cw / 2, 0)
        ctx.lineTo(cw / 2, ch)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(0, ch / 2)
        ctx.lineTo(cw, ch / 2)
        ctx.stroke()

        // ── Waveform ──
        if (samples.length < 2) {
          return
        }

        const color = phaseColors[phase ?? 'download']
        const padTop = 30
        const padBottom = 30
        const drawH = ch - padTop - padBottom

        // Determine Y range: auto-scale with a minimum range
        let maxVal = 0
        for (const s of samples) {
          if (s.mbps > maxVal) {
            maxVal = s.mbps
          }
        }
        // Ping phase: invert so waveform goes up for lower latency
        const isPing = phase === 'ping'
        if (isPing && maxVal > 0) {
          // We draw latency directly, higher = worse, so flip
          maxVal = maxVal * 1.2
        } else {
          maxVal = Math.max(maxVal * 1.15, 10) // at least 10 Mbps scale
        }

        // X mapping: ping is a short phase (a handful of samples in ~1s), so spread
        // its samples across the full width - otherwise the 120-sample window crushes
        // them into an invisible leftmost sliver. The longer download/upload phases
        // keep the windowed sweep (waveform grows left→right as it streams).
        const span = isPing ? Math.max(samples.length, 2) : maxSamples

        // Draw multiple "afterglow" layers for phosphor effect
        const layers = [
          { alpha: 0.03, width: 12 },
          { alpha: 0.06, width: 8 },
          { alpha: 0.15, width: 4 },
          { alpha: 0.5, width: 2 },
          { alpha: 1.0, width: 1.5 },
        ]

        for (const layer of layers) {
          ctx.beginPath()
          ctx.strokeStyle = `rgba(${color.r}, ${color.g}, ${color.b}, ${layer.alpha})`
          ctx.lineWidth = layer.width
          ctx.lineJoin = 'round'
          ctx.lineCap = 'round'

          for (let i = 0; i < samples.length; i++) {
            const x = (i / (span - 1)) * cw
            const val = isPing
              ? 1 - samples[i].mbps / maxVal
              : samples[i].mbps / maxVal // inverted for ping
            const y = padTop + drawH * (1 - Math.max(0, Math.min(1, val)))

            if (i === 0) {
              ctx.moveTo(x, y)
            } else {
              ctx.lineTo(x, y)
            }
          }
          ctx.stroke()
        }

        // ── Phosphor dot at the latest point ──
        if (samples.length > 0) {
          const last = samples[samples.length - 1]
          const x = ((samples.length - 1) / (span - 1)) * cw
          const val = isPing ? 1 - last.mbps / maxVal : last.mbps / maxVal
          const y = padTop + drawH * (1 - Math.max(0, Math.min(1, val)))

          // Glow
          const grad = ctx.createRadialGradient(x, y, 0, x, y, 20)
          grad.addColorStop(0, `rgba(${color.r}, ${color.g}, ${color.b}, 0.8)`)
          grad.addColorStop(
            0.5,
            `rgba(${color.r}, ${color.g}, ${color.b}, 0.2)`,
          )
          grad.addColorStop(1, `rgba(${color.r}, ${color.g}, ${color.b}, 0)`)
          ctx.fillStyle = grad
          ctx.fillRect(x - 20, y - 20, 40, 40)

          // Bright dot
          ctx.beginPath()
          ctx.arc(x, y, 3, 0, Math.PI * 2)
          ctx.fillStyle = `rgba(${color.r}, ${color.g}, ${color.b}, 1)`
          ctx.fill()
        }

        // ── Scale labels ──
        ctx.fillStyle = 'rgba(255, 255, 255, 0.12)'
        ctx.font = '10px monospace'
        ctx.textAlign = 'left'

        if (isPing) {
          ctx.fillText(`${maxVal.toFixed(1)}ms`, 4, padTop + 10)
          ctx.fillText('0ms', 4, ch - padBottom - 2)
        } else {
          ctx.fillText(`${maxVal.toFixed(0)} Mbps`, 4, padTop + 10)
          ctx.fillText('0', 4, ch - padBottom - 2)
        }
      }

      resize()
      onResize = () => {
        resize()
      }
      window.addEventListener('resize', onResize)

      // Start the render loop
      animate()

      // Listen for progress events from LiveView
      this.handleEvent('speedtest_progress', (e: SpeedtestProgress) => {
        onProgress(e)
      })

      // Clean up when the test finishes (panel gets removed from DOM)
      this.handleEvent('speedtest_complete', () => {
        stop()
      })

      this.cleanup = stop
    },

    destroyed(this: VizHook) {
      this.cleanup?.()
    },
  },

  // Live TCP-connect ping view - single-phase cousin of SpeedtestViz. Each
  // `ping_progress` payload pushes a latency sample (null for a failed connect);
  // bars are drawn inverted (lower latency = taller, amber) with failed samples
  // as a red baseline marker. `ping_complete` stops the render loop.
  PingViz: {
    mounted(this: VizHook) {
      let samples: PingSample[] = [] // [{latency: number|null}]
      // Cap high enough for a long run (duration × samples/sec); _draw spreads the
      // current set across the width, so a shorter run just widens the bars.
      const maxSamples = 120
      let startTime = Date.now()
      let animId: null | number = null

      const canvas = document.getElementById(
        'ping-canvas',
      ) as HTMLCanvasElement | null
      const ctx = canvas?.getContext('2d') ?? null
      const avgEl = document.getElementById('ping-avg')
      const jitterEl = document.getElementById('ping-jitter')
      const lossEl = document.getElementById('ping-loss')
      const elapsedEl = document.getElementById('ping-elapsed')
      const targetEl = document.getElementById('ping-target')

      let w = 0
      let h = 0
      let onResize: (() => void) | null = null

      function resize() {
        if (!canvas || !ctx) {
          return
        }
        const rect = canvas.parentElement?.getBoundingClientRect()
        if (!rect) {
          return
        }
        const dpr = window.devicePixelRatio
        canvas.width = rect.width * dpr
        canvas.height = rect.height * dpr
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
        w = rect.width
        h = rect.height
      }

      function stop() {
        if (animId != null) {
          cancelAnimationFrame(animId)
          animId = null
        }
        if (onResize) {
          window.removeEventListener('resize', onResize)
          onResize = null
        }
      }

      // A re-run from the open panel doesn't re-mount the hook (phx-update="ignore"
      // keeps #ping-viz), so ping_start resets the samples/readouts and restarts the
      // render loop for a fresh animation.
      function reset() {
        samples = []
        startTime = Date.now()
        if (avgEl) {
          avgEl.textContent = '───'
        }
        if (jitterEl) {
          jitterEl.textContent = '──'
        }
        if (lossEl) {
          lossEl.textContent = '──'
        }
        if (elapsedEl) {
          elapsedEl.textContent = '──'
        }
        if (animId == null) {
          animate()
        }
      }

      function onProgress(data: PingProgress) {
        samples.push({ latency: data.latency })
        if (samples.length > maxSamples) {
          samples.shift()
        }

        if (avgEl) {
          avgEl.textContent = data.avg.toFixed(1)
        }
        if (jitterEl) {
          jitterEl.textContent = data.jitter.toFixed(1)
        }
        if (lossEl) {
          lossEl.textContent = `${data.loss.toFixed(0)}%`
        }
        if (targetEl) {
          targetEl.textContent = `${data.host}:${data.port}`
        }
      }

      function animate() {
        draw()
        if (elapsedEl) {
          const sec = ((Date.now() - startTime) / 1000).toFixed(1)
          elapsedEl.textContent = sec
        }
        animId = requestAnimationFrame(() => {
          animate()
        })
      }

      function draw() {
        if (!ctx) {
          return
        }
        const cw = w
        const ch = h
        if (!cw || !ch) {
          return
        }

        // Background + grid - matches the SpeedtestViz oscilloscope frame.
        ctx.fillStyle = '#020408'
        ctx.fillRect(0, 0, cw, ch)
        ctx.strokeStyle = 'hsla(186, 100%, 50%, 0.04)'
        ctx.lineWidth = 1
        for (let i = 1; i < 8; i++) {
          const y = (ch / 8) * i
          ctx.beginPath()
          ctx.moveTo(0, y)
          ctx.lineTo(cw, y)
          ctx.stroke()
        }
        for (let i = 1; i < 12; i++) {
          const x = (cw / 12) * i
          ctx.beginPath()
          ctx.moveTo(x, 0)
          ctx.lineTo(x, ch)
          ctx.stroke()
        }
        ctx.strokeStyle = 'hsla(186, 100%, 50%, 0.08)'
        ctx.beginPath()
        ctx.moveTo(0, ch / 2)
        ctx.lineTo(cw, ch / 2)
        ctx.stroke()

        if (samples.length === 0) {
          return
        }

        const padTop = 30
        const padBottom = 30
        const drawH = ch - padTop - padBottom
        const span = Math.max(samples.length, 2)
        const barW = (cw / span) * 0.6

        // Auto-scale to the worst latency seen, floored so tiny latencies don't pin
        // the bars to the top edge.
        let maxVal = 1
        for (const s of samples) {
          if (s.latency != null && s.latency > maxVal) {
            maxVal = s.latency
          }
        }
        maxVal = maxVal * 1.2

        // A bar per sample: inverted (lower latency = taller, amber gradient); a
        // failed connect drops to a red stub on the baseline.
        for (let i = 0; i < samples.length; i++) {
          const x = (i / (span - 1)) * cw
          const s = samples[i]

          if (s.latency != null) {
            const frac = 1 - Math.min(s.latency / maxVal, 1)
            const y = padTop + drawH * (1 - frac)
            const barH = padTop + drawH - y
            const grad = ctx.createLinearGradient(x, y, x, y + barH)
            grad.addColorStop(0, 'rgba(255, 170, 0, 0.9)')
            grad.addColorStop(1, 'rgba(255, 170, 0, 0.15)')
            ctx.fillStyle = grad
            ctx.fillRect(x - barW / 2, y, barW, barH)
          } else {
            const y = padTop + drawH - 4
            ctx.fillStyle = 'rgba(255, 51, 102, 0.9)'
            ctx.fillRect(x - barW / 2, y, barW, 4)
          }
        }

        ctx.fillStyle = 'rgba(255, 255, 255, 0.12)'
        ctx.font = '10px monospace'
        ctx.textAlign = 'left'
        ctx.fillText(`${maxVal.toFixed(1)}ms`, 4, padTop + 10)
        ctx.fillText('0ms', 4, ch - padBottom - 2)
      }

      resize()
      onResize = () => {
        resize()
      }
      window.addEventListener('resize', onResize)

      animate()

      this.handleEvent('ping_start', () => {
        reset()
      })
      this.handleEvent('ping_progress', (d: PingProgress) => {
        onProgress(d)
      })
      this.handleEvent('ping_complete', () => {
        stop()
      })

      this.cleanup = stop
    },

    destroyed(this: VizHook) {
      this.cleanup?.()
    },
  },
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute('content')
const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken, time_range: readSavedTimeRange() },
  hooks: chartHooks,
})

// connect if there are any LiveViews on the page
liveSocket.connect()

window.liveSocket = liveSocket

if (process.env.NODE_ENV === 'development') {
  window.addEventListener('phx:live_reload:attached', (event: Event) => {
    const reloader = (event as CustomEvent).detail as Window['liveReloader']
    if (!reloader) {
      return
    }
    reloader.enableServerLogs()

    let keyDown: null | string = null
    window.addEventListener('keydown', (e: KeyboardEvent) => (keyDown = e.key))
    window.addEventListener('keyup', () => (keyDown = null))
    window.addEventListener(
      'click',
      (e: MouseEvent) => {
        if (keyDown === 'c') {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtCaller(e.target)
        } else if (keyDown === 'd') {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtDef(e.target)
        }
      },
      true,
    )

    window.liveReloader = reloader
  })
}
