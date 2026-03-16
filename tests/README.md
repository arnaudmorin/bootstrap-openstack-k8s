# Tests

This directory contains tests to validate the functionality of the various project components.

## Structure

```
tests/
├── README.md (this file)
├── keycloak/
│   ├── README.md
│   ├── run-all-tests.sh
│   ├── test-cli-installation.sh
│   ├── test-cli-connection.sh
│   └── test-realm-openstack.sh
└── nova/
    ├── README.md
    ├── run-all-tests.sh
    ├── test-create-instance-keystone.sh
    ├── test-reboot-instance-keycloak.sh
    └── test-keycloak-cannot-create.sh
```

## Available Tests

### Keycloak

Tests to validate the installation and functionality of Keycloak CLI tools.

See [keycloak/README.md](keycloak/README.md) for more details.

**Quick execution:**
```bash
cd tests/keycloak
./run-all-tests.sh
```

### Nova

Tests to validate Nova API functionality with both Keystone and Keycloak OAuth2 authentication.

See [nova/README.md](nova/README.md) for more details.

**Quick execution:**
```bash
cd tests/nova
./run-all-tests.sh
```

These tests verify:
- Instance creation with Keystone authentication (demo user)
- Instance reboot with Keycloak OAuth2 authentication (demo user)
- Security policy enforcement (Keycloak cannot create instances)

## Adding New Tests

To add new tests:

1. Create a subdirectory in `tests/` for the component to test
2. Add test scripts in this subdirectory
3. Create a `README.md` explaining the tests
4. Optionally, create a `run-all-tests.sh` script to run all tests for the component
