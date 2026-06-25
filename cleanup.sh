#!/bin/bash

# AWS DevOps Agent Terraform Cleanup Script

set -e

echo "🧹 AWS DevOps Agent Terraform Cleanup"
echo "====================================="

# Check if terraform.tfstate exists
if [ ! -f "terraform.tfstate" ]; then
    echo "❌ No Terraform state found. Nothing to clean up."
    exit 0
fi

# Show what will be destroyed
echo "🔍 Planning destruction..."
terraform plan -destroy

echo ""
echo "⚠️  WARNING: This will destroy all AWS DevOps Agent resources!"
echo "   - Agent Space and all associations"
echo "   - IAM roles and policies"
echo "   - All monitoring configurations"
echo ""
read -p "🤔 Are you sure you want to destroy everything? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo ""
read -p "🚨 Last chance! Type 'DESTROY' to confirm: " confirm
if [ "$confirm" != "DESTROY" ]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

# Destroy resources
echo "🧹 Destroying resources..."
terraform destroy -auto-approve

echo ""
echo "✅ Cleanup completed successfully!"
echo "   All AWS DevOps Agent resources have been removed."