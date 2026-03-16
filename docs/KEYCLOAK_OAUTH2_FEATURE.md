# Keycloak OAuth2 integration for OpenStack Nova

This feature adds **dual authentication** to Nova: requests can use either **Keystone** (X-Auth-Token) or **Keycloak OAuth2** (Bearer token). The same Nova API accepts both; no separate pipeline or endpoint.

## What we did

1. **Install Keycloak**
   Keycloak is deployed on the control plane (k8s) with a dedicated MySQL database. The deploy userdata installs the Keycloak CLI (kcadm.sh) and creates a keycloakrc file (similar to openrc).

2. **Configure Keycloak with Keystone**
   After Keystone is bootstrapped, the deploy script configures Keycloak:
   - Realm `openstack`
   - Clients: `nova-middleware` (token introspection by Nova), `openstack-client` (user tokens)
   - Protocol mappers so tokens carry OpenStack attributes: `project_id`, `project_name`, `project_domain`, `user_domain`, `project_domain_id`, `user_domain_id`, `openstack_roles` (string)
   - User profile updated for Keycloak 26.x so custom attributes persist
   - Realm role `nova:reboot` and users: `demo`, `demo-reboot-only`, `demo-keycloak`, `nova-restart-user` with correct attributes and passwords (demo password from openrc_demo)

3. **Configure Nova**
   - Nova uses a composite middleware that routes:
     - `Authorization: Bearer <token>` -> keystonemiddleware `external_oauth2_token` (Keycloak)
     - `X-Auth-Token: <token>` -> Keystone auth_token
   - Nova conf: `[ext_oauth2_auth]` with Keycloak introspection URL, client credentials (nova-middleware), and claim mappings so the middleware gets project/domain/roles from the token.
   - Nova policy: `os_compute_api:servers:reboot` (and `:create`) allow `role:nova:reboot` so Keycloak users with that role can reboot servers.
   - Policy file is in a ConfigMap and mounted under `/etc/nova/policy.d`.

4. **Tests**
   - **Keycloak**: CLI installation, connection, realm openstack (clients, users, roles).
   - **Nova**: create instance with Keystone (demo), create instance with Keycloak (demo-keycloak), reboot instance with Keycloak (demo-reboot-only), and a test that a user without create permission cannot create (keycloak-cannot-create). All tests run as the demo user (openrc_demo).

## Flow

- User gets an OAuth2 token from Keycloak (realm openstack, client openstack-client, e.g. username demo-reboot-only / demo password).
- User calls Nova with `Authorization: Bearer <token>`.
- Nova composite middleware forwards to external_oauth2_token, which introspects the token with Keycloak (using nova-middleware client).
- Introspection response must contain the mapped claims (project_id, project_domain_id, user_domain_id, openstack_roles string, etc.); Keycloak is configured with protocol mappers and user attributes so that is true.
- Middleware fills request env (project, user, roles); Nova policy allows reboot for role `nova:reboot`.

## Files touched

| Purpose | Files |
|--------|--------|
| Keycloak install | k8s/keycloak.yaml.in, k8s/mysql.yaml.in (keycloak db) |
| Keycloak config at deploy | keycloak-bootstrap/, files/keycloakrc.in |
| Nova dual auth | k8s/config.yaml.in (ext_oauth2_auth, api-paste.ini, nova policy), k8s/nova.yaml.in (policy.d mount) |
| Tests | tests/keycloak/*, tests/nova/* |

## Troubleshooting

### Keycloak connectivity

```bash
curl http://keycloak.<domain>/health/ready
```

### Nova logs

```bash
kubectl logs deployment/nova-api -f
```

### Token introspection

```bash
curl -X POST "http://keycloak.<domain>/realms/openstack/protocol/openid-connect/token/introspect" \
  -u "nova-middleware:<client_secret>" \
  -d "token=$TOKEN" \
  -d "token_type_hint=access_token"
```

### Common issues

- **401 Unauthorized on introspection**: Check `keycloak_client_secret` in `config.yaml` matches the nova-middleware client secret in Keycloak.
- **403 Forbidden**: Verify protocol mappers include required claims (`project_id`, `project_domain_id`, `user_domain_id`, `openstack_roles` string) and user attributes are set.
- **Invalid token**: Check token expiration and realm (`openstack`).
