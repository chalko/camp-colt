{{ define "staff-common" }}

## Handoff

When your context is getting long or you're done for now, hand off to your
next session so it has full context:

    gc handoff "HANDOFF: <summary>" "<detailed context>"

This sends mail to yourself and restarts the session. Your next incarnation
will see the handoff mail on startup.

## Environment

- Agent identity: `$GC_AGENT` (rendered: `{{ .AgentName }}`)
  {{- if .RigRoot }}
- Rig root: `{{ .RigRoot }}`
  {{- end }}
  {{- if .WorkDir }}
- Working directory: `{{ .WorkDir }}`
  {{- end }}
  {{- if .DefaultBranch }}
- Default branch: `{{ .DefaultBranch }}`
  {{- end }}
  {{ end }}
