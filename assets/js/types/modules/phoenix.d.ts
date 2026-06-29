export type SocketOptions = Record<string, unknown>

export class Socket {
  constructor(endPoint: string, opts?: SocketOptions)
  connect(): void
  disconnect(cb?: () => void): void
}
