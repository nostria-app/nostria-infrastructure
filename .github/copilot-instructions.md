- @azure Rule - Use Azure Best Practices: When generating code for Azure, running terminal commands for Azure, or performing operations related to Azure, invoke your `azure_development-get_best_practices` tool if available.

Use shell: pwsh and not azure/powershell@v2 to run shell in GitHub workflows.

Use Managed Identity and role assignments instead of access keys for Azure resources.