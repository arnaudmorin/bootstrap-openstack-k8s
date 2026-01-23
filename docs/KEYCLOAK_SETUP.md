# Configuration Keycloak pour OpenStack

Ce document décrit comment configurer Keycloak pour l'authentification OAuth2 avec les services OpenStack, en commençant par Nova.

## Vue d'ensemble

Keycloak est déployé comme serveur d'autorisation externe pour OpenStack, permettant une gestion de droits plus fine via OAuth2.0. L'authentification Keystone reste disponible et n'est pas modifiée.

## Architecture

```
Client OpenStack
    │
    ├─► Token OAuth2 (Keycloak)
    │   └─► Nova API (pipeline keystone+oauth2)
    │       └─► Middleware external_oauth2_token
    │           └─► Introspection Keycloak
    │
    └─► Token Keystone (toujours disponible)
        └─► Nova API (pipeline keystone - par défaut)
            └─► Middleware authtoken
```

**Note importante**: Par défaut, Nova utilise le pipeline `keystone` qui supporte uniquement Keystone. Pour utiliser OAuth2 avec Keycloak, vous devez configurer Nova pour utiliser le pipeline `keystone+oauth2`. Les deux authentifications ne peuvent pas être utilisées simultanément sur le même endpoint sans middleware composite personnalisé.

## Déploiement Keycloak

Keycloak est déployé via Kubernetes et utilise MySQL comme base de données (comme tous les autres services OpenStack) :

```bash
# D'abord, créer la base MySQL pour Keycloak
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=keycloak | kubectl apply -f -

# Attendre que MySQL soit prêt
kubectl wait --for=condition=available --timeout=60s deployment/mysql-keycloak

# Ensuite, déployer Keycloak
frep k8s/keycloak.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Attendez que Keycloak soit prêt :

```bash
kubectl wait --for=condition=available --timeout=300s deployment/keycloak
```

**Note**: Keycloak utilise MySQL avec l'utilisateur `root` (comme tous les autres services OpenStack dans ce projet).

## Configuration initiale de Keycloak

### 1. Accéder à l'interface d'administration

1. Accédez à `http://keycloak.{{domain}}`
2. Connectez-vous avec :
   - Username: `admin`
   - Password: (valeur de `password` dans `config.yaml`)

### 2. Créer un Realm OpenStack

1. Dans le menu déroulant en haut à gauche, cliquez sur "Master" et sélectionnez "Create Realm"
2. Nom du realm: `openstack`
3. Cliquez sur "Create"

### 3. Configurer le Client pour Nova Middleware

Le middleware Nova a besoin d'un client OAuth2 pour s'authentifier auprès de Keycloak lors de l'introspection des tokens.

1. Dans le realm `openstack`, allez dans "Clients" → "Create client"
2. Client ID: `nova-middleware`
3. Client authentication: **ON** (confidential client)
4. Cliquez sur "Next"
5. Dans "Capability config":
   - Client authentication: **ON**
   - Authorization: **OFF** (pour simplifier)
   - Standard flow: **OFF**
   - Direct access grants: **OFF**
   - Service accounts roles: **ON** (important pour client credentials grant)
6. Cliquez sur "Next" puis "Save"

7. Allez dans l'onglet "Credentials" du client `nova-middleware`
8. Copiez le "Client secret" et mettez-le dans `config.yaml` sous `keycloak_client_secret`

