/*
 * The gravity-sensor parallax behind the weather background.
 *
 * Port of two Android pieces:
 *   MaterialPainterView.kt:104-187   the TYPE_GRAVITY listener and the OrientationEventListener
 *                                    that together produce rotation2D / rotation3D
 *   DelayRotateController.kt         the accel/decel chaser that smooths them before they reach
 *                                    the implementors
 *
 * SettingsManager.isGravitySensorEnabled does not gate a feature flag upstream — it gates the
 * SensorManager itself (ContextExtensions.kt:80-85 returns null when the setting is off), so
 * registration silently no-ops and the rotations stay at 0. `setEnabled(false)` here does the same
 * thing by unsubscribing and zeroing, which lands in the same place: the listener's `else` branch
 * (kt:154-157) also writes 0 into both rotations when the setting is off.
 */

import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DEGREES: number = 180 / Math.PI;

/** MaterialPainterView.DeviceOrientation (kt:97-102). */
enum DeviceOrientation {
  TOP,
  LEFT,
  BOTTOM,
  RIGHT
}

/**
 * DelayRotateController.kt — the rotation the implementors see does not jump to the sensor's
 * value, it accelerates toward it at a fixed rate and brakes so it arrives without overshoot.
 * That is what stops the scene twitching on every sensor sample.
 */
export class DelayRotateController {
  /** kt:94. */
  private static readonly DEFAULT_ABS_ACCELERATION: number = 90.0 / 200.0 / 800.0;

  private targetRotation: number;
  private currentRotation: number;
  private velocity: number = 0;
  private acceleration: number = 0;

  constructor(initRotation: number) {
    this.targetRotation = DelayRotateController.rotationInScope(initRotation);
    this.currentRotation = this.targetRotation;
  }

  get rotation(): number {
    return this.currentRotation;
  }

  /** kt:34-74. */
  updateRotation(rotation: number, interval: number): void {
    this.targetRotation = DelayRotateController.rotationInScope(rotation);
    const rotationDiff: number = this.targetRotation - this.currentRotation;

    // no need to move
    if (rotationDiff === 0) {
      this.acceleration = 0;
      this.velocity = 0;
      return;
    }

    const accelSign: number = this.targetRotation > this.currentRotation ? 1 : -1;
    const oldVelocity: number = this.velocity;
    const absAccel: number = DelayRotateController.DEFAULT_ABS_ACCELERATION;

    if (this.velocity === 0 || rotationDiff * this.velocity < 0) {
      // start or turn around.
      this.acceleration = accelSign * absAccel;
      this.velocity = this.acceleration * interval;
    } else if (this.velocity * this.velocity / (2.0 * absAccel) < Math.abs(rotationDiff)) {
      // speed up
      this.acceleration = accelSign * absAccel;
      this.velocity += this.acceleration * interval;
    } else {
      // slow down
      this.acceleration = -1 * accelSign * this.velocity * this.velocity / (2.0 * Math.abs(rotationDiff));
      this.velocity += this.acceleration * interval;
    }

    const distance: number = oldVelocity * interval + this.acceleration * interval * interval / 2.0;

    if (Math.abs(distance) > Math.abs(rotationDiff)) {
      this.acceleration = 0;
      this.currentRotation = this.targetRotation;
      this.velocity = 0;
    } else {
      this.currentRotation += distance;
    }
  }

  /** kt:79-91 — fold the angle into [-90, 90] by reflecting it back at the poles. */
  private static rotationInScope(rotationP: number): number {
    const rotation: number = rotationP % 180.0;
    if (Math.abs(rotation) <= 90) {
      return rotation;
    }
    return rotation > 0 ? 90 - (rotation - 90) : -90 - (rotation + 90);
  }
}

/**
 * The raw sensor half: subscribes to TYPE_GRAVITY and turns each sample into the two angles the
 * scene leans by.
 */
export class GravitySensor {
  private subscribed: boolean = false;
  private enabled: boolean = false;
  private landscape: boolean = false;
  private deviceOrientation: DeviceOrientation = DeviceOrientation.TOP;
  private r2D: number = 0;
  private r3D: number = 0;

  /** (+) anticlockwise / (-) clockwise. */
  get rotation2D(): number {
    return this.r2D;
  }

  /** (+) look down / (-) look up. */
  get rotation3D(): number {
    return this.r3D;
  }

  /**
   * `Context.isLandscape` (Extensions.kt), which the orientation mapping below branches on. The
   * background is full-bleed, so the canvas being wider than it is tall is the same predicate.
   */
  setLandscape(landscape: boolean): void {
    this.landscape = landscape;
  }

