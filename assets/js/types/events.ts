// Mirrors lib/baudflow/measurements/measurement.ex @derive only: [...]
export interface Measurement {
  benchmarks: null | Record<string, unknown>
  // Download (bandwidth is bytes/sec, storage-only - never rendered as a rate)
  download_bandwidth: null | number
  download_bytes: null | number
  download_elapsed: null | number
  download_jitter: null | number
  download_mbps: null | number
  failed: boolean
  id: number
  inserted_at: string
  isp: null | string
  // Reliability
  packet_loss: null | number
  ping_high: null | number
  ping_jitter: null | number
  // Ping
  ping_latency: null | number
  ping_low: null | number
  // Result
  result_id: null | string
  result_url: null | string
  // Pipeline provenance (v2 forward-shape)
  schedule_id: null | number
  server_country: null | string
  server_host: null | string
  // Server
  server_id: null | number
  server_location: null | string
  server_name: null | string
  // Provenance
  source: null | string
  speedtest_version: null | string
  test_type: string
  timestamp: string
  // Upload
  upload_bandwidth: null | number
  upload_bytes: null | number
  upload_elapsed: null | number
  upload_jitter: null | number
  upload_mbps: null | number
}

// Global health thresholds the server evaluates per-row; each chart draws the
// subset relevant to its series via a `ThresholdKey`.
export type ThresholdKey = 'download' | 'ping' | 'upload'
export type Thresholds = Partial<Record<ThresholdKey, number>>

// `chart_data`: the full dataset for a chart. `averages` (7d/30d overlay) is only
// pushed to SpeedChart; `thresholds` only to charts that draw overlay lines.
export interface ChartAverages {
  avg_7d: number
  avg_30d: number
}

export interface ChartData {
  averages?: ChartAverages
  results: Measurement[]
  thresholds?: Thresholds
}

export interface AppendPoint {
  point: Measurement
}

export type SpeedtestProgress =
  | {
      data: { download?: { bandwidth?: number; progress?: number } }
      type: 'download'
    }
  | {
      data: { ping?: { jitter?: number; latency?: number; progress?: number } }
      type: 'ping'
    }
  | {
      data: { server?: { location?: string; name?: string } }
      type: 'testStart'
    }
  | {
      data: { upload?: { bandwidth?: number; progress?: number } }
      type: 'upload'
    }

export interface PingProgress {
  avg: number
  host: string
  jitter: number
  latency: null | number
  loss: number
  port: number
}

export interface RangeChanged {
  range: string
}

export type HeatStatus = 'breach' | 'empty' | 'failed' | 'healthy' | 'unknown'

export interface HeatmapCell {
  d: string
  v: HeatStatus
  x: number
  y: number
}

export interface HeatmapTile {
  cells: HeatmapCell[]
  weeks: number
}
