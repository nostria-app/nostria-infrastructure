# Example: Deploy with secrets from environment variables
# Set environment variables first:
# $env:PRIVATE_VAPID_KEY = "your-private-vapid-key"
# $env:NOTIFICATION_API_KEY = "your-notification-api-key"

# Convert to SecureString
$privateVapidKeySecure = ConvertTo-SecureString -String $env:PRIVATE_VAPID_KEY -AsPlainText -Force
$notificationApiKeySecure = ConvertTo-SecureString -String $env:NOTIFICATION_API_KEY -AsPlainText -Force

# Deploy with secrets
.\deploy-main.ps1 -PrivateVapidKey $privateVapidKeySecure -NotificationApiKey $notificationApiKeySecure

# Alternative: Deploy without secrets (will prompt)
# .\deploy-main.ps1

# Alternative: Deploy with what-if to preview changes
# .\deploy-main.ps1 -PrivateVapidKey $privateVapidKeySecure -NotificationApiKey $notificationApiKeySecure -WhatIf
