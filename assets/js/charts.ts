import Chart, {
  type ChartDataset,
  type ChartOptions,
  type PluginOptionsByType,
} from 'chart.js/auto'

import type {
  AppendPoint,
  ChartData,
  Measurement,
  ThresholdKey,
  Thresholds,
} from './types/events'

import type { AnnotationOptions } from 'chartjs-plugin-annotation'
import type { ViewHook } from 'phoenix_live_view'

interface SeriesColor {
  bg?: string
  border: string
}

export interface ChartPalette {
  avg7: SeriesColor
  avg30: SeriesColor
  cyan: SeriesColor
  download: SeriesColor
  error: SeriesColor
  latency: SeriesColor
  orange: SeriesColor
  upload: SeriesColor
}

export type ColorKey = keyof ChartPalette

export function chartColors(): ChartPalette {
  return {
    download: {
      border: 'hsl(186, 100%, 50%)',
      bg: 'hsla(186, 100%, 50%, 0.08)',
    }, // neon cyan
    upload: { border: 'hsl(153, 100%, 50%)', bg: 'hsla(153, 100%, 50%, 0.08)' }, // neon green
    latency: { border: 'hsl(40, 100%, 50%)', bg: 'hsla(40, 100%, 50%, 0.08)' }, // electric amber
    error: { border: 'hsl(345, 100%, 60%)', bg: 'hsla(345, 100%, 60%, 0.08)' }, // neon red
    avg7: { border: 'hsl(198, 100%, 60%)' }, // neon blue
    avg30: { border: 'hsl(340, 85%, 65%)' }, // neon pink
    cyan: { border: 'hsl(186, 80%, 50%)', bg: 'hsla(186, 80%, 50%, 0.08)' }, // teal
    orange: { border: 'hsl(25, 100%, 55%)', bg: 'hsla(25, 100%, 55%, 0.08)' }, // neon orange
  }
}

interface GridColors {
  grid: { color: string }
  ticks: { color: string }
  title: { color: string }
}

function chartGridColors(): GridColors {
  return {
    grid: { color: 'hsla(224, 30%, 90%, 0.05)' },
    ticks: { color: 'hsla(224, 20%, 60%, 0.6)' },
    title: { color: 'hsla(224, 20%, 60%, 0.8)' },
  }
}

type NumericField = {
  [K in keyof Measurement]: Measurement[K] extends null | number ? K : never
}[keyof Measurement]

function makeChartOptions(
  g: GridColors,
  yTitle: string,
  yExtra: Record<string, unknown> = {},
): ChartOptions<'line'> {
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: { duration: 300, easing: 'easeOutQuart' },
    interaction: { mode: 'index', intersect: false },
    scales: {
      x: {
        type: 'time',
        time: { unit: 'hour' },
        grid: { color: g.grid.color },
        ticks: {
          color: g.ticks.color,
          font: { size: 10 },
          maxRotation: 0,
          maxTicksLimit: 8,
        },
        border: { display: false },
      },
      y: Object.assign(
        {
          title: {
            display: true,
            text: yTitle,
            color: g.title.color,
            font: { size: 10 },
          },
          grid: { color: g.grid.color },
          ticks: { color: g.ticks.color, font: { size: 10 }, maxTicksLimit: 6 },
          border: { display: false },
        },
        yExtra,
      ),
    },
    plugins: {
      legend: { display: false },
      annotation: { annotations: {} },
      tooltip: {
        backgroundColor: 'rgba(0, 0, 0, 0.82)',
        titleFont: { size: 11, weight: 500 },
        bodyFont: { size: 11 },
        padding: { top: 8, bottom: 8, left: 10, right: 10 },
        cornerRadius: 6,
        boxWidth: 8,
        boxHeight: 2,
        boxPadding: 4,
      },
    },
  }
}

const FAILURE_COLOR = 'hsl(345, 100%, 60%)' // matches chartColors().error.border

interface ThresholdLineSpec {
  color: string
  key: ThresholdKey
  label: string
}

function lineAnnotation(
  yMin: number,
  color: string,
  label?: string,
): AnnotationOptions<'line'> {
  const a: AnnotationOptions<'line'> = {
    type: 'line',
    yMin,
    yMax: yMin,
    borderColor: color,
    borderWidth: 1,
    borderDash: [6, 4],
  }
  if (label) {
    a.label = {
      content: label,
      display: true,
      position: 'end',
      font: { size: 9, weight: 500 },
      backgroundColor: 'rgba(0, 0, 0, 0.6)',
      color,
      padding: { top: 2, bottom: 2, left: 4, right: 4 },
    }
  }
  return a
}

function failureAnnotation(timestamp: string): AnnotationOptions<'line'> {
  return {
    type: 'line',
    xMin: timestamp,
    xMax: timestamp,
    borderColor: FAILURE_COLOR,
    borderWidth: 2,
  }
}

