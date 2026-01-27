# Nova middleware (external_oauth2_token) and Keycloak token claims – plan

## Summary

The Nova API uses **keystonemiddleware.external_oauth2_token**, which validates Bearer tokens via Keycloak’s **introspection** endpoint and then parses the introspection JSON to build the request environment. The 403 *"The request you have made is denied, because the necessary information could not be parsed."* is raised when a **required** mapped claim is missing or has the wrong type.

This document describes what the middleware expects, what Keycloak currently sends, and a concrete plan to align them.

---

## 1. What the Nova middleware expects (source: keystonemiddleware)

From `keystonemiddleware.external_oauth2_token`:

- **ForbiddenToken** (HTTP 403 “necessary information could not be parsed”) is raised in `_read_data_from_token()` when a **required** mapping is missing or has the wrong type.
- **Required** mappings in `_parse_necessary_info()` are:
  - **mapping_roles** (required)
  - **mapping_project_name** (required when project scoped)
  - **mapping_project_domain_id** (required)
  - **mapping_project_domain_name** (required)
  - **mapping_user_id** (required)
  - **mapping_user_name** (required)
  - **mapping_user_domain_id** (required)
  - **mapping_user_domain_name** (required)

- **Roles** are used as: `roles.lower().split(',')`. So the value for the claim pointed to by `mapping_roles` **must be a string** (e.g. `"nova:reboot"` or `"default,member,nova:reboot"`). An array (e.g. from `realm_access.roles`) will cause a type error when `.lower()` is called.

- The middleware reads **top-level keys** from the introspection response: `token_metadata.get(meta_key)` where `meta_key` comes from the config (e.g. `mapping_roles` → `openstack_roles`).

---

## 2. Nova config (our mapping)

From `k8s/config.yaml.in` section `[ext_oauth2_auth]`:

| Config key                 | Claim name in token (meta_key) |
|---------------------------|---------------------------------|
| mapping_user_id           | sub                             |
| mapping_user_name         | preferred_username              |
| mapping_user_domain_id     | user_domain_id                  |
| mapping_user_domain_name   | user_domain                     |
| mapping_project_id        | project_id                      |
| mapping_project_name      | project_name                    |
| mapping_project_domain_id  | project_domain_id               |
| mapping_project_domain_name| project_domain                  |
| mapping_roles             | openstack_roles                 |

So the **introspection response** must contain these top-level keys, and `openstack_roles` must be a **string**.

---

## 3. What Keycloak currently provides

- **openstack-client** protocol mappers (from `k8s.tftpl`):
  - `project_id` ← user attribute `project_id` ✅
  - `project_name` ← user attribute `project_name` ✅
  - `project_domain` ← user attribute `project_domain` ✅
  - `user_domain` ← user attribute `user_domain` ✅
  - One mapper named “openstack_roles” that puts **realm roles** into claim **`realm_access.roles`** (array) ❌

- **Missing or wrong:**
  1. **project_domain_id** – no protocol mapper, no user attribute → middleware requires it → 403.
  2. **user_domain_id** – no protocol mapper, no user attribute → middleware requires it → 403.
  3. **openstack_roles** – middleware expects claim **name** `openstack_roles` and **type** string. We only have `realm_access.roles` (array). So either:
     - Add a mapper: user attribute `openstack_roles` → claim `openstack_roles` (String), and set that attribute on users (e.g. `"nova:reboot"` or `"default,member,nova:reboot"`), or
     - Change Nova config to `mapping_roles = realm_access.roles` and change middleware code to accept an array and convert to comma-separated string (not recommended).

- **sub** and **preferred_username** – usually present by default in Keycloak tokens; confirm in introspection response.

---

## 4. Plan

### Option A (recommended): Fix Keycloak so the token has all required claims

**4.1 Add protocol mappers (client `openstack-client`)**

- **project_domain_id**  
  - Type: `oidc-usermodel-attribute-mapper`  
  - User attribute: `project_domain_id`  
  - Claim name: `project_domain_id`  
  - Include in access token and **introspection** (introspection.token.claim = true).

