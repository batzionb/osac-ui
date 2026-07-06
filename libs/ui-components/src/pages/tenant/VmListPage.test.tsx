import { MemoryRouter } from 'react-router-dom';
import { render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { ComputeInstancesListResponseSchema } from '@osac/types';

import { VmListPage } from './VmListPage';
import { decodeFulfillmentResponse } from '../../api/fulfillment-decode';
import type { ApiFetch } from '../../api/types';
import { initTestI18n } from '../../components/catalogProvision/test/i18n';
import { WizardTestProvidersWithI18n } from '../../components/catalogProvision/test/WizardTestProviders';

const createVmListFetch =
  (): ApiFetch =>
  async (route, options = {}) => {
    const { decode } = options;

    if (route === 'v1/compute_instances') {
      return decodeFulfillmentResponse(decode ?? ComputeInstancesListResponseSchema, { items: [] });
    }

    throw new Error(`Unexpected route in VmListPage test: ${route}`);
  };

const renderVmListPage = async (fetch: ApiFetch = createVmListFetch()) => {
  const i18n = await initTestI18n();
  return render(
    <MemoryRouter>
      <WizardTestProvidersWithI18n i18n={i18n} fetch={fetch}>
        <VmListPage />
      </WizardTestProvidersWithI18n>
    </MemoryRouter>,
  );
};

describe('VmListPage', () => {
  it('shows create virtual machine action for tenant users', async () => {
    await renderVmListPage();

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Create virtual machine' })).toBeInTheDocument();
    });
  });
});
