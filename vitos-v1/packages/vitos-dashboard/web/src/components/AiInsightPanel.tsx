import { useSSE } from "../lib/sse";
import type { Alert } from "../lib/api";

interface Props {
  studentId: string | null;
}

export default function AiInsightPanel({ studentId }: Props) {
  const alerts = useSSE<Alert>("/api/stream/alerts");
  const filtered = studentId ? alerts.filter((a) => a.student_id === studentId) : alerts;
  const recent = filtered.slice(-5).reverse();

  return (
    <section style={{
      borderTop: "1px solid #1a1f4a",
      padding: "1rem 1.5rem",
      maxHeight: 220,
      overflowY: "auto",
      backgroundColor: "#0a0e2a",
    }}>
      <h4 style={{ marginTop: 0, color: "#7dd3fc" }}>AI Insight</h4>
      {recent.length === 0 && (
        <p style={{ opacity: 0.5, fontSize: "0.85rem" }}>(no alerts yet — engine learning baseline)</p>
      )}
      {recent.map((a, i) => (
        <div key={i} style={{
          padding: "0.5rem 0.75rem",
          marginBottom: 6,
          borderLeft: `3px solid ${a.category === "Critical" ? "#e94560" : "#facc15"}`,
          backgroundColor: "#11163a",
          fontSize: "0.85rem",
        }}>
          <div style={{ opacity: 0.6, fontSize: "0.75rem" }}>{a.ts} — {a.student_id}</div>
          <div>
            <strong style={{ color: a.category === "Critical" ? "#e94560" : "#facc15" }}>
              {a.category}
            </strong> {a.score}%{" "}
            {a.intent_label && a.intent_label !== "UNKNOWN" && (
              <span style={{ opacity: 0.7 }}>· {a.intent_label} ({(Number(a.intent_confidence) * 100).toFixed(0)}%)</span>
            )}
          </div>
          {a.ai_reason && (
            <div style={{ marginTop: 4, fontStyle: "italic", opacity: 0.85 }}>
              {a.ai_reason}
            </div>
          )}
        </div>
      ))}
    </section>
  );
}
