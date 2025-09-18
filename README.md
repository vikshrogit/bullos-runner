# BullOS GitHub Self-Hosted Runner

Welcome to **BullOS GitHub Self-Hosted Runner**, a robust, secure, and scalable solution for running GitHub Actions workflows on your own infrastructure. This repository provides everything you need to deploy multi-architecture (amd64 and arm64) GitHub runners inside Docker containers, complete with automation, security best practices, and production-grade deployment guidelines.

---

## 🚀 Overview

GitHub Actions is a powerful CI/CD platform, but GitHub-hosted runners can be limited in flexibility, performance, and control. BullOS GitHub Runner solves this problem by giving you **self-hosted runners** that:

- Run inside Docker containers for isolation and reproducibility.
- Support **multi-architecture builds** (`amd64` and `arm64`).
- Auto-register with your GitHub repository or organization.
- Scale horizontally to handle concurrent workloads.
- Integrate seamlessly with GitHub Actions workflows.
- Provide enhanced security with controlled execution environments.

By running BullOS runners on your own servers, you can reduce costs, improve performance, and maintain full control over your workflows.

---

## ✨ Features

- **Multi-Arch Support**: Build and deploy runners for both `linux/amd64` and `linux/arm64`.
- **Ephemeral Runners**: Optionally enable short-lived runners that self-destruct after jobs finish.
- **Docker-Compose Ready**: Easy setup with `.env` configuration.
- **Secure by Default**: Runs with limited permissions, integrates with Trivy for vulnerability scanning.
- **Scalable**: Deploy multiple containers across servers for concurrency.
- **Customizable**: Configure runner groups, labels, work directories, and debug options.
- **CI/CD Friendly**: Build, scan, and push images via GitHub Actions.

---

## 🏗️ Architecture

At a high level, BullOS Runner works like this:

1. The container launches and pulls the latest version of the GitHub Actions runner binary.
2. It registers itself with your GitHub repository or organization using a token.
3. The runner listens for jobs from GitHub Actions.
4. Jobs are executed inside the container environment.
5. When configured as **ephemeral**, the runner automatically de-registers and cleans up after completion.

The architecture ensures **isolation**, **clean builds**, and **repeatability**.

---

## ⚙️ Installation

### 1. Clone Repository
```bash
git clone https://github.com/vikshrogit/bullos-runner.git
cd bullos-runner
````

### 2. Create `.env` File

```env
GITHUB_URL=https://github.com/vikshrogit
RUNNER_TOKEN=your-github-token-here
RUNNER_NAME=bullos-runner-01
RUNNER_LABELS=self-hosted,linux,bullos
RUNNER_WORKDIR=_work
RUNNER_EPHEMERAL=false
RUNNER_RUNNERGROUP=Default
RUNNER_DEBUG=true
RUNNER_CONCURRENCY=4
```

### 3. Run with Docker Compose

```bash
docker compose up -d
```

### 4. Verify Runner Registration

Go to your GitHub repository or organization:

* **Settings → Actions → Runners**
  You should see `bullos-runner-01` listed.

---

## 🐳 Docker Images

The official container image is hosted at:

```
ghcr.io/vikshrogit/bullos-gh-runner:latest
```

You can pull it directly:

```bash
docker pull ghcr.io/vikshrogit/bullos-gh-runner:latest
```

---

## 🔧 Configuration Options

| Variable             | Description                                           |
| -------------------- | ----------------------------------------------------- |
| `GITHUB_URL`         | The GitHub repository or organization URL.            |
| `RUNNER_TOKEN`       | Registration token (from GitHub settings).            |
| `RUNNER_NAME`        | Friendly name for the runner.                         |
| `RUNNER_LABELS`      | Comma-separated labels for targeting jobs.            |
| `RUNNER_WORKDIR`     | Directory where jobs execute.                         |
| `RUNNER_EPHEMERAL`   | `true` or `false`. Ephemeral runners exit after jobs. |
| `RUNNER_RUNNERGROUP` | Runner group name.                                    |
| `RUNNER_DEBUG`       | Enable verbose logging.                               |
| `RUNNER_CONCURRENCY` | Number of jobs the runner can handle concurrently.    |

---

## 🔐 Security Best Practices

1. Always keep your Docker image updated with the latest version.
2. Use **ephemeral runners** for untrusted workflows.
3. Regularly scan images with **Trivy**:

   ```bash
   trivy image ghcr.io/vikshrogit/bullos-gh-runner:latest
   ```
4. Run containers with limited privileges (`--security-opt no-new-privileges`).
5. Rotate your `RUNNER_TOKEN` periodically.
6. Use dedicated infrastructure for sensitive workflows.

---

## 🛡️ Trivy Integration

BullOS Runner integrates with **Trivy** in CI/CD pipelines:

* **Vulnerability scanning** (OS packages, dependencies).
* **Secret scanning** (to avoid committing secrets).
* Configurable exit codes (`--exit-code 1` on critical findings).

---

## 🧩 Advanced Usage

### Multi-Runner Deployment

You can run multiple runners by scaling with Docker Compose:

```bash
docker compose up --scale runner=3 -d
```

### Ephemeral Mode

Set in `.env`:

```env
RUNNER_EPHEMERAL=true
```

This ensures clean, isolated runners for every workflow.

### Custom Labels

```env
RUNNER_LABELS=self-hosted,linux,build,deploy
```

Target specific jobs with these labels.

---

## 🛠️ Development

To build locally:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t bullos-runner:test .
```

Run locally:

```bash
docker run --rm -it bullos-runner:test bash
```

---

## ❓ Troubleshooting

* **Runner not appearing in GitHub**
  → Check if the `RUNNER_TOKEN` is valid. Tokens expire quickly.
* **Image fails to build**
  → Make sure you’re using `docker buildx` with experimental features enabled.
* **Architecture mismatch**
  → Ensure you specify `--platform linux/amd64,linux/arm64` for multi-arch builds.
* **Trivy OOM errors**
  → Use `--scanners vuln` to disable secret scanning.

---

## 📚 FAQ

**Q: Why use BullOS runner instead of GitHub-hosted runners?**
A: Control, cost efficiency, custom environments, and support for private infrastructure.

**Q: Can I use this in Kubernetes?**
A: Yes! Wrap the container into a `Deployment` or `DaemonSet` for cluster-wide runners.

**Q: Is it secure to run untrusted workflows?**
A: Use **ephemeral mode** + restricted nodes for maximum safety.

**Q: How often are images updated?**
A: Images are built automatically on new GitHub runner releases.

---

## 🤝 Contributing

Contributions are welcome!

1. Fork the repository.
2. Create a new branch.
3. Make your changes.
4. Submit a Pull Request.

We follow our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 📜 License

This project is licensed under the terms of the [Apache License 2.0](LICENSE.md).

---

## 📈 Roadmap

* [ ] Add Kubernetes Helm Chart support
* [ ] Enhanced monitoring with Prometheus/Grafana
* [ ] Auto-scaling runner pools
* [ ] Support for Windows-based runners

---

## 🌍 Community

* **Discussions**: [GitHub Discussions](https://github.com/vikshrogit/bullos-runner/discussions)
* **Issues**: [Issue Tracker](https://github.com/vikshrogit/bullos-runner/issues)

Join us to make CI/CD faster, more secure, and fully under your control!
