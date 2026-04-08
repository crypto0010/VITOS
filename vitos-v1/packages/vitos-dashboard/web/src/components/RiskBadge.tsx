interface Props {
  score: number;
  category: string;
}

const COLORS: Record<string, string> = {
  Normal:     "#16c79a",
  Suspicious: "#facc15",
  Warning:    "#fb923c",
  Critical:   "#e94560",
};

export default function RiskBadge({ score, category }: Props) {
  const color = COLORS[category] ?? "#888";
  return (
    <span style={{
      display: "inline-block",
      padding: "0.15rem 0.55rem",
      borderRadius: 999,
      backgroundColor: color,
      color: "#0a0e2a",
      fontWeight: 700,
      fontSize: "0.8rem",
      minWidth: 38,
      textAlign: "center",
    }}>
      {score}
    </span>
  );
}
