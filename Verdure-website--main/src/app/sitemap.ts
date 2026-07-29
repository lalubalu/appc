import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/seo";

/**
 * /sitemap.xml — every public route, absolute against the canonical host so
 * the vercel.app copies of this build still point a crawler home.
 *
 * The signed-in routes (/account, /login, /signup, /auth/*) are deliberately
 * absent: a sitemap is a list of pages you want indexed, and those are
 * noindex.
 *
 * lastModified is the build timestamp. That is honest for this site — the
 * pages are static and only change when a build ships — and it means a deploy
 * is what tells Google to come back and look.
 */

type ChangeFrequency = MetadataRoute.Sitemap[number]["changeFrequency"];

interface Route
{
  path: string;
  priority: number;
  changeFrequency: ChangeFrequency;
}

let ROUTES: Route[] = [
  { path: "/", priority: 1, changeFrequency: "weekly" },
  { path: "/pricing", priority: 0.9, changeFrequency: "monthly" },
  { path: "/roadmap", priority: 0.8, changeFrequency: "weekly" },
  { path: "/story", priority: 0.7, changeFrequency: "monthly" },
  { path: "/partnerships", priority: 0.7, changeFrequency: "monthly" },
  { path: "/privacy", priority: 0.3, changeFrequency: "yearly" },
];

let BUILT_AT = new Date();

export default function sitemap(): MetadataRoute.Sitemap
{
  return ROUTES.map(function (route)
  {
    return {
      url: absoluteUrl(route.path),
      lastModified: BUILT_AT,
      changeFrequency: route.changeFrequency,
      priority: route.priority,
    };
  });
}
