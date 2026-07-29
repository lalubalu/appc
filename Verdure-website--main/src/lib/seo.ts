import type { Metadata } from "next";
import { PLANS } from "@/lib/plans";

/**
 * One source for every SEO fact on the site: the canonical host, the shared
 * copy, and the builders for per-page metadata and JSON-LD.
 *
 * The canonical host matters more here than on a normal site. This build is
 * served on two hostnames — verdure-app.com and the connectify-proto.vercel.app
 * deployment behind it — plus a preview URL per push. Without a canonical on
 * every page a crawler sees three identical copies of the same six pages and
 * splits the ranking signal between them. Everything below resolves against
 * SITE_URL so the copies all point home.
 */

export let SITE_URL = "https://verdure-app.com";
export let SITE_NAME = "Verdure";
export let SUPPORT_EMAIL = "support@verdure-app.com";

/**
 * ~155 characters on purpose: Google truncates the snippet around 160, so a
 * longer description loses its tail rather than gaining anything.
 */
export let SITE_DESCRIPTION =
  "Three real places to explore near you, every day. Check in to build a streak, earn points worth real gift cards, and find local events nearby. Launching soon.";

/** The brand line. Kept for share cards, where voice beats keywords. */
export let SITE_TAGLINE = "Verdure · Step Outside. Connect Within.";

let OG_IMAGE = {
  url: "/og.png",
  width: 1200,
  height: 630,
  type: "image/png",
  alt: "Verdure — three real places near you, every day",
};

export interface PageSeo
{
  /**
   * The page name only — the root layout's title template appends
   * "· Verdure". Omit it on the homepage to take the root default.
   */
  title?: string;
  description: string;
  /** Route path, e.g. "/pricing". Becomes the canonical and the og:url. */
  path: string;
  /** Share-card headline, when it should read differently from the title. */
  socialTitle?: string;
}

/**
 * Per-page metadata: canonical, plus an Open Graph and Twitter card that
 * describe *this* page. Without the override every sub-page inherits the
 * homepage card, so a link to /pricing shared anywhere reads "Step Outside.
 * Connect Within." instead of what the page is about.
 */
export function pageMetadata(page: PageSeo): Metadata
{
  let socialTitle =
    page.socialTitle || (page.title ? page.title + " · " + SITE_NAME : SITE_TAGLINE);

  return {
    // Spread rather than `title: page.title` — an explicit `undefined` here
    // does not fall through to the root layout's default, it overrides it,
    // and the homepage ships with no <title> at all.
    ...(page.title ? { title: page.title } : {}),
    description: page.description,
    alternates: { canonical: page.path },
    openGraph: {
      type: "website",
      siteName: SITE_NAME,
      url: page.path,
      title: socialTitle,
      description: page.description,
      images: [OG_IMAGE],
      locale: "en_US",
    },
    twitter: {
      card: "summary_large_image",
      title: socialTitle,
      description: page.description,
      images: [OG_IMAGE.url],
    },
  };
}

/** An absolute URL for JSON-LD, which may not use site-relative paths. */
export function absoluteUrl(path: string): string
{
  return path === "/" ? SITE_URL : SITE_URL + path;
}

/* --------------------------------------------------------------- JSON-LD */

let ORGANIZATION_ID = SITE_URL + "/#organization";
let WEBSITE_ID = SITE_URL + "/#website";

/**
 * The sitewide graph, emitted once from the root layout. Organization and
 * WebSite are the two entities every other node on the site points back at,
 * which is what lets a crawler treat six pages as one brand rather than six
 * unrelated documents.
 */
