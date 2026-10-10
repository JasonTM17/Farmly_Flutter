import { Injectable } from '@nestjs/common';

export type ReadinessProbe = () => boolean | Promise<boolean>;

@Injectable()
export class ReadinessService {
  private readonly probes = new Map<string, ReadinessProbe>();

  register(name: 'database' | 'migrations', probe: ReadinessProbe): void {
    this.probes.set(name, probe);
  }

  async isReady(): Promise<boolean> {
    if (!this.probes.has('database') || !this.probes.has('migrations')) return false;
    try {
      for (const probe of this.probes.values()) {
        if (!await probe()) return false;
      }
      return true;
    } catch {
      return false;
    }
  }
}
