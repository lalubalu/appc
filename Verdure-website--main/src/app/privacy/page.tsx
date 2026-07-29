import type { Metadata } from "next";
import PageShell from "@/components/layout/PageShell";
import JsonLd from "@/components/seo/JsonLd";
import { breadcrumbLd, pageMetadata } from "@/lib/seo";
import PrivacyContent from "./PrivacyContent";

export const metadata: Metadata = pageMetadata({
  title: "Privacy Policy",
  description:
    "How Verdure collects, uses, and protects your information — what we store, who we share it with, how long we keep it, and how to delete your account.",
  path: "/privacy",
});

export default function PrivacyPage()
{
  return (
    <PageShell>
      <JsonLd
        data={breadcrumbLd([
          { name: "Verdure", path: "/" },
          { name: "Privacy Policy", path: "/privacy" },
        ])}
      />
      <PrivacyContent />
    </PageShell>
  );
}
