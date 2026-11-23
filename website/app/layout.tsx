import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://leonida-heperkoo.meshedgoby9.chatgpt.site"),
  title: "Leonida / Heperkoo — Native Runtime Workbench",
  description: "Heperkoo's experimental Leonida fork. Native GTA VI PC runtime research, a local experiment workbench, source activity, and developer handoffs. Gameplay remains unverified in this fork.",
  openGraph: {
    title: "Leonida / Heperkoo — Boot progress and world rendering",
    description: "Boot screens, video and saves reported working on one Windows 11 / RX 9070 XT machine. Follow the progress showcase and ongoing world-rendering investigation.",
    type: "website",
    url: "https://leonida-heperkoo.meshedgoby9.chatgpt.site",
    siteName: "Leonida / Heperkoo",
  },
  twitter: { card: "summary", title: "Leonida / Heperkoo", description: "Native PC runtime research. Real experiments. A useful next handoff." },
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
