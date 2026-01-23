"""
Composite middleware for Nova allowing OAuth2 (Keycloak) authentication
and Keystone as fallback.

This middleware first tries to authenticate with OAuth2, and if that fails,
it tries with Keystone.
"""

from keystonemiddleware import auth_token
from keystonemiddleware.external_oauth2_token import ExternalOAuth2TokenMiddleware
import oslo_middleware.exceptions as exceptions


class CompositeAuthMiddleware(object):
    """Middleware that tries OAuth2 then Keystone as fallback."""

    def __init__(self, app, conf):
        self.app = app
        self.conf = conf
        
        # Create OAuth2 and Keystone middlewares
        try:
            self.oauth2_middleware = ExternalOAuth2TokenMiddleware(app, conf)
        except Exception:
            self.oauth2_middleware = None
            
        try:
            self.keystone_middleware = auth_token.AuthProtocol(app, conf)
        except Exception:
            self.keystone_middleware = None

    def __call__(self, env, start_response):
        # Try OAuth2 first
        if self.oauth2_middleware:
            try:
                return self.oauth2_middleware(env, start_response)
            except (exceptions.HTTPException, exceptions.Unauthorized):
                # If OAuth2 fails, try Keystone
                pass
        
        # Fallback to Keystone
        if self.keystone_middleware:
            return self.keystone_middleware(env, start_response)
        
        # If no middleware is available, pass the request through
        return self.app(env, start_response)


def filter_factory(global_conf, **local_conf):
    """Factory to create the composite middleware."""
    conf = global_conf.copy()
    conf.update(local_conf)
    
    def filter_(app):
        return CompositeAuthMiddleware(app, conf)
    
    return filter_
