/**
 * The two plans — owner-supplied names, prices, and features (2026-07-22
 * pricing change: Champion is gone). These are the ONLY plan facts that
 * exist; nothing here may be invented or extended without an owner
 * decision. Single source for /pricing and every other plan reference.
 */

export interface Plan
{
  name: string;
  price: string;
  cadence: string;
  /** The annual price shown beside the monthly one, when a plan has one. */
  annual: string;
  tagline: string;
  features: string[];
  featured: boolean;
}

export let PLANS: Plan[] = [
  {
    name: "Verdure Free",
    price: "$0.00",
    cadence: "",
    annual: "",
    tagline: "Forever free",
    features: [
      "Maps and public spaces",
      "Community events",
      "Daily Gem",
      "Basic gamification",
      "Points redeem for $5 to $10 gift cards",
      "Friend activity feed",
    ],
    featured: false,
  },
  {
    name: "Verdure+",
    price: "$4.99",
    cadence: "/mo",
    annual: "or $39.99/yr",
    tagline: "Everything in Free, plus:",
    features: [
      "AI Adventure Planner",
      "AR outdoor exploration",
      "Apple Health and Google Fit",
      "Offline maps and trail guidance",
      "Crowd forecasts and best times",
      "Higher-value rewards and multipliers",
      "Group planning tools",
      "AI-personalized challenges",
    ],
    featured: true,
  },
];
