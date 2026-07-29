import type { Metadata } from "next";
import Link from "next/link";
import AuthForm from "@/components/auth/AuthForm";
import { signup } from "@/app/auth/actions";

export const metadata: Metadata = {
  // The root layout's title template appends "· Verdure".
  title: "Create Account",
  robots: { index: false },
};

export default function SignupPage()
{
  return (
    <>
      <header className="mb-7 text-center">
        <h1 className="font-display text-[clamp(1.9rem,5vw,2.4rem)] font-semibold leading-tight text-cream">
          Get Access
        </h1>
        <p className="mt-2 text-[0.98rem] text-cream/70">
          Create your account and start exploring your world.
        </p>
      </header>

      <AuthForm mode="signup" action={signup} />

      <p className="mt-7 text-center text-sm text-cream/70">
        Already have an account?{" "}
        <Link
          href="/login"
          className="link-underline font-semibold text-cream transition-colors duration-300"
        >
          Log in
        </Link>
      </p>
    </>
  );
}
