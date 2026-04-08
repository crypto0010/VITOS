import { useEffect, useState } from "react";
import { tailAudit } from "../lib/api";

export default function Audit() {
  const [rows, setRows] = useState<Array<Record<string, unknown>>>([]);

  useEffect(() => {
    let cancelled = false;
    async function tick() {
      try {
        const r = await tailAudit();
        if (!cancelled) setRows(r);
      } catch {/* ignore */}
    }
    tick();
    const t = setInterval(tick, 5000);
    return () => { cancelled = true; clearInterval(t); };
  }, []);

  return (
    <div>
      <h2>Admin Audit Log</h2>
      <p style={{ opacity: 0.6 }}>{rows.length} entries shown.</p>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "0.85rem" }}>
        <thead>
          <tr style={{ borderBottom: "1px solid #1a1f4a", textAlign: "left" }}>
            <th style={{ padding: "0.5rem" }}>Time</th>
            <th style={{ padding: "0.5rem" }}>Admin</th>
            <th style={{ padding: "0.5rem" }}>Action</th>
            <th style={{ padding: "0.5rem" }}>Target</th>
            <th style={{ padding: "0.5rem" }}>Result</th>
          </tr>
        </thead>
        <tbody>
          {rows.slice().reverse().map((r, i) => (
            <tr key={i} style={{ borderBottom: "1px solid #11163a" }}>
              <td style={{ padding: "0.5rem", fontFamily: "monospace" }}>{String(r.ts)}</td>
              <td style={{ padding: "0.5rem" }}>{String(r.admin)}</td>
              <td style={{ padding: "0.5rem" }}>{String(r.action)}</td>
              <td style={{ padding: "0.5rem", fontFamily: "monospace" }}>{String(r.target)}</td>
              <td style={{ padding: "0.5rem" }}>{String(r.result)}</td>
            </tr>
          ))}
          {rows.length === 0 && (
            <tr><td colSpan={5} style={{ padding: "1rem", opacity: 0.5 }}>(no audit entries)</td></tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
