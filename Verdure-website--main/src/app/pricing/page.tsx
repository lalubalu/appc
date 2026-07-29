import type { Metadata } from "next";
import PageShell from "@/components/layout/PageShell";
import JsonLd from "@/components/seo/JsonLd";
import { breadcrumbLd, pageMetadata, pricingLd } from "@/lib/seo";
import PricingContent from "./PricingContent";

export const metadata: Metadata = pageMetadata({
  title: "Pricing — Free and Verdure+ Plans",
  description:
    "Verdure Free costs nothing, forever. Verdure+ ($4.99/mo or $39.99/yr) adds the AI Adventure Planner, AR exploration, offline maps, and higher-value rewards.",
  path: "/pricing",
});

export default function PricingPage()
{
  return (
    <PageShell>
      {/* Prices come from lib/plans.ts, the single owner-supplied source —
          the markup never restates a number of its own. */}
      <JsonLd data={pricingLd()} />
      <JsonLd
        data={breadcrumbLd([
          { name: "Verdure", path: "/" },
          { name: "Pricing", path: "/pricing" },
        ])}
      />
      <PricingContent />
    </PageShell>
  );
}
