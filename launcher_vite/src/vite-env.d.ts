/// <reference types="vite/client" />

interface Window {
  webkit?: {
    messageHandlers?: {
      launchProfile?: {
        postMessage(payload: { profile: string }): void
      }
      exitLauncher?: {
        postMessage(payload: Record<string, never>): void
      }
    }
  }
}