  /** SettingsManager.isGravitySensorEnabled. */
  setEnabled(enabled: boolean): void {
    if (this.enabled === enabled) {
      return;
    }
    this.enabled = enabled;
    if (enabled) {
      this.start();
    } else {
      this.stop();
    }
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  /** kt:299-307 — resetDrawer zeroes both angles before registering. */
  start(): void {
    if (this.subscribed || !this.enabled) {
      return;
    }
    this.r2D = 0;
    this.r3D = 0;
    try {
      /*
       * Android registers at SENSOR_DELAY_FASTEST. The angles are only ever read once per drawn
       * frame (kt:252-253) and this port's loop runs at 30 fps, so sampling faster than the frame
       * rate changes nothing visible while costing callbacks the measurement has to carry. 20 ms
       * (50 Hz) stays comfortably above the loop; the interval is in nanoseconds.
       */
      sensor.on(sensor.SensorId.GRAVITY, (data: sensor.GravityResponse) => {
        this.onSample(data.x, data.y, data.z);
      }, { interval: 20000000 });
      this.subscribed = true;
    } catch (error) {
      // A device with no gravity sensor behaves like the setting being off, which is what
      // getDefaultSensor returning null does upstream.
      const err = error as BusinessError;
      console.error('GravitySensor: subscribe failed, code ' + err.code + ' ' + err.message);
      this.subscribed = false;
    }
  }

  /** kt:90 — the painter unregisters as soon as it stops being drawable. */
  stop(): void {
    if (this.subscribed) {
      try {
        sensor.off(sensor.SensorId.GRAVITY);
      } catch (error) {
        const err = error as BusinessError;
        console.error('GravitySensor: unsubscribe failed, code ' + err.code + ' ' + err.message);
      }
      this.subscribed = false;
    }
    this.r2D = 0;
    this.r3D = 0;
  }

  /**
   * kt:106-158.
   *   x : (+) fall to the left / (-) fall to the right.
   *   y : (+) stand / (-) head stand.
   *   z : (+) look down / (-) look up.
   */
  private onSample(aX: number, aY: number, aZ: number): void {
    this.updateDeviceOrientation(aX, aY, aZ);

    const g2D: number = Math.sqrt(aX * aX + aY * aY);
    const g3D: number = Math.sqrt(aX * aX + aY * aY + aZ * aZ);

    const cos2D: number = Math.max(-1, Math.min(1, aY / g2D));
    const cos3D: number = Math.max(-1, Math.min(1, g2D / g3D));

    let rotation2D: number = Math.acos(cos2D) * DEGREES * (aX >= 0 ? 1 : -1);
    const rotation3D: number = Math.acos(cos3D) * DEGREES * (aZ >= 0 ? 1 : -1);

    /*
     * A perfectly flat, perfectly still device makes g2D zero and both angles NaN — upstream
     * divides the same way and has the same hazard, but there a NaN is transient. Here it would
     * poison the chaser's accumulator permanently (NaN + distance is NaN forever), so the sample
     * is dropped instead of stored. Real sensor noise means this effectively never fires.
     */
    if (!Number.isFinite(rotation2D) || !Number.isFinite(rotation3D)) {
      return;
    }

    // kt:126-150 — the phone's own rotation is taken out of the 2D angle.
    switch (this.deviceOrientation) {
      case DeviceOrientation.TOP:
        break;
      case DeviceOrientation.LEFT:
        rotation2D -= 90;
        break;
      case DeviceOrientation.RIGHT:
        rotation2D += 90;
        break;
      case DeviceOrientation.BOTTOM:
        rotation2D = rotation2D > 0 ? rotation2D - 180 : rotation2D + 180;
        break;
      default:
        break;
    }

    // kt:151-153 — near flat, the 2D angle stops meaning anything, so it is damped out.
    if (60 < Math.abs(rotation3D) && Math.abs(rotation3D) < 120) {
      rotation2D *= Math.abs(Math.abs(rotation3D) - 90) / 30.0;
    }

    this.r2D = rotation2D;
    this.r3D = rotation3D;
  }

  /**
   * HarmonyOS has no OrientationEventListener, so the 0-359° device angle is derived here from the
   * same vector — which is what the Android listener does internally from the accelerometer:
   * negate the axes, reject the sample when the in-plane magnitude is small next to z (the phone
   * is too flat for the angle to mean anything), then `90 - round(atan2(-y, x))`.
   *
   * The mapping onto TOP/LEFT/BOTTOM/RIGHT is kt:172-186 unchanged.
   */
  private updateDeviceOrientation(aX: number, aY: number, aZ: number): void {
    const x: number = -aX;
    const y: number = -aY;
    const z: number = -aZ;
    const magnitude: number = x * x + y * y;
    if (magnitude * 4 < z * z) {
      // Not trustworthy — keep the orientation we had, exactly as the listener does.
      return;
    }
    let orientation: number = 90 - Math.round(Math.atan2(-y, x) * DEGREES);
    while (orientation >= 360) {
      orientation -= 360;
    }
    while (orientation < 0) {
      orientation += 360;
    }

    if (this.landscape) {
      this.deviceOrientation = (orientation >= 1 && orientation <= 179)
        ? DeviceOrientation.RIGHT
        : DeviceOrientation.LEFT;
    } else {
      this.deviceOrientation = (orientation > 270 || orientation < 90)
        ? DeviceOrientation.TOP
        : DeviceOrientation.BOTTOM;
    }
  }
}
