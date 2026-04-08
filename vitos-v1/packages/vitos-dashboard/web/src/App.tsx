import { Routes, Route, Link, NavLink } from "react-router-dom";
import Console from "./pages/Console";
import Login from "./pages/Login";
import Network from "./pages/Network";
import Process from "./pages/Process";
import Reports from "./pages/Reports";
import Scopes from "./pages/Scopes";
import Audit from "./pages/Audit";
import About from "./pages/About";

const navStyle = ({ isActive }: { isActive: boolean }): React.CSSProperties => ({
  color: isActive ? "#facc15" : "#7dd3fc",
  marginRight: "1rem",
  textDecoration: "none",
  fontWeight: isActive ? 700 : 400,
});

export default function App() {
  return (
    <div style={{
      fontFamily: "system-ui, sans-serif",
      backgroundColor: "#0a0e2a",
      color: "#fff",
      minHeight: "100vh",
      margin: 0,
    }}>
      <header style={{ padding: "0.75rem 2rem", borderBottom: "1px solid #1a1f4a" }}>
        <h1 style={{ margin: 0, fontSize: "1.4rem" }}>
          VITOS Admin Console <span style={{ opacity: 0.5, fontSize: "0.85rem" }}>[VIT Bhopal Lab 3]</span>
        </h1>
        <p style={{ margin: "0.15rem 0 0", fontSize: "0.72rem", opacity: 0.55 }}>
          Cybersecurity and Digital Forensics Lab · VIT Bhopal University ·
          Dr. Hemraj Shobharam Lamkuche (Project Director) ·
          Dr. Pon Harshavardhanan (Chief Mentor) ·
          Dr. Saravanan D. (Division Head)
        </p>
        <nav style={{ marginTop: "0.5rem" }}>
          <NavLink to="/"        style={navStyle} end>Console</NavLink>
          <NavLink to="/network" style={navStyle}>Network</NavLink>
          <NavLink to="/process" style={navStyle}>Process</NavLink>
          <NavLink to="/reports" style={navStyle}>Reports</NavLink>
          <NavLink to="/scopes"  style={navStyle}>Scopes</NavLink>
          <NavLink to="/audit"   style={navStyle}>Audit</NavLink>
          <NavLink to="/about"   style={navStyle}>About</NavLink>
          <Link to="/login" style={{ color: "#94a3b8", marginLeft: "1rem" }}>Sign in</Link>
        </nav>
      </header>
      <Routes>
        <Route path="/"        element={<Console />} />
        <Route path="/network" element={<PagePadding><Network /></PagePadding>} />
        <Route path="/process" element={<PagePadding><Process /></PagePadding>} />
        <Route path="/reports" element={<PagePadding><Reports /></PagePadding>} />
        <Route path="/scopes"  element={<PagePadding><Scopes /></PagePadding>} />
        <Route path="/audit"   element={<PagePadding><Audit /></PagePadding>} />
        <Route path="/about"   element={<PagePadding><About /></PagePadding>} />
        <Route path="/login"   element={<PagePadding><Login /></PagePadding>} />
      </Routes>
      <footer style={{
        padding: "0.5rem 2rem",
        borderTop: "1px solid #1a1f4a",
        fontSize: "0.7rem",
        opacity: 0.45,
        textAlign: "center",
      }}>
        VITOS · Cybersecurity and Digital Forensics Lab, VIT Bhopal University
        · Contact: vitbhopal.os@gmail.com
      </footer>
    </div>
  );
}

function PagePadding({ children }: { children: React.ReactNode }) {
  return <main style={{ padding: "1.5rem 2rem" }}>{children}</main>;
}
