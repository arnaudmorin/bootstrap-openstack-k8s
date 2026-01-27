# Implementation Plan: Option B - CompositeAuthMiddleware

## Overview

This plan implements dual authentication (Keystone + OAuth2) in Nova using a composite middleware that routes requests based on authentication headers.

## Changes Made

### 1. Updated `api-paste.ini` Configuration

**File:** `k8s/config.yaml.in`

**Changes:**
- Added `[filter:composite_auth]` filter definition
- Updated `keystone` pipeline to use `composite_auth` instead of `authtoken`
- The `composite_auth` middleware routes:
  - `Authorization: Bearer <token>` → OAuth2 middleware
  - `X-Auth-Token: <token>` → Keystone middleware

**Before:**
```ini
keystone = ... authtoken keystonecontext ...
```

**After:**
```ini
keystone = ... composite_auth keystonecontext ...
```

### 2. Added CompositeAuthMiddleware to ConfigMap

**File:** `k8s/config.yaml.in`

Added `nova_oauth2_middleware.py` to the nova-conf ConfigMap with the CompositeAuthMiddleware implementation.

### 3. Updated Deployment

**File:** `k8s/nova.yaml.in`

Added volume mount for `nova_oauth2_middleware.py`:
```yaml
- name: nova-conf
  mountPath: /etc/nova/nova_oauth2_middleware.py
  subPath: nova_oauth2_middleware.py
```

## How It Works

### Request Flow

```
Request arrives
    │
    ├─► Has "Authorization: Bearer" header?
    │   └─► YES → Route to OAuth2 middleware (external_oauth2_token)
    │
    ├─► Has "X-Auth-Token" header?
    │   └─► YES → Route to Keystone middleware (authtoken)
    │
    └─► NO → Pass to app (will return 401)
```

### Pipeline Structure

```
cors → http_proxy_to_wsgi → compute_req_id → faultwrap → sizelimit 
  → composite_auth → keystonecontext → osapi_compute_app_v21
```

The `composite_auth` middleware:
1. Checks request headers
2. Routes to appropriate authentication middleware
3. Only ONE middleware processes each request (no interference)

## Advantages

✅ **No Nova code modification** - Uses existing middleware infrastructure  
✅ **No interference** - Only one middleware processes each request  
✅ **Easy to maintain** - Single file, clear logic  
✅ **Backward compatible** - Keystone authentication still works  
✅ **Flexible** - Can easily add more auth methods later  

## Deployment Steps

1. Apply ConfigMap changes:
   ```bash
   frep k8s/config.yaml.in:- --load config/config.yaml | kubectl apply -f -
   ```

2. Apply Deployment changes:
   ```bash
   frep k8s/nova.yaml.in:- --load config/config.yaml | kubectl apply -f -
   ```

3. Restart Nova API:
   ```bash
   kubectl rollout restart deployment/nova-api
   kubectl rollout status deployment/nova-api --timeout=120s
   ```

## Testing

### Test Keystone Authentication
```bash
curl -X GET "http://nova.<domain>/v2.1/<project_id>/servers" \
  -H "X-Auth-Token: <keystone_token>"
```

**Expected:** HTTP 200 with server list

### Test OAuth2 Authentication
```bash
curl -X GET "http://nova.<domain>/v2.1/<project_id>/servers" \
  -H "Authorization: Bearer <oauth2_token>"
```

**Expected:** HTTP 200 with server list

### Verify Logs
```bash
kubectl logs -l app=nova-api | grep -i "composite\|oauth\|keystone"
```

**Expected logs:**
- "OAuth2 middleware initialized successfully"
- "Keystone middleware initialized successfully"
- "Using OAuth2 authentication (Bearer token present)" (for OAuth2 requests)
- "Using Keystone authentication (X-Auth-Token present)" (for Keystone requests)

## Verification Checklist

- [ ] ConfigMap updated with nova_oauth2_middleware.py
- [ ] api-paste.ini updated with composite_auth filter
- [ ] Pipeline updated to use composite_auth
- [ ] Deployment updated to mount middleware file
- [ ] Nova API pods restarted
- [ ] Keystone authentication works (HTTP 200)
- [ ] OAuth2 authentication works (HTTP 200)
- [ ] Logs show both middlewares initialized
- [ ] No interference between authentication methods

## Troubleshooting

### Issue: Module not found
**Error:** `ModuleNotFoundError: No module named 'nova_oauth2_middleware'`

**Solution:** Verify PYTHONPATH includes `/etc/nova` and file is mounted correctly.

### Issue: Middleware not routing correctly
**Error:** Wrong authentication method used

**Solution:** Check logs for routing decisions. Verify headers are correct.

### Issue: 401 Unauthorized
**Error:** Both methods return 401

**Solution:** 
- Check middleware initialization logs
- Verify token validity
- Check Keycloak/Keystone connectivity

---

**Implementation Date:** 2026-01-27  
**Status:** Ready for deployment and testing
