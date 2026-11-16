import { C, sans } from "./lib/theme";
import { EarlyAccessProvider } from "./components/EarlyAccess";
import { Hero } from "./components/Hero";
import { Demo } from "./components/Demo";
import { Modes } from "./components/Modes";
import { Voice } from "./components/Voice";
import { UseCases } from "./components/UseCases";
import { Capabilities } from "./components/Capabilities";
import { Control } from "./components/Control";
import { CTA } from "./components/CTA";
import { Footer } from "./components/Footer";

export default function App() {
  return (
    <EarlyAccessProvider>
      <div
        style={{
          width: "100%",
          background: C.bg,
          color: C.ink,
          fontFamily: sans,
          overflowX: "hidden",
          padding: "0 24px",
        }}
      >
        <div
          style={{
            maxWidth: 1240,
            margin: "0 auto",
            borderLeft: `1px solid ${C.faint}`,
            borderRight: `1px solid ${C.faint}`,
          }}
        >
          <Hero />
          <Demo />
          <Modes />
          <Voice />
          <UseCases />
          <Capabilities />
          <Control />
          <CTA />
          <Footer />
        </div>
      </div>
    </EarlyAccessProvider>
  );
}