- **user_domain_id**  
  - Same idea: user attribute `user_domain_id` → claim `user_domain_id`.

- **openstack_roles (string)**  
  - Type: `oidc-usermodel-attribute-mapper`  
  - User attribute: `openstack_roles`  
  - Claim name: `openstack_roles`  
  - JSON type: String  
  - Include in access token and introspection.  
  - Do **not** rely only on the existing realm-role mapper that fills `realm_access.roles` (array); the middleware expects a single string claim `openstack_roles`.

**4.2 User attributes**

- Set on every OpenStack/Keycloak user (demo, demo-reboot-only, demo-keycloak, nova-restart-user, etc.):
  - `project_domain_id`: e.g. `default` or the real OpenStack default domain ID.
  - `user_domain_id`: same.
  - `openstack_roles`: comma-separated string, e.g.:
    - `demo-reboot-only`: `nova:reboot`
    - `demo-keycloak`: `default,member` (or plus `nova:reboot` if they should reboot)
    - `demo`: e.g. `default,member`
    - `nova-restart-user`: `nova:reboot`

**4.3 User profile (Keycloak 26.x)**

- Ensure the realm User Profile includes attributes: `project_id`, `project_name`, `project_domain`, `user_domain`, `project_domain_id`, `user_domain_id`, `openstack_roles` (already done in tftpl for most; add `openstack_roles` and domain IDs if missing).

**4.4 Where to apply**

- **In Terraform/userdata** (`tofu/userdata/k8s.tftpl`): add the three mappers and extend user creation to set `project_domain_id`, `user_domain_id`, and `openstack_roles` for all created users.
- **On existing deployment (e.g. 57.128.30.161)**: one-time script or manual Keycloak changes:
  - Add mappers for `project_domain_id`, `user_domain_id`, and `openstack_roles` (attribute → claim, string).
  - Set user attributes for demo, demo-reboot-only, demo-keycloak (and any other users that use Nova with Keycloak).

**4.5 Optional: realm_access.roles**

- The existing mapper that fills `realm_access.roles` can stay for other consumers; Nova will use only `openstack_roles` as long as `mapping_roles = openstack_roles`.

---

### Option B: Change Nova config and/or middleware (not recommended)

- Set `mapping_roles = realm_access.roles` and patch keystonemiddleware so that when the value is a list, it is converted to a comma-separated string before `roles.lower().split(',')`. This would require maintaining a fork or downstream patch of keystonemiddleware and still would not fix the missing `project_domain_id` and `user_domain_id`, which must be added in Keycloak anyway.

---

## 5. Verification

After applying Option A:

1. Obtain a Bearer token for `demo-reboot-only` (or another test user).
2. Call Keycloak’s introspection endpoint with that token (using nova-middleware client credentials).
3. Inspect the JSON: it must contain at least:
   - `sub`, `preferred_username`
   - `user_domain_id`, `user_domain`
   - `project_id`, `project_name`, `project_domain_id`, `project_domain`
   - `openstack_roles` (string, e.g. `"nova:reboot"`).
4. Re-run the Nova reboot test (e.g. `test-reboot-instance-keycloak.sh`); the middleware should parse all required fields and return 2xx (or the appropriate Nova API result) instead of 403.

---

## 6. Checklist (Option A)

- [ ] Add protocol mapper `project_domain_id` (user attribute → claim, introspection).
- [ ] Add protocol mapper `user_domain_id` (user attribute → claim, introspection).
- [ ] Add protocol mapper `openstack_roles` (user attribute → claim `openstack_roles`, String, introspection).
- [ ] Ensure User Profile includes `project_domain_id`, `user_domain_id`, `openstack_roles`.
- [ ] Set user attributes on demo, demo-reboot-only, demo-keycloak (and any other Nova/Keycloak users): `project_domain_id`, `user_domain_id`, `openstack_roles`.
- [ ] Apply on 57.128.30.161 (one-time script or manual) and in k8s.tftpl for future deploys.
- [ ] Verify introspection response and re-run Nova reboot test.