export function siteGraphLd(): Record<string, unknown>
{
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": ORGANIZATION_ID,
        name: SITE_NAME,
        url: SITE_URL,
        email: SUPPORT_EMAIL,
        description: SITE_DESCRIPTION,
        logo: {
          "@type": "ImageObject",
          url: absoluteUrl("/icon-512.png"),
          width: 512,
          height: 512,
        },
        contactPoint: [
          {
            "@type": "ContactPoint",
            contactType: "customer support",
            email: SUPPORT_EMAIL,
            availableLanguage: "English",
          },
        ],
      },
      {
        "@type": "WebSite",
        "@id": WEBSITE_ID,
        url: SITE_URL,
        name: SITE_NAME,
        description: SITE_DESCRIPTION,
        inLanguage: "en",
        publisher: { "@id": ORGANIZATION_ID },
      },
    ],
  };
}

/** "$4.99" -> "4.99". The plan file stores display strings, not numbers. */
let numericPrice = function (display: string): string
{
  return display.replace(/[^0-9.]/g, "");
};

let monthlyPrices = PLANS.map(function (plan)
{
  return Number(numericPrice(plan.price));
});

/**
 * The app itself, for the homepage. There is deliberately no aggregateRating:
 * the app has not launched, so it has no ratings, and inventing one is both a
 * lie and a manual-action risk. Availability is PreOrder for the same reason.
 */
export function appLd(): Record<string, unknown>
{
  return {
    "@context": "https://schema.org",
    "@type": "MobileApplication",
    "@id": SITE_URL + "/#app",
    name: SITE_NAME,
    url: SITE_URL,
    description: SITE_DESCRIPTION,
    applicationCategory: "LifestyleApplication",
    applicationSubCategory: "Outdoor recreation",
    operatingSystem: "iOS, Android",
    image: absoluteUrl("/og.png"),
    publisher: { "@id": ORGANIZATION_ID },
    isPartOf: { "@id": WEBSITE_ID },
    featureList: [
      "Three curated places near you each day",
      "Check in where you actually stand",
      "Daily streaks",
      "Points redeemable for gift cards",
      "Local community events",
    ],
    offers: {
      "@type": "AggregateOffer",
      priceCurrency: "USD",
      lowPrice: Math.min(...monthlyPrices).toFixed(2),
      highPrice: Math.max(...monthlyPrices).toFixed(2),
      offerCount: PLANS.length,
      availability: "https://schema.org/PreOrder",
    },
  };
}

/**
 * The plan table, for /pricing. Every price is read from lib/plans.ts — the
 * owner-supplied prices are the only ones that exist, so nothing here may
 * hardcode a number of its own.
 */
export function pricingLd(): Record<string, unknown>
{
  let offers = PLANS.flatMap(function (plan)
  {
    let monthly = {
      "@type": "Offer",
      name: plan.name,
      description: plan.tagline,
      price: numericPrice(plan.price),
      priceCurrency: "USD",
      availability: "https://schema.org/PreOrder",
      url: absoluteUrl("/pricing"),
    };

    if (!plan.annual)
    {
      return [monthly];
    }

    return [
      monthly,
      {
        "@type": "Offer",
        name: plan.name + " (annual)",
        description: "Billed annually",
        price: numericPrice(plan.annual),
        priceCurrency: "USD",
        availability: "https://schema.org/PreOrder",
        url: absoluteUrl("/pricing"),
      },
    ];
  });

  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    url: absoluteUrl("/pricing"),
    description:
      "Verdure Free costs nothing forever. Verdure+ adds the AI Adventure Planner, AR exploration, offline maps, and higher-value rewards.",
    applicationCategory: "LifestyleApplication",
    operatingSystem: "iOS, Android",
    publisher: { "@id": ORGANIZATION_ID },
    offers: offers,
  };
}

export interface Crumb
{
  name: string;
  path: string;
}

/**
 * Breadcrumbs for a sub-page. Google renders these in place of the raw URL in
 * the result, so /pricing shows "Verdure › Pricing" rather than the path.
 */
export function breadcrumbLd(trail: Crumb[]): Record<string, unknown>
{
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: trail.map(function (crumb, index)
    {
      return {
        "@type": "ListItem",
        position: index + 1,
        name: crumb.name,
        item: absoluteUrl(crumb.path),
      };
    }),
  };
}
