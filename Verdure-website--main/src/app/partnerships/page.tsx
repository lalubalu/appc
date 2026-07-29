import type { Metadata } from "next";
import PageShell from "@/components/layout/PageShell";
import JsonLd from "@/components/seo/JsonLd";
import { breadcrumbLd, pageMetadata } from "@/lib/seo";
import PartnershipsContent from "./PartnershipsContent";

export const metadata: Metadata = pageMetadata({
  title: "Partnerships — Bring Foot Traffic to Your Space",
  description:
    "Partner with Verdure: drive foot traffic to parks, libraries, and local spaces, access engagement analytics, and run branded challenges and reward programs.",
  path: "/partnerships",
});

export default function PartnershipsPage()
{
  return (
    <PageShell>
      <JsonLd
        data={breadcrumbLd([
          { name: "Verdure", path: "/" },
          { name: "Partnerships", path: "/partnerships" },
        ])}
      />
      <PartnershipsContent />
    </PageShell>
  );
}
