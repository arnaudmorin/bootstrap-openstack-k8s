# Keycloak Tests

This directory contains tests to validate the installation and functionality of Keycloak CLI tools.

## Prerequisites

- Keycloak 26.0.0 installed in `/root/keycloak-26.0.0/`
- File `/root/keycloakrc` configured with credentials
- PATH configured via `/etc/profile.d/keycloak.sh`

## Test Scripts

### 1. `test-cli-installation.sh`
Tests the installation of Keycloak binaries and PATH configuration.

**Usage:**
```bash
./test-cli-installation.sh
```

**Checks:**
- Presence of Keycloak 26.0.0
- Presence of `kcreg.sh` and `kcadm.sh` binaries
- PATH configuration

### 2. `test-cli-connection.sh`
Tests the connection to Keycloak CLI tools with configured credentials.

**Usage:**
```bash
./test-cli-connection.sh
```

**Checks:**
- Loading of `keycloakrc` file
- Connection of `kcadm.sh` to master realm
- List of realms (checks for presence of `openstack` realm)
- Configuration of `kcreg.sh` credentials

### 3. `test-realm-openstack.sh`
Tests access to `openstack` realm resources.

**Usage:**
```bash
./test-realm-openstack.sh
```

**Checks:**
- Access to `openstack` realm
- List of clients (checks for `nova-middleware` and `openstack-client`)
- List of users (checks for `nova-restart-user`)
- List of roles (checks for `nova:reboot`)

## Running All Tests

To run all tests in order:

```bash
cd /home/plibeau/dev/github/bootstrap-openstack-k8s/tests/keycloak
chmod +x *.sh
./test-cli-installation.sh
./test-cli-connection.sh
./test-realm-openstack.sh
```

Or in a single command:

```bash
cd /home/plibeau/dev/github/bootstrap-openstack-k8s/tests/keycloak
chmod +x *.sh
for test in test-*.sh; do
  echo "=== Running $test ==="
  ./"$test"
  echo ""
done
```

## Environment Variables

Tests use variables defined in `/root/keycloakrc`:
- `KEYCLOAK_URL`: Keycloak server URL
- `KEYCLOAK_USER`: Admin username
- `KEYCLOAK_PASSWORD`: Admin password
- `KEYCLOAK_REALM`: Realm name (usually `openstack`)

## Notes

- Tests require root access or appropriate permissions
- Tests connect to `master` realm to manage `openstack` realm
- `kcreg.sh` requires client credentials for some operations (not tested here)
