# Nova API Tests

This directory contains tests to validate Nova API functionality with both Keystone and Keycloak OAuth2 authentication.

## Overview

These tests verify that:
1. **Keystone authentication** works correctly for creating Nova instances (demo user)
2. **Keycloak OAuth2 authentication** works correctly for rebooting Nova instances (demo user)
3. **Keycloak OAuth2 authentication** correctly prevents instance creation (security policy enforcement)

## Prerequisites

- OpenStack environment with Nova API deployed
- Keystone authentication configured
- Keycloak OAuth2 authentication configured for Nova
- Demo user and project exist in Keystone
- Demo user exists in Keycloak realm (or will be created automatically)
- OpenRC files available:
  - `/root/openrc_demo` - Demo user credentials for Keystone
  - `/root/keycloakrc` - Keycloak configuration

## Test Files

### `test-create-instance-keystone.sh`
Creates a Nova instance using Keystone authentication with the demo user.

**What it does:**
- Loads demo openrc credentials
- Gets project ID, image, flavor, and network
- Creates a new Nova instance
- Waits for instance to be ACTIVE
- Saves instance ID for subsequent tests

**Expected result:** Instance created successfully

### `test-reboot-instance-keycloak.sh`
Reboots a Nova instance using Keycloak OAuth2 authentication with the demo user.

**What it does:**
- Loads instance ID from previous test
- Obtains OAuth2 token from Keycloak
- Sends reboot request to Nova API with OAuth2 token
- Waits for instance to be ACTIVE again

**Expected result:** Instance rebooted successfully

### `test-keycloak-cannot-create.sh`
Verifies that Keycloak OAuth2 authentication cannot create instances (only reboot allowed).

**What it does:**
- Obtains OAuth2 token from Keycloak
- Attempts to create a new instance using OAuth2 token
- Verifies that the request is denied (HTTP 403)

**Expected result:** Instance creation denied with 403 Forbidden

## Running Tests

### Run all tests in sequence:
```bash
cd tests/nova
./run-all-tests.sh
```

### Run individual tests:
```bash
cd tests/nova
./test-create-instance-keystone.sh
./test-reboot-instance-keycloak.sh
./test-keycloak-cannot-create.sh
```

## Test Execution Order

The tests must be run in the following order:
1. `test-create-instance-keystone.sh` - Creates the instance
2. `test-reboot-instance-keycloak.sh` - Reboots the instance (requires instance from test 1)
3. `test-keycloak-cannot-create.sh` - Verifies security policy (independent)

The `run-all-tests.sh` script runs all tests in the correct order and handles cleanup automatically.

## Cleanup

The `run-all-tests.sh` script automatically cleans up test resources (deletes the created instance) on exit. If you run tests individually, you may need to manually delete the test instance:

```bash
source /root/openrc_demo
openstack server delete <instance-id>
```

## Troubleshooting

### Demo user not found in Keycloak
If the demo user doesn't exist in Keycloak, you may need to create it first:

```bash
source /root/keycloakrc
# Create demo user in Keycloak (adjust as needed)
/root/keycloak-26.0.0/bin/kcadm.sh create users \
  --realm openstack \
  -s username=demo \
  -s enabled=true \
  -s email=demo@example.com
```

### OAuth2 token request fails
- Verify Keycloak is accessible
- Check that the `openstack-client` client exists in Keycloak
- Verify demo user credentials are correct
- Check that demo user has required attributes (project_id, project_name, etc.)

### Instance creation fails
- Verify Keystone authentication works: `openstack server list`
- Check that images and flavors are available
- Verify network configuration

### Reboot fails with 401/403
- Verify OAuth2 token is valid
- Check that Nova API is configured to use Keycloak OAuth2
- Verify that the demo user has the `nova:reboot` role in Keycloak

## Notes

- Tests use the demo user/project, not admin
- Instance IDs are saved to `/tmp/nova-test-instance-id.txt` for use between tests
- Tests include timeouts and error handling
- All tests use the same instance to minimize resource usage