// specs: [{key, color, label}] - which threshold fields this chart draws.
// failedTimestamps: [iso] - one red vertical bar each.
function buildAnnotations(
  specs: ThresholdLineSpec[],
  thresholds: Thresholds | undefined,
  failedTimestamps: string[],
): Record<string, AnnotationOptions<'line'>> {
  const annotations: Record<string, AnnotationOptions<'line'>> = {}
  for (const spec of specs) {
    const v = thresholds ? thresholds[spec.key] : null
    if (typeof v === 'number' && v > 0) {
      annotations[`threshold-${spec.key}`] = lineAnnotation(
        v,
        spec.color,
        spec.label,
      )
    }
  }
  for (const ts of failedTimestamps) {
    annotations[`fail-${ts}`] = failureAnnotation(ts)
  }
  return annotations
}

function annotationOptions(
  chart: Chart,
): PluginOptionsByType<'line'>['annotation'] {
  return (chart.options.plugins as PluginOptionsByType<'line'>).annotation
}

interface SeriesSpec {
  borderWidth?: number
  color: ColorKey
  field: NumericField
  fill?: boolean
  label: string
  pointHoverRadius?: number
  tension?: number
}

export interface ChartSpec {
  averages?: boolean // 7d/30d constant-line overlay (SpeedChart only)
  drawFailures?: boolean // red bars for failed points (SpeedChart only)
  series: SeriesSpec[]
  thresholds?: ThresholdLineSpec[]
  yExtra?: Record<string, unknown>
  yTitle: string
}

type ChartHook = ViewHook & { chart?: Chart | null }

export function makeChartHook(spec: ChartSpec) {
  return {
    mounted(this: ChartHook) {
      const palette = chartColors()
      const g = chartGridColors()
      const canvas = this.el.querySelector('canvas')
      const ctx = canvas?.getContext('2d')
      if (!ctx) {
        return
      }

      const seriesDatasets: ChartDataset<'line', (null | number)[]>[] =
        spec.series.map(s => {
          const color = palette[s.color]
          return {
            label: s.label,
            data: [],
            borderColor: color.border,
            backgroundColor: color.bg,
            borderWidth: s.borderWidth ?? 1.5,
            fill: s.fill ?? false,
            tension: s.tension ?? 0.2,
            pointRadius: 0,
            pointHoverRadius: s.pointHoverRadius ?? 3,
          }
        })

      const avgDatasets: ChartDataset<'line', (null | number)[]>[] =
        spec.averages
          ? [
              {
                label: '7d Avg',
                data: [],
                borderColor: palette.avg7.border,
                borderWidth: 1,
                borderDash: [4, 4],
                pointRadius: 0,
                pointHoverRadius: 0,
                fill: false,
              },
              {
                label: '30d Avg',
                data: [],
                borderColor: palette.avg30.border,
                borderWidth: 1,
                borderDash: [4, 4],
                pointRadius: 0,
                pointHoverRadius: 0,
                fill: false,
              },
            ]
          : []

      this.chart = new Chart(ctx, {
        type: 'line',
        data: { labels: [], datasets: [...seriesDatasets, ...avgDatasets] },
        options: makeChartOptions(g, spec.yTitle, spec.yExtra),
      })

      this.handleEvent(
        'chart_data',
        ({ results, averages, thresholds }: ChartData) => {
          const chart = this.chart
          if (!chart) {
            return
          }
          chart.resize()
          const sorted = [...results].reverse()
          chart.data.labels = sorted.map(r => r.timestamp)
          spec.series.forEach((s, i) => {
            chart.data.datasets[i].data = sorted.map(r => r[s.field])
          })

          if (spec.averages && averages && sorted.length > 0) {
            const base = spec.series.length
            chart.data.datasets[base].data = sorted.map(() => averages.avg_7d)
            chart.data.datasets[base + 1].data = sorted.map(
              () => averages.avg_30d,
            )
          }

          const failed = spec.drawFailures
            ? sorted.filter(r => r.failed).map(r => r.timestamp)
            : []
          annotationOptions(chart).annotations = buildAnnotations(
            spec.thresholds ?? [],
            thresholds,
            failed,
          )

          chart.update()
        },
      )

      this.handleEvent('append_point', ({ point }: AppendPoint) => {
        const chart = this.chart
        if (!chart) {
          return
        }
        const labels = chart.data.labels ?? (chart.data.labels = [])
        labels.push(point.timestamp)
        spec.series.forEach((s, i) => {
          const data = chart.data.datasets[i].data as (null | number)[]
          data.push(point[s.field])
        })

        // Keep overlay lines in sync with data length
        if (spec.averages) {
          const base = spec.series.length
          const len = labels.length
          const d7 = chart.data.datasets[base].data as (null | number)[]
          const d30 = chart.data.datasets[base + 1].data as (null | number)[]
          const avg7 = d7[0] ?? null
          const avg30 = d30[0] ?? null
          chart.data.datasets[base].data = Array.from(
            { length: len },
            () => avg7,
          )
          chart.data.datasets[base + 1].data = Array.from(
            { length: len },
            () => avg30,
          )
        }

        if (spec.drawFailures && point.failed) {
          const annotations = annotationOptions(chart).annotations as Record<
            string,
            AnnotationOptions<'line'>
          >
          annotations[`fail-${point.timestamp}`] = failureAnnotation(
            point.timestamp,
          )
        }

        chart.update()
      })
    },
  }
}
