import { I18nextProvider } from 'react-i18next';
import { MemoryRouter } from 'react-router-dom';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { initTestI18n } from '@osac/ui-components/components/catalogProvision/test/i18n';
import { SessionProvider } from '@osac/ui-components/hooks/use-session';
import type { DemoShellRole } from '@osac/ui-components/shellTypes';

import { ShellSidebar } from './ShellSidebar';

const renderShellSidebar = async (role: DemoShellRole) => {
  const i18n = await initTestI18n();
  return render(
    <MemoryRouter>
      <I18nextProvider i18n={i18n}>
        <SessionProvider role={role} username="test@example.com">
          <ShellSidebar />
        </SessionProvider>
      </I18nextProvider>
    </MemoryRouter>,
  );
};

describe('ShellSidebar', () => {
  it('shows Virtual Machines in tenant user Services nav', async () => {
    await renderShellSidebar('tenantUser');

    expect(screen.getByRole('navigation', { name: 'Primary navigation' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Virtual Machines' })).toBeInTheDocument();
  });

  it('shows Virtual Machines in tenant admin Services nav', async () => {
    await renderShellSidebar('tenantAdmin');

    expect(screen.getByRole('link', { name: 'Virtual Machines' })).toBeInTheDocument();
  });

  it('does not show Virtual Machines in provider admin nav', async () => {
    await renderShellSidebar('providerAdmin');

    expect(screen.queryByRole('link', { name: 'Virtual Machines' })).not.toBeInTheDocument();
  });
});
