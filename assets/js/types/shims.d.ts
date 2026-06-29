import type { LiveSocket } from 'phoenix_live_view'

declare global {
  const process: {
    env: Record<string, string | undefined>
  }

  interface Window {
    liveReloader?: {
      disableServerLogs(): void
      enableServerLogs(): void
      openEditorAtCaller(target: unknown): void
      openEditorAtDef(target: unknown): void
    }
    liveSocket?: InstanceType<typeof LiveSocket>
  }
}

export {}
