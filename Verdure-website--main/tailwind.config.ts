import type { Config } from "tailwindcss";

let config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // Clean-light system. Legacy names stay wired so existing markup
        // keeps working: cream = high-emphasis text (now ink), ink = the
        // page ground (now paper). RGB-channel vars keep the opacity
        // modifiers working (text-cream/70, bg-accent/10, ...).
        cream: "rgb(var(--cream-rgb) / <alpha-value>)",
        ink: "rgb(var(--ink-rgb) / <alpha-value>)",
        accent: "rgb(var(--accent-rgb) / <alpha-value>)",
        "accent-ink": "var(--accent-ink)",
        line: "var(--line)",
        elev: "var(--elev)",
      },
      fontFamily: {
        // One family for everything readable — Plus Jakarta Sans (500 floor)
        sans: ["var(--font-body)", "system-ui", "sans-serif"],
        display: ["var(--font-body)", "system-ui", "sans-serif"],
        // Mono is fine print only (the build stamp)
        mono: ["ui-monospace", "Cascadia Mono", "Consolas", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