9. Allez dans l'onglet "Service account roles"
10. Cliquez sur "Assign role" → "Filter by clients" → sélectionnez `realm-management`
11. Ajoutez le rôle `view-clients` (nécessaire pour l'introspection)

### 4. Configurer le Client pour les utilisateurs OpenStack

Les utilisateurs OpenStack auront besoin d'un client OAuth2 pour obtenir des tokens.

1. Dans "Clients" → "Create client"
2. Client ID: `openstack-client`
3. Client authentication: **OFF** (public client)
4. Cliquez sur "Next"
5. Dans "Capability config":
   - Standard flow: **ON**
   - Direct access grants: **ON** (pour client credentials grant)
   - Service accounts roles: **OFF**
6. Cliquez sur "Next" puis "Save"

7. Dans les paramètres du client `openstack-client`:
   - Valid redirect URIs: `*` (ou spécifiez les URLs de vos services)
   - Web origins: `*` (ou spécifiez les domaines)

### 5. Configurer les Mappers pour les tokens

Les mappers permettent d'inclure les informations nécessaires (project, roles, etc.) dans les tokens.

#### Mapper pour project_id et project_name

1. Allez dans "Clients" → `openstack-client` → "Client scopes" → "openstack-client-dedicated" → "Mappers"
2. Cliquez sur "Create mapper"
3. Mapper type: "User Attribute"
4. Name: `project_id`
5. User Attribute: `project_id`
6. Token Claim Name: `project_id`
7. Claim JSON Type: `String`
8. Add to ID token: **ON**
9. Add to access token: **ON**
10. Cliquez sur "Save"

Répétez pour `project_name` et `project_domain` (utilisez les mêmes noms pour User Attribute et Token Claim Name).

#### Mapper pour user_domain

1. Créez un mapper de type "User Attribute"
2. Name: `user_domain`
3. User Attribute: `user_domain`
4. Token Claim Name: `user_domain`
5. Claim JSON Type: `String`
6. Add to ID token: **ON**
7. Add to access token: **ON**

#### Mapper pour les rôles OpenStack

1. Créez un mapper de type "User Realm Role"
2. Name: `openstack_roles`
3. Token Claim Name: `realm_access.roles`
4. Claim JSON Type: `String`
5. Multivalued: **ON**
6. Add to ID token: **ON**
7. Add to access token: **ON**

### 6. Créer un utilisateur exemple

Créons un utilisateur qui peut seulement redémarrer les instances Nova.

1. Allez dans "Users" → "Create new user"
2. Username: `nova-restart-user`
3. Email: `nova-restart@example.com`
4. First name: `Nova`
5. Last name: `Restart`
6. User enabled: **ON**
7. Cliquez sur "Create"

8. Allez dans l'onglet "Credentials" et définissez un mot de passe (temporaire ou permanent)

9. Allez dans l'onglet "Attributes"
10. Ajoutez les attributs suivants :
    - Key: `project_id`, Value: `<ID_DU_PROJET_OPENSTACK>`
    - Key: `project_name`, Value: `<NOM_DU_PROJET_OPENSTACK>`
    - Key: `project_domain`, Value: `Default`
    - Key: `user_domain`, Value: `Default`

**Note**: Vous devez obtenir l'ID et le nom du projet depuis Keystone :
```bash
source /root/openrc_admin
openstack project list
openstack project show <project_name>
```

### 7. Créer un rôle pour redémarrer les instances

1. Allez dans "Realm roles" → "Create role"
2. Role name: `nova:reboot`
3. Description: `Permission to reboot Nova instances`
4. Cliquez sur "Save"

2. Allez dans "Users" → `nova-restart-user` → "Role mapping" → "Assign role"
3. Sélectionnez le rôle `nova:reboot`
4. Cliquez sur "Assign"

### 8. Configurer la politique Nova

Pour que le rôle Keycloak soit reconnu par Nova, vous devez créer une politique Nova personnalisée.

1. Créez un fichier de politique dans le pod Nova :

```bash
kubectl exec -it deployment/nova-api -- bash
```

2. Créez `/etc/nova/policy.d/keycloak-policy.yaml` :

```yaml
# Policy pour permettre le redémarrage avec le rôle Keycloak
"os_compute_api:servers:reboot": "role:nova:reboot or role:admin"
"os_compute_api:servers:reboot:create": "role:nova:reboot or role:admin"
```

3. Redémarrez Nova API :

```bash
kubectl rollout restart deployment/nova-api
```

## Configuration de Nova pour utiliser OAuth2

Par défaut, Nova utilise le pipeline `keystone` qui supporte uniquement Keystone. Pour activer OAuth2 avec Keycloak, vous devez modifier la configuration Nova :

1. Modifiez `nova.conf` pour utiliser le pipeline OAuth2 :

```bash
kubectl edit configmap nova-conf
```

Ajoutez dans la section `[DEFAULT]` ou créez une section `[api]` :

```ini
[api]
auth_strategy = keystone+oauth2
```

2. Redémarrez Nova API :

```bash
kubectl rollout restart deployment/nova-api
```

**Alternative**: Vous pouvez aussi utiliser le pipeline `keystone` (par défaut) pour Keystone et créer un endpoint séparé pour OAuth2, mais cela nécessite une configuration plus complexe.

## Utilisation

### Obtenir un token OAuth2 depuis Keycloak

```bash
# Obtenir un token avec client credentials grant
TOKEN=$(curl -X POST "http://keycloak.{{domain}}/realms/openstack/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=openstack-client" \
  -d "username=nova-restart-user" \
  -d "password=<PASSWORD>" \
  -d "grant_type=password" \
  -d "scope=openid" | jq -r '.access_token')

echo $TOKEN
```

### Utiliser le token avec l'API Nova

```bash
# Redémarrer une instance (devrait fonctionner)
curl -X POST "http://nova.{{domain}}/v2.1/<project_id>/servers/<server_id>/action" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reboot": {"type": "SOFT"}}'

# Lister les instances (devrait échouer avec 403)
curl -X GET "http://nova.{{domain}}/v2.1/<project_id>/servers" \
  -H "Authorization: Bearer $TOKEN"
```

## Configuration avancée

### Mapping des rôles Keycloak vers les rôles OpenStack

Si vous voulez mapper les rôles Keycloak vers les rôles OpenStack existants, vous pouvez :

1. Créer des groupes dans Keycloak correspondant aux projets OpenStack
2. Assigner les rôles OpenStack aux groupes
3. Utiliser un mapper de groupe pour inclure les rôles dans le token

### Support de plusieurs services

Pour ajouter le support OAuth2 à d'autres services OpenStack (Glance, Neutron, etc.) :

1. Répétez les étapes de configuration pour chaque service
2. Ajoutez la section `[external_oauth2_token]` dans la configuration de chaque service
3. Créez un fichier `api-paste.ini` similaire pour chaque service
4. Modifiez le déploiement Kubernetes pour utiliser paste deploy

## Dépannage

### Vérifier que Keycloak est accessible

```bash
curl http://keycloak.{{domain}}/health/ready
```

### Vérifier les logs Nova

```bash
kubectl logs deployment/nova-api -f
```

### Vérifier l'introspection du token

```bash
curl -X POST "http://keycloak.{{domain}}/realms/openstack/protocol/openid-connect/token/introspect" \
  -u "nova-middleware:<client_secret>" \
  -d "token=$TOKEN" \
  -d "token_type_hint=access_token"
```

### Problèmes courants

1. **401 Unauthorized lors de l'introspection** : Vérifiez que le client secret est correct dans `config.yaml`
2. **403 Forbidden** : Vérifiez que les mappers incluent bien les attributs nécessaires (project_id, roles, etc.)
3. **Token invalide** : Vérifiez que le token n'est pas expiré et que le realm est correct

## Références

- [OpenStack Spec: External OAuth2.0 Authorization Server Support](https://specs.openstack.org/openstack/keystone-specs/specs/keystonemiddleware/2023.1/external_authentication_server_oauth2_grant_support.html)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [RFC 7662: OAuth 2.0 Token Introspection](https://datatracker.ietf.org/doc/html/rfc7662)
