// Tiny typed fetch wrapper. Cookies travel automatically.

export interface Student {
  id: string;
  risk: number;
  category: "Normal" | "Suspicious" | "Warning" | "Critical" | string;
  ai_reason?: string;
}

export interface Alert {
  ts: string;
  student_id: string;
  session_id: string;
  category: string;
  score: number;
  ai_reason?: string;
  intent_label?: string;
  intent_confidence?: number;
  scope_breach?: boolean;
  trigger_event?: unknown;
}

export interface Event {
  ts: string;
  type: string;
  student_id: string;
  session_id: string;
  [key: string]: unknown;
}

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const r = await fetch(path, {
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    ...init,
  });
  if (!r.ok) {
    throw new Error(`${r.status} ${r.statusText}: ${await r.text()}`);
  }
  return (await r.json()) as T;
}

export const listStudents   = () => api<Student[]>("/api/students");
export const listSessions   = () => api<string[]>("/api/sessions");
export const freezeSession  = (id: string) => api(`/api/sessions/${id}/freeze`,  { method: "POST" });
export const isolateSession = (id: string) => api(`/api/sessions/${id}/isolate`, { method: "POST" });
export const releaseSession = (id: string) => api(`/api/sessions/${id}/release`, { method: "POST" });
export const listScopes     = () => api<string[]>("/api/scopes");
export const tailAudit      = () => api<Array<Record<string, unknown>>>("/api/audit");
