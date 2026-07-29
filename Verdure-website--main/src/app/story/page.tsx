import type { Metadata } from "next";
import PageShell from "@/components/layout/PageShell";
import JsonLd from "@/components/seo/JsonLd";
import { breadcrumbLd, pageMetadata } from "@/lib/seo";
import StoryContent from "./StoryContent";

export const metadata: Metadata = pageMetadata({
  title: "Our Story — Why Verdure Exists",
  description:
    "Why Verdure exists: the spaces around us deserve people in them, and going outside should be the easy option. Here is the thinking behind the app.",
  path: "/story",
});

export default function StoryPage()
{
  return (
    <PageShell>
      <JsonLd
        data={breadcrumbLd([
          { name: "Verdure", path: "/" },
          { name: "Our Story", path: "/story" },
        ])}
      />
      <StoryContent />
    </PageShell>
  );
}
