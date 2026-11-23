import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://leonida-heperkoo.meshedgoby9.chatgpt.site"),
  title: "Leonida / Heperkoo — Native Runtime Workbench",
  description: "Heperkoo's experimental Leonida fork. Native GTA VI PC runtime research, a local experiment workbench, source activity, and developer handoffs. Gameplay remains unverified in this fork.",
  openGraph: {
    title: "Leonida / Heperkoo — One real frame",
    description: "An independent native runtime lab. Open source, documented experiments, a contributor workbench, and ongoing collaboration.",
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
