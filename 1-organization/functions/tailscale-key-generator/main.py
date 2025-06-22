"""Cloud Function to automatically generate Tailscale auth keys using OAuth."""

import os
import json
import logging
from datetime import datetime, timedelta
from google.cloud import secretmanager
import requests
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID')
TAILNET = os.environ.get('TAILNET')

def get_secret(secret_id: str) -> str:
    """Retrieve secret from Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def get_oauth_token(client_id: str, client_secret: str) -> str:
    """Get OAuth access token from Tailscale."""
    token_url = "https://api.tailscale.com/api/v2/oauth/token"
    
    response = requests.post(
        token_url,
        data={
            "grant_type": "client_credentials",
            "scope": "devices"
        },
        auth=(client_id, client_secret)
    )
    
    response.raise_for_status()
    return response.json()["access_token"]

def create_auth_key(access_token: str) -> str:
    """Create a new auth key using the Tailscale API."""
    api_url = f"https://api.tailscale.com/api/v2/tailnet/{TAILNET}/keys"
    
    # Key expires in 90 days
    expiry = datetime.utcnow() + timedelta(days=90)
    
    key_data = {
        "capabilities": {
            "devices": {
                "create": {
                    "reusable": True,
                    "ephemeral": False,
                    "preauthorized": True,
                    "tags": ["tag:subnet-router", "tag:gcp"]
                }
            }
        },
        "expirySeconds": 90 * 24 * 60 * 60,  # 90 days
        "description": f"Auto-generated key for GCP routers - {datetime.utcnow().isoformat()}"
    }
    
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    
    response = requests.post(api_url, json=key_data, headers=headers)
    response.raise_for_status()
    
    return response.json()["key"]

def update_secret(secret_id: str, value: str) -> None:
    """Update secret in Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{PROJECT_ID}/secrets/{secret_id}"
    
    # Add new version
    response = client.add_secret_version(
        request={
            "parent": parent,
            "payload": {"data": value.encode("UTF-8")}
        }
    )
    
    logger.info(f"Added new version to secret: {response.name}")

def restart_instances() -> None:
    """Restart Tailscale router instances to pick up new key."""
    # This could be implemented to restart the instances
    # For now, instances will pick up new key on next restart
    logger.info("Instances will pick up new key on next restart")

@functions_framework.http
def generate_auth_key(request):
    """Main function entry point."""
    try:
        # Get OAuth credentials
        logger.info("Retrieving OAuth credentials")
        client_id = get_secret("tailscale-oauth-client-id")
        client_secret = get_secret("tailscale-oauth-client-secret")
        
        # Get OAuth token
        logger.info("Getting OAuth token")
        access_token = get_oauth_token(client_id, client_secret)
        
        # Create new auth key
        logger.info("Creating new auth key")
        auth_key = create_auth_key(access_token)
        
        # Update secret
        logger.info("Updating auth key secret")
        update_secret("tailscale-auth-key", auth_key)
        
        # Optionally restart instances
        restart_instances()
        
        return {
            "status": "success",
            "message": "Auth key rotated successfully",
            "timestamp": datetime.utcnow().isoformat()
        }, 200
        
    except Exception as e:
        logger.error(f"Error rotating auth key: {str(e)}")
        return {
            "status": "error",
            "message": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }, 500