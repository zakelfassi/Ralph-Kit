# GCP Runner (Forgeloop-equipped VM)

This folder contains a simple GCP flow to get a **Forgeloop-equipped VM** that can run loops in full-auto mode.

## Quick start

From the `forgeloop` repo root:

```bash
OPENAI_API_KEY=... ANTHROPIC_API_KEY=... \
  ops/gcp/provision.sh --name forgeloop-runner --project <gcp-project> --zone us-central1-a
```

This will:
- Create a new Ubuntu VM
- Upload `forgeloop` to the VM and install it at `/opt/forgeloop`
- Install Node.js + pnpm + base tooling
- Install `codex` + `claude` CLIs (best-effort)
- Store keys at `/etc/forgeloop/keys.env` (mode 600) and load them via `/etc/profile.d/forgeloop-env.sh`

## After provisioning

SSH in:

```bash
gcloud compute ssh forgeloop-runner --project <gcp-project> --zone us-central1-a
```

Then clone your target repo and install the kit:

```bash
mkdir -p ~/work && cd ~/work
git clone <your-repo-url> repo
/opt/forgeloop/install.sh ~/work/repo --wrapper

cd ~/work/repo
./forgeloop.sh plan 1
./forgeloop.sh build 10
```

## Security notes

- **Full-auto** is powerful and risky. Treat the VM as disposable.
- Use least-privilege keys and a dedicated GCP project.
- Prefer private repos + deploy keys over personal SSH keys.

## Troubleshooting

- If `codex` or `claude` didn’t install, install them manually on the VM.
- If Claude requires interactive auth, run `claude setup-token` on the VM.
