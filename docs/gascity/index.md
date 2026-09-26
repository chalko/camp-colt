# Gas City Infrastructure & Supervisor Operations

## Architecture & Supervision Model

Gas City runs an active supervisor daemon (`gc supervisor`) to manage session processes, background agents, bead databases, and rig dispatch routing.

### Finding: Systemd User Instance Warning

During city startup (`gc start` / initialization), the following warning is observed:

```text
gc supervisor install: per-user systemd instance is not available (systemctl --user could not reach the user manager).
Either enable lingering for this account ('sudo loginctl enable-linger camp-colt-mayor-agent'),
log in via a PAM session that starts user-systemd, or run the supervisor detached (e.g. 'gc supervisor start' without service install).
Supervisor started (PID <pid>)
```

#### Cause

The host environment does not maintain an active systemd user session bus (`systemctl --user`) for `camp-colt-mayor-agent`, as linger is not enabled and the session is not spawned through a PAM systemd login session.

### Decision: Detached Process Mode (Option 2)

**Decision Date:** 2026-09-21
**Status:** Accepted

We intentionally run the Gas City supervisor in **detached process mode** (`gc supervisor start` without systemd service installation) rather than enabling systemd lingering (`sudo loginctl enable-linger`).

### Rationale

1. **Camp Colt Security Principles:**
   Camp Colt operates under strict security posture:

   > _Zero standing root access; all agent tasks execute under unprivileged POSIX identities._

   Enabling lingering requires privileged (`sudo`) elevation on the host system. Operating in detached mode adheres to unprivileged execution boundaries.

2. **Environment Portability:**
   Detached execution works identically across bare metal, unprivileged containers, and headless agent sandboxes without requiring host-level init system integration.

3. **Autonomous Supervisor Recovery:**
   `gc` automatically checks and restarts the detached supervisor process as needed when executing CLI commands.

### Operational Runbook

#### Checking Status

```bash
gc status
gc supervisor status
```

#### Starting Supervisor (Detached)

```bash
gc supervisor start
```

#### Stopping Supervisor

```bash
gc supervisor stop
```

#### Logs & Diagnostics

Supervisor logs and runtime sockets reside in `.gc/`:

```bash
ls -la .gc/
```
