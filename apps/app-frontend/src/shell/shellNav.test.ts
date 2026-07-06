import { describe, expect, it } from 'vitest';

import { navRowsForRole } from './shellNav';

const t = (key: string) => key;

const findServicesLinks = (role: 'tenantUser' | 'tenantAdmin' | 'providerAdmin') => {
  const rows = navRowsForRole(role, t);
  const sectionId = role === 'tenantAdmin' ? 'nav-admin-services' : 'nav-tenant-services';
  return rows.find((row) => row.sectionId === sectionId)?.children ?? [];
};

describe('shellNav', () => {
  it('includes Virtual Machines in tenant user Services nav', () => {
    const links = findServicesLinks('tenantUser');
    expect(links).toContainEqual({
      id: 'compute-vms',
      label: 'Virtual Machines',
      path: '/vms',
    });
  });

  it('includes Virtual Machines in tenant admin Services nav', () => {
    const links = findServicesLinks('tenantAdmin');
    expect(links).toContainEqual({
      id: 'compute-vms',
      label: 'Virtual Machines',
      path: '/vms',
    });
  });

  it('does not include Virtual Machines in provider admin nav', () => {
    const rows = navRowsForRole('providerAdmin', t);
    const links = rows.flatMap((row) => row.children);
    expect(links.some((link) => link.id === 'compute-vms')).toBe(false);
  });
});
