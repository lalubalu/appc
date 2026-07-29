import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/seo";

/**
 * /robots.txt — the file a crawler asks for before anything else. Until now
 * the site had none, which meant no crawler was ever told where the sitemap
 * lived, and the signed-in routes were open to be crawled.
 *
 * The disallow list is the set of pages that are already `robots: noindex` in
 * their own metadata. Both matter and neither replaces the other: noindex
 * keeps a page out of the index once it has been fetched, this keeps it from
 * being fetched at all and spends the crawl budget on the six pages that are
 * meant to rank.
 *
 * The preview and *.vercel.app copies of this same build are handled in
 * middleware with an X-Robots-Tag, because robots.txt is generated at build
 * time and cannot see which hostname is being asked.
 *
 * Nothing here may ever disallow public/google*.html. Those are the Search
 * Console ownership tokens; Google has to be able to fetch one to keep the
 * property verified, and blocking it is the standard way to lose access to
 * the very reports this file exists to feed. See README.md.
 */
export default function robots(): MetadataRoute.Robots
{
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: ["/account", "/login", "/signup", "/auth/"],
      },
    ],
    sitemap: SITE_URL + "/sitemap.xml",
    host: SITE_URL,
  };
}
