# Command Reference

The actual commands used to build, deploy, and debug this project — organized by tool, not chronologically. When in doubt about "how do I do X again," look here before re-deriving it.

## Terraform (run from `terraform/`, on your WSL laptop)

```bash
terraform init                  # one-time, downloads the AWS provider
terraform plan                  # ALWAYS run before apply -- shows what would change
terraform apply -auto-approve   # actually makes the change

terraform output                # show all outputs (public_ip, ssh_command, etc.)
terraform output -raw public_ip  # just the raw value, no quotes -- useful in scripts
```

## SSH — connecting to the server

```bash
# Normal interactive use:
ssh -i ~/.ssh/ots-devops ubuntu@13.203.126.12

# Loading the key into an agent once, so you're not asked for the
# passphrase on every single command (needed before running Ansible):
eval $(ssh-agent -s)
ssh-add ~/.ssh/ots-devops
```

## Ansible (run from `ansible/`, on your WSL laptop)

```bash
ansible-playbook playbooks/site.yml --syntax-check   # catch YAML mistakes before running anything
ansible-playbook playbooks/site.yml --check --diff   # dry run -- show what WOULD change, don't actually change it
ansible-playbook playbooks/site.yml                   # the real run
```

## Docker (on the EC2 box — Jenkins runs these automatically, shown here for manual debugging)

```bash
docker build -t ots-django-app:10 .        # build an image from the Dockerfile in the current dir
docker images                                # list images already on this machine
docker ps                                     # list currently running containers
docker save ots-django-app:10 | sudo k3s ctr images import -   # load a built image straight into k3s, no registry
```

## kubectl — inspecting and controlling the Kubernetes cluster

```bash
export KUBECONFIG=/home/ubuntu/.kube/config   # already set in .bashrc, shown here for clarity

kubectl get nodes                              # is the cluster itself healthy?
kubectl get pods -A                            # every pod, every namespace
kubectl get pods -n ots                        # just the app's namespace
kubectl get pods -n monitoring

kubectl describe pod -n ots <pod-name>         # deep diagnostic info + recent events -- start here when something's broken
kubectl logs -n ots deploy/ots-django-app      # what the app actually printed
kubectl logs -n ots deploy/ots-django-app --previous   # logs from the PREVIOUS crashed instance of a restarting pod

kubectl exec -n ots deploy/ots-django-app -- bash                    # get a shell inside the running container
kubectl exec -n ots deploy/ots-django-app -- python manage.py shell -c "..."   # run a one-off Django command

kubectl delete pod -n ots -l app=ots-django-app   # force-kill the pod (Kubernetes immediately starts a replacement) -- how we tested that data survives a restart
kubectl rollout restart deployment ots-django-app -n ots   # cleaner way to force a fresh pod
kubectl rollout status deployment ots-django-app -n ots    # wait and watch a rollout finish

kubectl get svc -n ots            # Services (stable internal addresses)
kubectl get ingress -n ots        # Ingress rules (external routing)
kubectl get certificate -n ots    # has cert-manager actually issued the TLS cert?

# One-time setup (not something you re-run casually):
kubectl create namespace ots
kubectl create secret generic django-secret -n ots \
    --from-literal=DJANGO_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')" \
    --from-literal=DJANGO_DEBUG=False \
    --from-literal=DJANGO_ALLOWED_HOSTS="*"
```

## Helm — deploying and inspecting releases

```bash
helm list -A                              # every release, every namespace, and its status
helm list -n ots
helm status ots-django-app -n ots         # detailed info on one release

helm lint helm/ots-django-app             # check the chart for mistakes before deploying
helm template helm/ots-django-app --set image.tag=42   # render to plain YAML WITHOUT installing -- great for checking templates

helm upgrade --install ots-django-app helm/ots-django-app \
    -n ots --create-namespace \
    --set image.repository=ots-django-app \
    --set image.tag=10 \
    --rollback-on-failure --wait --timeout 5m

helm rollback ots-django-app 3 -n ots     # manually go back to a specific earlier revision
helm uninstall ots-django-app -n ots      # remove a release entirely (used once to clear a "stuck" release -- see doc 6)
```

## Verifying things actually work (not just "looks configured")

```bash
# Is the app actually responding?
curl -s -o /dev/null -w "HTTP %{http_code}\n" https://13.203.126.12.nip.io/OTS/

# Is the TLS certificate real and trusted (not self-signed)?
curl -v https://13.203.126.12.nip.io/ 2>&1 | grep -E "subject:|issuer:|SSL certificate verify"

# Is your current IP still what the firewall rule expects?
curl -s https://checkip.amazonaws.com
```

## Git — the app repo, on the EC2 box

```bash
# One-time: generate a repo-scoped deploy key so the server can push
# without ever using your personal GitHub credentials
ssh-keygen -t ed25519 -C "ec2-ots-devops" -f ~/.ssh/github_deploy -N ""
# -> add the PUBLIC half (github_deploy.pub) as a GitHub Deploy Key with write access

git status
git add <files>
git commit -m "..."
git push
```
