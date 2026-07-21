import { describe, expect, it } from 'vitest';

import { type ComputeInstance, ComputeInstanceState } from '@osac/types';

import { isComputeInstanceDetailsSettled } from './compute-instance';

const vmWithState = (state: ComputeInstanceState): ComputeInstance =>
  ({ status: { state } }) as ComputeInstance;

describe('isComputeInstanceDetailsSettled', () => {
  it('returns false while the VM is still transitioning', () => {
    expect(isComputeInstanceDetailsSettled(undefined)).toBe(false);
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.UNSPECIFIED))).toBe(
      false,
    );
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.STARTING))).toBe(false);
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.STOPPING))).toBe(false);
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.DELETING))).toBe(false);
  });

  it('returns true once the VM is ready or failed', () => {
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.RUNNING))).toBe(true);
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.STOPPED))).toBe(true);
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.PAUSED))).toBe(true);
    expect(isComputeInstanceDetailsSettled(vmWithState(ComputeInstanceState.FAILED))).toBe(true);
  });
});
