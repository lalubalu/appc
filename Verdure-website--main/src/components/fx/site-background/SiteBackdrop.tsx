"use client";

import { useEffect, useRef } from "react";
import { createScene, type SceneSettings } from "./scene";
import "lenis/dist/lenis.css";

/**
 * SiteBackdrop — the ground the whole site stands on. A photographic plate
 * redrawn every frame in WebGL2: the depth map pushes it into parallax, a
 * fluid field the cursor stirs bends it, and fog, grain, bloom and a lens
 * profile sit on top.
 *
 * It mounts once in the root layout, so it survives every client-side
 * navigation and the GL context is built one time per page load rather
 * than per route.
 *
 * The still plate underneath is not a placeholder. It renders on the
 * server, it is what a visitor without WebGL2 keeps, and the canvas only
 * cross-fades over it once a frame has actually been drawn.
 */

let COLOR_SRC = "/bg/mountain.jpg";
let DEPTH_SRC = "/bg/mountain-depth.jpg";
let PLATE_BG = "#0b120d";

type SiteBackdropProps = {
  /** How hard the cursor pushes the fluid field. 0 to 2.5. */
  fluidStrength?: number;
  /** Seconds the wake takes to fade once the cursor has gone. 0.4 to 4. */
  fluidDecay?: number;
  /** How closely the camera chases the scroll. 0.4 to 2.5. */
  scrollSpeed?: number;
  /** Weight of the aerial haze over the far ridges. 0 to 2. */
  fogDensity?: number;
  /** Bloom and the low sun halo. 0 to 2. */
  sunGlow?: number;
};

export default function SiteBackdrop({
  // Was 2.5 — the top of the range. Review liked the effect and asked for
  // less of it, so the cursor now stirs the field at about a third of
  // that: still there when you move, no longer a visible warp.
  fluidStrength = 0.85,
  fluidDecay = 0.4,
  scrollSpeed = 1,
  fogDensity = 0.2,
  sunGlow = 0,
}: SiteBackdropProps)
{
  let plateRef = useRef<HTMLImageElement | null>(null);
  let canvasRef = useRef<HTMLCanvasElement | null>(null);
  let settingsRef = useRef<SceneSettings>({
    fluidStrength: fluidStrength,
    fluidDecay: fluidDecay,
    scrollSpeed: scrollSpeed,
    fogDensity: fogDensity,
    sunGlow: sunGlow,
  });

  // The scene reads settings through the ref, so a prop change lands on
  // the next frame instead of rebuilding the whole GL context.
  useEffect(function ()
  {
    settingsRef.current = {
      fluidStrength: fluidStrength,
      fluidDecay: fluidDecay,
      scrollSpeed: scrollSpeed,
      fogDensity: fogDensity,
      sunGlow: sunGlow,
    };
  }, [fluidStrength, fluidDecay, scrollSpeed, fogDensity, sunGlow]);

  useEffect(function ()
  {
    let canvas = canvasRef.current;
    if (!canvas) return;

    let root = document.documentElement;
    let reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    // vd-bg-on is what flips the site's surface tokens dark. It goes on
    // before anything paints over the plate and comes off on teardown.
    root.classList.add("vd-bg-on");
    root.classList.remove("vd-bg-pinned");

    let scene = createScene({
      canvas: canvas,
      plate: plateRef.current,
      colorSrc: COLOR_SRC,
      depthSrc: DEPTH_SRC,
      reduced: reduced,
      settings: function ()
      {
        return settingsRef.current;
      },
      onPinned: function (isPinned)
      {
        root.classList.toggle("vd-bg-pinned", isPinned);
      },
    });

    return function ()
    {
      scene.destroy();
      root.classList.remove("vd-bg-on");
      root.classList.remove("vd-bg-pinned");
    };
  }, []);

  return (
    <div className="vd-bg-layer" style={{ background: PLATE_BG }} aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element -- this is the
          WebGL colour plate and the no-WebGL fallback in one element; a
          next/image wrapper buys nothing over a fixed decorative layer. */}
      <img
        ref={plateRef}
        className="vd-bg-plate"
        src={COLOR_SRC}
        alt=""
        fetchPriority="high"
        decoding="async"
        draggable={false}
      />
      <canvas ref={canvasRef} className="vd-bg-canvas" />
    </div>
  );
}
