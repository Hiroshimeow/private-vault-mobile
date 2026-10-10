import { AppSettings } from '../../types';
import { LockController } from '../auth/lockController';

export class PanicEvaluator {
  private shakeThreshold: number;
  private debounceMs: number;
  private faceDownDelayMs: number;
  private lastTriggerTime: number | null = null;
  private faceDownSince: number | null = null;

  constructor(shakeThreshold = 2.5, debounceMs = 2000, faceDownDelayMs = 1200) {
    this.shakeThreshold = shakeThreshold;
    this.debounceMs = debounceMs;
    this.faceDownDelayMs = faceDownDelayMs;
  }

  updateConfig(shakeThreshold: number, faceDownDelayMs: number): void {
    this.shakeThreshold = shakeThreshold;
    this.faceDownDelayMs = faceDownDelayMs;
  }

  onAccelerationG(magnitudeG: number, now: number): boolean {
    if (magnitudeG < this.shakeThreshold || !this.canTrigger(now)) {
      return false;
    }
    this.lastTriggerTime = now;
    return true;
  }

  onFaceDown(isFaceDown: boolean, now: number): boolean {
    if (!isFaceDown) {
      this.faceDownSince = null;
      return false;
    }

    if (this.faceDownSince === null) {
      this.faceDownSince = now;
      return false;
    }

    if (now - this.faceDownSince < this.faceDownDelayMs || !this.canTrigger(now)) {
      return false;
    }

    this.lastTriggerTime = now;
    this.faceDownSince = null;
    return true;
  }

  private canTrigger(now: number): boolean {
    return this.lastTriggerTime === null || now - this.lastTriggerTime >= this.debounceMs;
  }
}

export class PanicSensorService {
  private lockController: LockController;
  private settings: AppSettings;
  private evaluator: PanicEvaluator;
  private motionHandler: ((e: DeviceMotionEvent) => void) | null = null;
  private orientationHandler: ((e: DeviceOrientationEvent) => void) | null = null;
  private keydownHandler: ((e: KeyboardEvent) => void) | null = null;
  private running = false;

  constructor(lockController: LockController, settings: AppSettings) {
    this.lockController = lockController;
    this.settings = settings;
    this.evaluator = new PanicEvaluator(
      settings.shakeThresholdG,
      2000,
      settings.faceDownDelayMs
    );
  }

  start(): void {
    if (this.running || typeof window === 'undefined') return;
    this.running = true;

    this.motionHandler = (event: DeviceMotionEvent) => {
      if (!this.settings.panicShakeEnabled) return;
      const acc = event.accelerationIncludingGravity || event.acceleration;
      if (!acc || acc.x === null || acc.y === null || acc.z === null) return;

      const m = Math.sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z) / 9.80665;
      if (this.evaluator.onAccelerationG(m, Date.now())) {
        this.lockController.panic();
      }
    };

    this.orientationHandler = (event: DeviceOrientationEvent) => {
      if (!this.settings.panicFaceDownEnabled) return;
      const beta = event.beta;
      const isFaceDown = beta !== null && (Math.abs(beta) > 150 || Math.abs(beta) < -150);
      if (this.evaluator.onFaceDown(isFaceDown, Date.now())) {
        this.lockController.panic();
      }
    };

    this.keydownHandler = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !this.lockController.isLocked) {
        this.lockController.panic();
      }
    };

    window.addEventListener('devicemotion', this.motionHandler, { passive: true });
    window.addEventListener('deviceorientation', this.orientationHandler, { passive: true });
    window.addEventListener('keydown', this.keydownHandler);
  }

  updateSettings(settings: AppSettings): void {
    this.settings = settings;
    this.evaluator.updateConfig(settings.shakeThresholdG, settings.faceDownDelayMs);
  }

  triggerPanic(): void {
    this.lockController.panic();
  }

  dispose(): void {
    this.running = false;
    if (this.motionHandler) {
      window.removeEventListener('devicemotion', this.motionHandler);
      this.motionHandler = null;
    }
    if (this.orientationHandler) {
      window.removeEventListener('deviceorientation', this.orientationHandler);
      this.orientationHandler = null;
    }
    if (this.keydownHandler) {
      window.removeEventListener('keydown', this.keydownHandler);
      this.keydownHandler = null;
    }
  }
}
