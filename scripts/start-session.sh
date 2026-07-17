#!/usr/bin/env bash
# Run this at the start of every work session on OTS-DevOps.
#
# What it does:
#   1. Loads your EC2 SSH key into an agent (prompts for your passphrase
#      once, only if it isn't already loaded).
#   2. Checks your current public IP against the Jenkins firewall
#      allowlist. If your ISP rotated your IP (this happens often), it
#      updates terraform/variables.tf and re-applies automatically.
#   3. Confirms SSH and Jenkins are actually reachable.
#   4. Prints the commands/URLs you need for the rest of the session.
#
# Usage: ./scripts/start-session.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
SSH_KEY="$HOME/.ssh/ots-devops"

echo "== OTS-DevOps session bootstrap =="
echo ""

# 1. SSH agent
if ! ssh-add -l 2>/dev/null | grep -qi "ots-devops"; then
    if [ -z "${SSH_AUTH_SOCK:-}" ]; then
        eval "$(ssh-agent -s)" >/dev/null
    fi
    echo "Loading SSH key (enter your passphrase)..."
    ssh-add "$SSH_KEY"
else
    echo "SSH key already loaded in agent."
fi
echo ""

# 2. Check IP against Jenkins allowlist, update Terraform if it changed
echo "Checking your current public IP..."
CURRENT_IP="$(curl -s --max-time 5 https://checkip.amazonaws.com)"
CURRENT_CIDR="${CURRENT_IP}/32"
ALLOWED_CIDR="$(grep -A3 'variable "jenkins_admin_cidr"' "$TF_DIR/variables.tf" | grep default | sed -E 's/.*"(.*)".*/\1/')"

echo "  Your IP:   $CURRENT_IP"
echo "  SG allows: $ALLOWED_CIDR"

if [ "$CURRENT_CIDR" != "$ALLOWED_CIDR" ]; then
    echo "  -> IP changed, updating Jenkins allowlist and applying Terraform..."
    sed -i "s#default     = \"${ALLOWED_CIDR}\"#default     = \"${CURRENT_CIDR}\"#" "$TF_DIR/variables.tf"
    (cd "$TF_DIR" && terraform apply -auto-approve)
else
    echo "  -> IP unchanged, no Terraform apply needed."
fi
echo ""

# 3. Resolve instance IP and verify connectivity
PUBLIC_IP="$(cd "$TF_DIR" && terraform output -raw public_ip)"

echo "Checking SSH connectivity..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY" "ubuntu@${PUBLIC_IP}" "echo ok" >/dev/null 2>&1; then
    echo "  SSH: OK"
else
    echo "  SSH: FAILED -- check the key/agent, or that the instance is running"
fi

echo "Checking Jenkins..."
JENKINS_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${PUBLIC_IP}:8080/" || echo "000")"
if [ "$JENKINS_CODE" = "000" ]; then
    echo "  Jenkins: UNREACHABLE (check the SG rule above, or that the service is running)"
else
    echo "  Jenkins: reachable (HTTP $JENKINS_CODE -- 403 is normal, it just means log in)"
fi
echo ""

echo "================================================"
echo " EC2 SSH:    ssh -i $SSH_KEY ubuntu@${PUBLIC_IP}"
echo " Jenkins UI: http://${PUBLIC_IP}:8080"
echo " App repo:   (on the EC2 box) ~/ONline_testing_app_django"
echo " Infra repo: $REPO_ROOT"
echo "================================================"
