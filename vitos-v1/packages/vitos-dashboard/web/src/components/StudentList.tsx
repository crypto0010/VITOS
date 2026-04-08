import RiskBadge from "./RiskBadge";
import type { Student } from "../lib/api";

interface Props {
  students: Student[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}

export default function StudentList({ students, selectedId, onSelect }: Props) {
  return (
    <aside style={{
      width: 280,
      borderRight: "1px solid #1a1f4a",
      padding: "1rem",
      overflowY: "auto",
      height: "calc(100vh - 110px)",
    }}>
      <h3 style={{ marginTop: 0, color: "#7dd3fc" }}>
        Students Online <span style={{ opacity: 0.5 }}>{students.length}/30</span>
      </h3>
      {students.length === 0 && (
        <p style={{ opacity: 0.5, fontSize: "0.85rem" }}>(no active sessions)</p>
      )}
      <ul style={{ listStyle: "none", padding: 0, margin: 0 }}>
        {students.map((s) => {
          const sel = s.id === selectedId;
          return (
            <li
              key={s.id}
              onClick={() => onSelect(s.id)}
              style={{
                padding: "0.6rem 0.5rem",
                marginBottom: 4,
                borderRadius: 4,
                cursor: "pointer",
                backgroundColor: sel ? "#1a1f4a" : "transparent",
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
              }}
            >
              <span style={{ fontFamily: "monospace" }}>{s.id}</span>
              <RiskBadge score={s.risk} category={s.category} />
            </li>
          );
        })}
      </ul>
    </aside>
  );
}
