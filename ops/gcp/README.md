# GCP Runner (Ralph-equipped VM)

This folder contains a simple GCP flow to get a **Ralph-equipped VM** that can run loops in full-auto mode.

## Quick start

From the `ralph-kit` repo root:

```bash
OPENAI_API_KEY=... ANTHROPIC_API_KEY=... \
  ops/gcp/provision.sh --name ralph-runner --project <gcp-project> --zone us-central1-a
```

This will:
- Create a new Ubuntu VM
- Upload `ralph-kit` to the VM and install it at `/opt/ralph-kit`
- Install Node.js + pnpm + base tooling
- Install `codex` + `claude` CLIs (best-effort)
- Store keys at `/etc/ralph/keys.env` (mode 600) and load them via `/etc/profile.d/ralph-env.sh`

## After provisioning

SSH in:

```bash
gcloud compute ssh ralph-runner --project <gcp-project> --zone us-central1-a
```

Then clone your target repo and install the kit:

```bash
mkdir -p ~/work && cd ~/work
git clone <your-repo-url> repo
/opt/ralph-kit/install.sh ~/work/repo --wrapper

cd ~/work/repo
./ralph.sh plan 1
./ralph.sh build 10
```

## Security notes

- **Full-auto** is powerful and risky. Treat the VM as disposable.
- Use least-privilege keys and a dedicated GCP project.
- Prefer private repos + deploy keys over personal SSH keys.

## Troubleshooting

- If `codex` or `claude` didn’t install, install them manually on the VM.
- If Claude requires interactive auth, run `claude setup-token` on the VM.
