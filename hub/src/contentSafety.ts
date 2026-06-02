import type { BusMessage, ControlEvent, RoleAssignment, Roles } from "./types.js";

const SECRET_PATTERNS: RegExp[] = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\bsk-[A-Za-z0-9_-]{16,}\b/,
  /\bgh[pousr]_[A-Za-z0-9_]{16,}\b/,
  /\bxox[baprs]-[A-Za-z0-9-]{16,}\b/,
  /\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)\s*[:=]\s*["']?[A-Za-z0-9_./+=-]{12,}/i,
];

const CODE_LINE_PATTERN =
  /^\s*(?:import|export|const|let|var|function|class|interface|type|enum|if|for|while|switch|return|guard|struct)\b|[{};]\s*$/;

export function assertSafeCoordinationMessage(message: string): void {
  assertSafeCoordinationText(message, "Message");
}

export function assertSafeRoleAssignment(label: string, assignment: RoleAssignment): void {
  assertSafeCoordinationText(assignment.role, `${label} role`);
  assertSafeCoordinationText(assignment.task, `${label} task`);
}

export function assertSafeCoordinationText(value: string, label: string): void {
  if (/```/.test(value)) {
    throw new Error(`${label} appears to contain a code block. Send file paths and a natural-language summary only.`);
  }
  if (SECRET_PATTERNS.some((pattern) => pattern.test(value))) {
    throw new Error(`${label} appears to contain a secret. Do not send secrets or private data through Duet.`);
  }

  const codeLikeLines = value
    .split(/\r?\n/)
    .filter((line) => CODE_LINE_PATTERN.test(line) || /^\s{2,}\S.*(?:=>|=|\(|\))/.test(line));
  if (codeLikeLines.length >= 3) {
    throw new Error(`${label} appears to contain source code. Send file paths and a natural-language summary only.`);
  }
}

export function redactSensitiveText(value: string): string {
  return SECRET_PATTERNS.reduce((text, pattern) => text.replace(globalPattern(pattern), "[redacted]"), value);
}

export function redactControlEvent(event: ControlEvent): ControlEvent {
  switch (event.type) {
    case "message":
      return { type: "message", message: redactMessage(event.message) };
    case "rolesUpdated":
      return { type: "rolesUpdated", roles: redactRoles(event.roles) };
    case "snapshot":
      return {
        type: "snapshot",
        snapshot: {
          ...event.snapshot,
          repoPath: redactPath(event.snapshot.repoPath),
          roles: redactRoles(event.snapshot.roles),
          transcript: event.snapshot.transcript.map(redactMessage),
        },
      };
    case "error":
      return { type: "error", message: redactSensitiveText(event.message) };
    case "status":
      return event;
    case "stall":
      return event;
  }
}

function redactMessage(message: BusMessage): BusMessage {
  return {
    ...message,
    message: `[redacted:${message.message.length}]`,
  };
}

function redactRoles(roles: Roles): Roles {
  return {
    claude: { role: redactSensitiveText(roles.claude.role), task: `[redacted:${roles.claude.task.length}]` },
    codex: { role: redactSensitiveText(roles.codex.role), task: `[redacted:${roles.codex.task.length}]` },
  };
}

function redactPath(value: string): string {
  const home = process.env.HOME;
  return home && value.startsWith(home) ? `~${value.slice(home.length)}` : value;
}

function globalPattern(pattern: RegExp): RegExp {
  return new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`);
}
