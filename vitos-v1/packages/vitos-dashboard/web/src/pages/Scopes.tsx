import { useEffect, useState } from "react";
import { listScopes } from "../lib/api";

export default function Scopes() {
  const [scopes, setScopes] = useState<string[]>([]);
  const [yaml, setYaml] = useState<string>("");
  const [msg, setMsg] = useState<string>("");

  useEffect(() => {
    listScopes().then(setScopes);
  }, []);

  async function activate() {
    const r = await fetch("/api/scopes/active", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "custom", yaml }),
    });
    setMsg(r.ok ? "activated" : `error ${r.status}`);
  }

  return (
    <div>
      <h2>Lab-Exercise Scopes</h2>
      <p style={{ opacity: 0.6 }}>Available manifests: {scopes.length === 0 ? "(none)" : scopes.join(", ")}</p>
      <textarea
        value={yaml}
        onChange={(e) => setYaml(e.target.value)}
        rows={16}
        placeholder={"exercise: Recon-101\nallowed_targets:\n  - 10.10.1.0/24\n..."}
        style={{
          width: "100%",
          fontFamily: "monospace",
          fontSize: "0.85rem",
          backgroundColor: "#11163a",
          color: "#e2e8f0",
          border: "1px solid #1a1f4a",
          padding: "0.75rem",
        }}
      />
      <div style={{ marginTop: "0.75rem", display: "flex", gap: "0.5rem", alignItems: "center" }}>
        <button onClick={activate} style={{
          padding: "0.5rem 1rem",
          backgroundColor: "#16c79a",
          color: "#0a0e2a",
          border: "none",
          borderRadius: 4,
          fontWeight: 600,
          cursor: "pointer",
        }}>Activate</button>
        {msg && <span style={{ opacity: 0.7 }}>{msg}</span>}
      </div>
    </div>
  );
}
