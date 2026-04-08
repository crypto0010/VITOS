export default function About() {
  return (
    <div style={{ maxWidth: 760, lineHeight: 1.6 }}>
      <h2 style={{ color: "#7dd3fc" }}>About VITOS</h2>
      <p>
        <strong>VITOS</strong> (VIT Operating System for Cybersecurity) is a Kali-based
        academic security distribution designed and developed at the
        {" "}<strong>Cybersecurity and Digital Forensics Lab, VIT Bhopal University</strong>.
        It pairs the standard Kali pentesting toolchain with a behavioral-monitoring
        AI engine, a sandboxed per-student execution model, and a faculty admin console.
      </p>

      <h3 style={{ color: "#facc15" }}>Project leadership</h3>
      <ul>
        <li><strong>Project Director:</strong> Dr. Hemraj Shobharam Lamkuche &mdash; Senior Assistant Professor (Employee ID 100541)</li>
        <li><strong>Chief Mentor:</strong> Pon Harshavardhanan</li>
      </ul>

      <h3 style={{ color: "#facc15" }}>Contributing team</h3>
      <ol style={{ columns: 2, columnGap: "2rem" }}>
        <li>Matrupriya Dibyanshu Panda</li>
        <li>Spandan Gope</li>
        <li>Bharat Raghuvanshi</li>
        <li>Mayank Singh Bhadouria</li>
        <li>Advait Sahu</li>
        <li>Aayushman Arora</li>
        <li>Harsh Singh</li>
        <li>Satyanarayana Murthy V</li>
        <li>Ravi Shankar</li>
        <li>Agnibha</li>
        <li>Leonardo</li>
        <li>Mannat Pal</li>
        <li>Ambika</li>
        <li>Rashmi</li>
        <li>Nahal</li>
        <li>Piyush</li>
        <li>Krishno</li>
      </ol>

      <h3 style={{ color: "#facc15" }}>Contact</h3>
      <p>
        <a href="mailto:vitbhopal.os@gmail.com" style={{ color: "#7dd3fc" }}>
          vitbhopal.os@gmail.com
        </a>
      </p>

      <h3 style={{ color: "#facc15" }}>Citation</h3>
      <pre style={{
        backgroundColor: "#11163a",
        padding: "1rem",
        borderRadius: 4,
        whiteSpace: "pre-wrap",
        fontSize: "0.85rem",
      }}>
{`Lamkuche, H. S., Harshavardhanan, P., et al.
VITOS — VIT Cybersecurity Lab Operating System.
Cybersecurity and Digital Forensics Lab,
VIT Bhopal University, 2026.
https://github.com/crypto0010/VITOS`}
      </pre>
    </div>
  );
}
