# DevBox CLI

A lightweight CLI to create and manage an isolated Git development environment using **Podman**.

With DevBox CLI, you can keep your **personal Git identity** completely separate from your **work/company Git configuration**, while continuing to develop on your host machine.

---

### Why this project?

Many developers have their **company Git account** configured on their host machine.

For example:

- Company GitHub account
- Company SSH keys
- Company email
- Company username

When working on personal or open-source projects, switching Git identities repeatedly can be inconvenient and error-prone.

A small mistake can result in:

- Pushing personal code to a company account
- Using the wrong email in commits
- Mixing SSH keys between work and personal projects

This project solves that problem.

---

### The Idea

Instead of changing Git configurations on your host machine, create a dedicated Podman container that contains:

- Personal Git configuration
- Personal SSH keys
- Personal GitHub account

Your host machine remains untouched.

You continue editing code on your host, while Git operations happen inside the container.

---

### How it Works

```
               Host Machine

        +------------------------+
        |                        |
        |  VS Code / Vim / IDE   |
        |                        |
        |   Edit Source Code     |
        +-----------+------------+
                    |
                    |
            Mounted Volume
                    |
                    ▼
        +------------------------+
        |    Podman Container    |
        |                        |
        | Git                    |
        | SSH                    |
        | Personal Git Config    |
        | Personal SSH Key       |
        +-----------+------------+
                    |
                    |
             Push to GitHub
                    |
                    ▼
          Personal GitHub Account
```

The project directory is mounted into the container.

This means:

- Edit files on your host machine
- Commit from inside the container
- Push using your personal GitHub account

No changes are required to your host Git configuration.

---

### Features

- Lightweight Ubuntu container
- Automatic Git installation
- Automatic SSH setup
- Personal Git configuration
- SSH key generation
- GitHub SSH authentication check
- Start/Stop container with one command
- Opens directly in `/workspace`
- Keeps work and personal Git identities isolated

---
### Prerequisites

Before using this project, make sure you have the following installed:

- Remote repo
- **Podman** (required)
- Internet connection (for the initial Ubuntu image download and package installation)

---

### Commands

Create a new development container.

```bash
./devbox.sh install personal-git
```

Start the container.

```bash
./devbox.sh start personal-git
```

Check container and GitHub status.

```bash
./devbox.sh status personal-git
```

Stop the container.

```bash
./devbox.sh stop personal-git
```

Remove the container.

```bash
./devbox.sh remove personal-git
```
---

### Typical Workflow

```text
Edit code on Host
        │
        ▼
Start Container
        │
        ▼
Git Add
Git Commit
Git Push
        │
        ▼
Personal GitHub Repository
```

---

#### Example

Your host machine:

```
Company Git Account
company@example.com
```

Container:

```
Personal Git Account
nandha@gmail.com
```

Both environments remain completely independent.



---

### License

MIT